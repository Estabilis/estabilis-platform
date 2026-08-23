# ---------------------------------------------------------------------------
# Provider configuration
#
# The DigitalOcean provider reads its token from DIGITALOCEAN_ACCESS_TOKEN (or
# DIGITALOCEAN_TOKEN) when `token` is null. That is the preferred path: a token
# passed through var.do_token lands in the state file, whereas an environment
# variable does not.
#
# There is no default_tags equivalent on this provider — DigitalOcean tags are
# flat strings attached per resource, so local.do_tags is applied by hand on
# every resource that supports tagging. See the tag projection below.
# ---------------------------------------------------------------------------

provider "digitalocean" {
  token = var.do_token != "" ? var.do_token : null

  # Spaces is S3-compatible and authenticates with an access-key pair that has
  # nothing to do with the API token above. Leaving these null makes the
  # provider read SPACES_ACCESS_KEY_ID / SPACES_SECRET_ACCESS_KEY from the
  # environment, which is the preferred path — a value passed as a variable is
  # recorded in the state file.
  spaces_access_id  = var.spaces_access_id != "" ? var.spaces_access_id : null
  spaces_secret_key = var.spaces_secret_key != "" ? var.spaces_secret_key : null
}

# The kubernetes provider, for platform-outputs.tf and nothing else. The helm
# provider is still absent: this module writes the handoff and stops, and ArgoCD
# installs everything after it.
#
# DIGITALOCEAN HAS NO EXEC-PLUGIN AUTH. EKS shells out to `aws eks get-token`
# and AKS to `az aks get-credentials`, so on both the provider holds a command
# and mints a fresh token per run. Here the token is an attribute of the cluster
# resource and it EXPIRES — kubeconfig_expire_seconds, seven days by default.
#
# What that means in practice: a plan run against a state older than the expiry
# refreshes the cluster first and picks up a new token, so it works. A plan run
# from a stale state file without refresh does not. If a plan here fails
# authenticating, refresh before believing the cluster is unreachable.
provider "kubernetes" {
  host                   = try(digitalocean_kubernetes_cluster.this.endpoint, null)
  token                  = try(digitalocean_kubernetes_cluster.this.kube_config[0].token, null)
  cluster_ca_certificate = try(base64decode(digitalocean_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate), null)
}

# ---------------------------------------------------------------------------
# CAF naming + tags — key names kept byte-compatible with the AWS and Azure
# providers so client downstream tfvars reuse the same CAF tag keys across
# clouds.
# ---------------------------------------------------------------------------

locals {
  env_code = {
    dev  = "dev"
    uat  = "uat"
    hml  = "hml"
    stg  = "stg"
    prd  = "prd"
    prod = "prd"
  }[var.environment]

  # DigitalOcean region slugs carry no separators (nyc3, atl1, fra1), so the
  # slug goes into resource names verbatim.
  region_code = var.region

  base_name = "${var.name_prefix}-platform-${local.env_code}-${local.region_code}"

  cluster_name = var.cluster_name_override != "" ? var.cluster_name_override : "doks-${local.base_name}"

  module_version = trimspace(file("${path.module}/../../VERSION"))

  # CAF tags — the same map the AWS and Azure providers build, in the same
  # key-value shape. Nothing on DigitalOcean consumes it directly (see the
  # projection below); it exists so the platform ConfigMap can publish the
  # full-fidelity set once platform-outputs.tf lands, and so the three
  # providers stay comparable line by line.
  caf_tags = {
    for k, v in {
      # Functional
      app        = coalesce(var.tag_app, var.name_prefix)
      env        = local.env_code
      region     = var.region
      tier       = var.tag_tier
      managed-by = "terraform"
      # Provenance — upstream platform module (always populated)
      platform_source  = "https://github.com/Estabilis/estabilis-platform"
      platform_version = local.module_version
      # Provenance — client repo (passed through; filtered when empty)
      source  = var.repo_url
      version = var.client_version
      # Classification
      criticality     = var.tag_criticality
      confidentiality = var.tag_confidentiality
      sla             = var.tag_sla
      # Accounting
      costcenter = var.tag_costcenter
      department = var.tag_department
      budget     = var.tag_budget
      # Purpose
      businessprocess = var.tag_businessprocess
      businessimpact  = var.tag_businessimpact
      revenueimpact   = var.tag_revenueimpact
      # Ownership
      opsteam      = var.tag_opsteam
      businessunit = var.tag_businessunit
    } : k => v if v != ""
  }

  tags = merge(local.caf_tags, var.extra_tags)
}

