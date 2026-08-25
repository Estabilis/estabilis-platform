# ---------------------------------------------------------------------------
# DOKS cluster
#
# DigitalOcean requires every cluster to carry an inline node_pool, so the
# default pool lives here rather than as a standalone resource. The inline
# block accepts labels and tags but NOT taints (provider schema v2.100) —
# pools that need taints go through additional_node_pools in node-pools.tf.
#
# The API server endpoint is always public on DOKS; control_plane_firewall is
# the only thing restricting it. See the safety check in main.tf.
# ---------------------------------------------------------------------------

resource "digitalocean_kubernetes_cluster" "this" {
  name    = local.cluster_name
  region  = var.region
  version = local.kubernetes_version_effective

  vpc_uuid = local.vpc_uuid_effective

  ha                   = var.ha_control_plane
  auto_upgrade         = var.auto_upgrade
  surge_upgrade        = var.surge_upgrade
  isolated_workers     = var.isolated_workers
  registry_integration = var.registry_integration

  # Null values let DigitalOcean assign; both are immutable after creation.
  cluster_subnet = var.cluster_subnet
  service_subnet = var.service_subnet

  kubeconfig_expire_seconds = var.kubeconfig_expire_seconds > 0 ? var.kubeconfig_expire_seconds : null

  # Off by default so `terraform destroy` cannot take load balancers and data
  # volumes with the cluster. Turn on only for disposable environments.
  destroy_all_associated_resources = var.destroy_all_associated_resources

  tags = local.do_tags

  node_pool {
    name       = var.default_node_pool.name
    size       = var.default_node_pool.size
    auto_scale = var.default_node_pool.auto_scale

    # DigitalOcean takes node_count as the pool's INITIAL size even when
    # auto_scale is on — it is not "unset means let the autoscaler decide".
    # Passing null lands 0 in state: the first apply of this module recorded
    # `node_count = 0` against a pool DigitalOcean reported as 4.
    #
    # It is inert today only because ignore_changes covers the attribute. Drop
    # that lifecycle rule, or hit a provider that stops honouring it, and
    # Terraform reconciles the pool to zero nodes — which is the cluster's
    # entire capacity. Send the real floor instead.
    node_count = var.default_node_pool.auto_scale ? var.default_node_pool.min_nodes : var.default_node_pool.node_count
    min_nodes  = var.default_node_pool.auto_scale ? var.default_node_pool.min_nodes : null
    max_nodes  = var.default_node_pool.auto_scale ? var.default_node_pool.max_nodes : null

    labels = var.default_node_pool.labels
    tags   = distinct(concat(local.do_tags, var.default_node_pool.tags))

    # A `dynamic` block and not a static one: with an empty list this emits
    # nothing at all, so every deployment that does not set taints renders
    # byte-identically to before.
    dynamic "taint" {
      for_each = var.default_node_pool.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  dynamic "control_plane_firewall" {
    for_each = var.control_plane_firewall_enabled ? [1] : []
    content {
      enabled           = true
      allowed_addresses = local.authorized_ips
    }
  }

  dynamic "maintenance_policy" {
    for_each = var.maintenance_policy != null ? [var.maintenance_policy] : []
    content {
      day        = maintenance_policy.value.day
      start_time = maintenance_policy.value.start_time
    }
  }

  dynamic "cluster_autoscaler_configuration" {
    for_each = var.cluster_autoscaler_configuration != null ? [var.cluster_autoscaler_configuration] : []
    content {
      expanders                        = cluster_autoscaler_configuration.value.expanders
      scale_down_unneeded_time         = cluster_autoscaler_configuration.value.scale_down_unneeded_time
      scale_down_utilization_threshold = cluster_autoscaler_configuration.value.scale_down_utilization_threshold
    }
  }

  dynamic "coredns_autoscaler" {
    for_each = var.coredns_autoscaler_enabled != null ? [var.coredns_autoscaler_enabled] : []
    content {
      enabled = coredns_autoscaler.value
    }
  }

  dynamic "routing_agent" {
    for_each = var.routing_agent_enabled != null ? [var.routing_agent_enabled] : []
    content {
      enabled = routing_agent.value
    }
  }

  dynamic "sso" {
    for_each = var.cluster_sso != null ? [var.cluster_sso] : []
    content {
      enabled    = sso.value.enabled
      issuer_url = sso.value.issuer_url
      client_id  = sso.value.client_id
      required   = sso.value.required
    }
  }

  lifecycle {
    ignore_changes = [
      # With auto_scale on, the autoscaler moves the live count constantly.
      # Without this, every plan after a scaling event shows a spurious diff
      # and an apply would scale the pool back to the last applied number.
      node_pool[0].node_count,
    ]

    # Unlike a `check` block, a failing precondition FAILS the plan. Every
    # assertion here guards something that cannot be undone cheaply once the
    # cluster exists.

    precondition {
      condition = (
        var.allow_public_api_endpoint ||
        (var.control_plane_firewall_enabled && length(local.authorized_ips) > 0)
      )
      error_message = "Refusing to create a DOKS cluster whose API server accepts any address. DigitalOcean has no private control plane, so control_plane_firewall is the only barrier there is. Set authorized_ip_ranges, or set allow_public_api_endpoint = true to state that this is intended."
    }

    precondition {
      condition     = !(var.operator_ip_autodetect && !local._operator_ip_valid && var.control_plane_firewall_enabled && length(var.authorized_ip_ranges) == 0)
      error_message = "operator_ip_autodetect is on but the address returned by api.ipify.org is not an IPv4 address, and authorized_ip_ranges is empty — the allowlist would be created empty, locking everyone out of a cluster that costs money to reach. Declare authorized_ip_ranges explicitly."
    }

    precondition {
      # Isolating workers removes their public IPv4 addresses, and on DOKS that
      # is their only egress path. Without a NAT gateway in the VPC the new
      # cluster comes up unable to pull a single image — every pod in
      # ImagePullBackOff, and no fix short of rebuilding again. Worse, this is
      # a REPLACEMENT: the working cluster is destroyed before the broken one
      # is discovered.
      condition     = !var.isolated_workers || var.nat_gateway_enabled
      error_message = "isolated_workers = true requires nat_gateway_enabled = true. Isolated nodes have no public address, so the VPC NAT Gateway is their only route out; without it the rebuilt cluster cannot pull images at all."
    }

    precondition {
      # DigitalOcean cannot downgrade a control plane. With auto_upgrade on,
      # DigitalOcean moves the patch version on its own schedule; with an exact
      # kubernetes_version pinned, the next plan then wants to move it back and
      # the API refuses. The two settings contradict each other.
      condition     = !(var.kubernetes_version != "" && var.auto_upgrade)
      error_message = "kubernetes_version pins an exact slug while auto_upgrade lets DigitalOcean move it. After the first automatic patch upgrade Terraform will plan a downgrade that the API rejects. Pin the version and set auto_upgrade = false, or leave kubernetes_version empty and track the series with kubernetes_version_prefix."
    }
  }
}

# ---------------------------------------------------------------------------
# Additional node pools — standalone resources, which is the only shape that
# accepts taints on DigitalOcean.
# ---------------------------------------------------------------------------

resource "digitalocean_kubernetes_node_pool" "this" {
  for_each = var.additional_node_pools

  cluster_id = digitalocean_kubernetes_cluster.this.id

  name       = each.key
  size       = each.value.size
  auto_scale = each.value.auto_scale

  # Same reasoning as the default pool above: initial size, not "unset".
  node_count = each.value.auto_scale ? each.value.min_nodes : each.value.node_count
  min_nodes  = each.value.auto_scale ? each.value.min_nodes : null
  max_nodes  = each.value.auto_scale ? each.value.max_nodes : null

  labels = each.value.labels
  tags   = distinct(concat(local.do_tags, each.value.tags))

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}