# ---------------------------------------------------------------------------
# DigitalOcean tag projection
#
# DigitalOcean tags are flat strings, not key-value pairs: `digitalocean_tag`
# has a name and nothing else. The convention already in use on this account
# ("project:nsights-risk-ops", "environment:staging") encodes the pair into
# one string, and that is what this projection does — "env:prd", not { env =
# "prd" }.
#
# Two consequences worth stating plainly:
#
#   1. Values that are not [A-Za-z0-9_-] are DROPPED, not mangled. That covers
#      the two provenance URLs (platform_source, source) and any dotted value
#      such as a semver `version`/`platform_version` or an `sla` of "99.95".
#      Those survive at full fidelity in local.tags and reach the cluster
#      through the platform ConfigMap instead. Silently rewriting "99.95" to
#      "99-95" would put a value in the console that matches nothing anyone
#      searches for, so dropping is the honest failure.
#
#      The pattern is deliberately narrower than what the API may accept. If
#      dots turn out to be legal, widen it here — widening adds tags, and
#      never breaks an apply that used to work.
#
#   2. A DigitalOcean tag is an ACCOUNT-GLOBAL object, not a per-resource
#      pair. "env:prd" is one object shared by every resource in the account
#      that carries it, including resources this module does not manage. On a
#      shared account, set do_tags_enabled = false.
#
# Coverage is partial by platform limitation: DOKS clusters, node pools and
# database clusters accept tags; VPCs and Spaces buckets have no tag field at
# all (confirmed against provider schema v2.100).
# ---------------------------------------------------------------------------

locals {
  _do_tag_safe = "^[A-Za-z0-9_-]+$"

  do_tags = var.do_tags_enabled ? [
    for k, v in local.tags : "${k}:${v}" if can(regex(local._do_tag_safe, v))
  ] : []

  # Surfaced as an output so an operator can see what fell out of the
  # projection without diffing two maps by hand.
  do_tags_dropped = var.do_tags_enabled ? [
    for k, v in local.tags : k if !can(regex(local._do_tag_safe, v))
  ] : keys(local.tags)
}

# ---------------------------------------------------------------------------
# Kubernetes version resolution
#
# An exact kubernetes_version wins. Otherwise the latest patch in the
# kubernetes_version_prefix series is resolved at plan time, so patch bumps
# arrive by re-running plan rather than by editing tfvars.
#
# Note this makes the version a plan-time lookup: a new patch published by
# DigitalOcean shows up as a diff. That is the intent, but it also means an
# unattended apply can move the control plane. Pin kubernetes_version where
# that is unacceptable.
# ---------------------------------------------------------------------------

data "digitalocean_kubernetes_versions" "selected" {
  version_prefix = var.kubernetes_version_prefix
}

locals {
  kubernetes_version_effective = (
    var.kubernetes_version != ""
    ? var.kubernetes_version
    : data.digitalocean_kubernetes_versions.selected.latest_version
  )
}

# ---------------------------------------------------------------------------
# Operator IP — auto-detected, and appended to the DOKS API server allowlist
# when the control plane firewall is on.
#
# Convenient for a laptop workflow: whoever applies keeps reaching the API
# without editing the allowlist. It becomes a liability the moment something
# NON-INTERACTIVE runs Terraform, because "whoever applies" is then a CI
# runner:
#
#   - the detected address changes on every run, so the plan never converges;
#   - hosted runner addresses come from a SHARED pool, so allowlisting one does
#     not authorise "our CI" — it authorises whatever workload happens to hold
#     that address.
#
# Unlike the AWS provider, the list here is rebuilt from var.authorized_ip_ranges
# on every apply rather than unioned with prior state, so stale operator
# addresses do not accumulate on the allowlist — they fall off next apply.
#
# The data source is gated too: with autodetect off nothing calls out to
# api.ipify.org, so a run from a network that cannot reach it does not fail for
# a value it would discard.
# ---------------------------------------------------------------------------

data "http" "operator_ip" {
  count = var.operator_ip_autodetect && var.control_plane_firewall_enabled ? 1 : 0
  url   = "https://api.ipify.org"
}

locals {
  # Guard the response shape. ipify normally returns a bare address, but a
  # captive portal or a proxy error page returns HTML with a 200, and that
  # would otherwise be concatenated into "<!DOCTYPE html.../32" and shipped to
  # the DigitalOcean API as an allowlist entry.
  _operator_ip_raw = try(chomp(data.http.operator_ip[0].response_body), "")
  _operator_ip_valid = can(
    regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", local._operator_ip_raw)
  )

  operator_ips = (
    var.operator_ip_autodetect && var.control_plane_firewall_enabled && local._operator_ip_valid
    ? ["${local._operator_ip_raw}/32"]
    : []
  )

  # Egress addresses of the NAT gateway, as /32s.
  #
  # These MUST be in the API allowlist whenever workers are isolated, and the
  # reason is not obvious until it bites: an isolated node has no public
  # address, so its kubelet reaches the control plane THROUGH the NAT gateway.
  # The control plane firewall then sees the gateway's address, not the node's.
  # Leave it out and the nodes boot, pull images fine, register — and then go
  # NotReady with "Kubelet stopped posting node status", because the platform's
  # own firewall is dropping the kubelet. Observed exactly that way.
  #
  # Derived rather than configured, so turning on isolated_workers cannot
  # forget it.
  nat_egress_ips = [
    for gw in try(one(digitalocean_vpc_nat_gateway.this[*].egresses)[0].public_gateways, []) :
    "${gw.ipv4}/32"
  ]

  # Ordering is part of the value here: `allowed_addresses` is a LIST in the
  # provider schema, and DigitalOcean returns it in its own order. Produce a
  # different sequence with identical contents and Terraform reports a change,
  # applies it, and reports it again next plan — a diff that never converges
  # and quietly trains people to ignore "1 to change".
  #
  # DigitalOcean orders NUMERICALLY by octet, which plain sort() does not do:
  # sort() is lexicographic, so it puts "191.209.43.153" before "45.55.98.208"
  # while the API returns 45 first. That distinction is invisible while every
  # address happens to start with a similar digit — an earlier fix used sort()
  # and looked correct for exactly as long as the NAT address began with 1.
  #
  # Zero-padding each octet makes a lexicographic sort agree with a numeric
  # one, so the map below is keyed by the padded form and read back in key
  # order.
  _authorized_ips_raw = distinct(concat(var.authorized_ip_ranges, local.operator_ips, local.nat_egress_ips))

  _authorized_ips_by_sortkey = {
    for cidr in local._authorized_ips_raw :
    join(".", [for octet in split(".", split("/", cidr)[0]) : format("%03d", tonumber(octet))]) => cidr
  }

  authorized_ips = [
    for k in sort(keys(local._authorized_ips_by_sortkey)) : local._authorized_ips_by_sortkey[k]
  ]
}

# ---------------------------------------------------------------------------
# Safety gate — refuse to expose the Kubernetes API to the internet without an
# explicit acknowledgement.
#
# DigitalOcean has no private control plane, so "firewall off" and "firewall on
# with an empty list" both mean the API server answers the whole internet.
# Neither should happen by omission.
#
# This is enforced as a resource `precondition`, NOT a `check` block. A failing
# check emits a warning and Terraform proceeds — verified: plan exits 0 with
# "Warning: Check block assertion failed" and still reports "3 to add". A
# precondition fails the plan. For a gate whose whole purpose is to stop an
# apply, only the second one is worth anything.
#
# The check below is kept as an EARLY signal: it evaluates before the resource
# graph and surfaces the same problem at the top of the output. It does not
# enforce; the precondition in doks.tf does.
# ---------------------------------------------------------------------------

check "public_api_endpoint_requires_acknowledgement" {
  assert {
    condition = (
      var.allow_public_api_endpoint ||
      (var.control_plane_firewall_enabled && length(local.authorized_ips) > 0)
    )
    error_message = "The DOKS API server would be reachable from any address. Either set authorized_ip_ranges to a non-empty list with control_plane_firewall_enabled = true (optionally letting operator_ip_autodetect fill it), or opt in explicitly with allow_public_api_endpoint = true."
  }
}
