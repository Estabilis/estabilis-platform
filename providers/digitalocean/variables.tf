# ---------------------------------------------------------------------------
# Core identification
# ---------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix used for all resource names. Override per client."
  type        = string
  default     = "estabilis"
  nullable    = false
}

variable "region" {
  description = "DigitalOcean region slug for all resources (e.g., nyc3, atl1, fra1). Must be a region where DOKS is offered."
  type        = string
  default     = "nyc3"
  nullable    = false
}

variable "environment" {
  description = "Deployment environment identifier."
  type        = string
  default     = "prd"
  nullable    = false

  validation {
    condition     = contains(["dev", "uat", "hml", "stg", "prd", "prod"], var.environment)
    error_message = "Environment must be one of: dev, uat, hml, stg, prd, prod."
  }
}

variable "deployment_id" {
  description = "Deployment identifier used as key in the client GitOps repo (e.g., platform-digitalocean-nyc3-prd). Maps to platforms/{deployment_id}/ in the gitops repo."
  type        = string

  validation {
    condition     = length(var.deployment_id) > 0
    error_message = "deployment_id is required (e.g., platform-digitalocean-nyc3-prd)."
  }
}

variable "do_token" {
  description = "DigitalOcean API token. Prefer leaving empty and exporting DIGITALOCEAN_ACCESS_TOKEN so the value never reaches a tfvars file or the plan output."
  type        = string
  default     = ""
  nullable    = false
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Provenance — client repo identity, tagged onto resources that accept tags
# ---------------------------------------------------------------------------

variable "repo_url" {
  description = "Client repository URL (https://...). Carried as CAF `source` for provenance. DigitalOcean tag names cannot hold a URL (see main.tf), so this reaches resources through the platform ConfigMap rather than the tag set. Empty value (default) omits it."
  type        = string
  default     = ""
  nullable    = false
}

variable "client_version" {
  description = "Client deployment semver (e.g. \"1.10.5\"). Computed in the client tfvars from CHANGELOG.md regex. Carried as CAF `version`. Empty value (default) omits it."
  type        = string
  default     = ""
  nullable    = false
}

# ---------------------------------------------------------------------------
# CAF tags — key names kept byte-compatible with the AWS and Azure providers
# so a client's downstream tfvars carries across clouds unchanged.
# ---------------------------------------------------------------------------

variable "tag_app" {
  description = "CAF Functional: application name. Defaults to name_prefix if empty."
  type        = string
  default     = ""
  nullable    = false
}

variable "tag_tier" {
  description = "CAF Functional: application tier (infrastructure, platform, application)."
  type        = string
  default     = "platform"
  nullable    = false

  validation {
    condition     = var.tag_tier == "" || contains(["infrastructure", "platform", "application", "database", "web", "api"], var.tag_tier)
    error_message = "Tier must be one of: infrastructure, platform, application, database, web, api (or empty to omit)."
  }
}

variable "tag_criticality" {
  description = "CAF Classification: criticality level."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.tag_criticality == "" || contains(["mission-critical", "high", "medium", "low"], var.tag_criticality)
    error_message = "Criticality must be one of: mission-critical, high, medium, low (or empty to omit)."
  }
}

variable "tag_confidentiality" {
  description = "CAF Classification: data confidentiality level."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.tag_confidentiality == "" || contains(["public", "internal", "confidential", "restricted"], var.tag_confidentiality)
    error_message = "Confidentiality must be one of: public, internal, confidential, restricted (or empty to omit)."
  }
}

variable "tag_sla" {
  description = "CAF Classification: expected SLA (e.g., 99.9, 99.95, 99.99). Dots are stripped by the DigitalOcean tag projection — see main.tf."
  type        = string
  default     = ""
  nullable    = false
}

variable "tag_costcenter" {
  description = "CAF Accounting: cost center for billing attribution."
  type        = string
  default     = ""
  nullable    = false
}

variable "tag_department" {
  description = "CAF Accounting: department responsible for the cost."
  type        = string
  default     = ""
  nullable    = false
}

variable "tag_budget" {
  description = "CAF Accounting: budget associated with the workload."
  type        = string
  default     = ""
  nullable    = false
}

variable "tag_businessprocess" {
  description = "CAF Purpose: business process this workload supports."
  type        = string
  default     = ""
  nullable    = false
}

variable "tag_businessimpact" {
  description = "CAF Purpose: impact if this workload is unavailable."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.tag_businessimpact == "" || contains(["critical", "high", "moderate", "low", "none"], var.tag_businessimpact)
    error_message = "Business impact must be one of: critical, high, moderate, low, none (or empty to omit)."
  }
}

variable "tag_revenueimpact" {
  description = "CAF Purpose: revenue impact if this workload is unavailable."
  type        = string
  default     = ""
  nullable    = false
}

variable "tag_opsteam" {
  description = "CAF Ownership: team operating the workload."
  type        = string
  default     = ""
  nullable    = false
}

variable "tag_businessunit" {
  description = "CAF Ownership: business unit owning the workload."
  type        = string
  default     = ""
  nullable    = false
}

variable "extra_tags" {
  description = "Additional CAF tags merged over the computed set. Keys collide-and-win against the built-ins."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "do_tags_enabled" {
  description = "Project the CAF tag map onto DigitalOcean's flat `key:value` tag strings. DigitalOcean tags are account-global objects shared by every resource in the account — set false when the account is shared and tag collisions are unwanted."
  type        = bool
  default     = true
  nullable    = false
}

# ---------------------------------------------------------------------------
# VPC
#
# DigitalOcean assigns an ip_range automatically when none is given, and that
# is the default here: the provider picks a free /20 in the region and the
# operator never has to reason about collisions. Downstreams that need a
# specific range (peering, on-prem overlap) set vpc_ip_range explicitly.
# ---------------------------------------------------------------------------

variable "vpc_mode" {
  description = "Whether to create a VPC or attach the cluster to an existing one. `create` provisions digitalocean_vpc; `existing` requires vpc_uuid."
  type        = string
  default     = "create"
  nullable    = false

  validation {
    condition     = contains(["create", "existing"], var.vpc_mode)
    error_message = "vpc_mode must be one of: create, existing."
  }
}

variable "vpc_uuid" {
  description = "UUID of an existing VPC. Required when vpc_mode = \"existing\", ignored otherwise."
  type        = string
  default     = ""
  nullable    = false
}

variable "vpc_name" {
  description = "Name of the VPC to create. Empty derives `vpc-{base_name}`."
  type        = string
  default     = ""
  nullable    = false
}

variable "vpc_description" {
  description = "Free-text description on the created VPC."
  type        = string
  default     = "Managed by Estabilis Platform"
  nullable    = false
}

variable "vpc_ip_range" {
  description = "CIDR for the created VPC (e.g. 10.20.0.0/20). Null (default) lets DigitalOcean allocate a free range automatically — the documented provider default. DigitalOcean cannot change a VPC ip_range in place, so a later edit forces replacement of the VPC and everything attached."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# DOKS — Kubernetes version
#
# version_prefix keeps patch upgrades flowing while pinning the minor. An
# exact kubernetes_version wins when set, for deployments that must not move.
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Exact DOKS version slug (e.g. \"1.36.3-do.2\"). Empty (default) resolves the latest patch matching kubernetes_version_prefix."
  type        = string
  default     = ""
  nullable    = false
}

variable "kubernetes_version_prefix" {
  description = "Minor series to track when kubernetes_version is empty (e.g. \"1.36.\"). Trailing dot matters — \"1.3\" would also match 1.30-1.39."
  type        = string
  default     = "1.36."
  nullable    = false
}

# ---------------------------------------------------------------------------
# DOKS — cluster behaviour
# ---------------------------------------------------------------------------

variable "cluster_name_override" {
  description = "Full cluster name, bypassing the derived `doks-{name_prefix}-platform-{env}-{region}`. Empty (default) uses the derived name."
  type        = string
  default     = ""
  nullable    = false
}

variable "ha_control_plane" {
  description = "Highly-available DOKS control plane. Adds roughly USD 40/month. DigitalOcean cannot turn HA back off once enabled."
  type        = bool
  default     = false
  nullable    = false
}

variable "auto_upgrade" {
  description = "Let DigitalOcean apply patch upgrades to the control plane during the maintenance window."
  type        = bool
  default     = true
  nullable    = false
}

variable "surge_upgrade" {
  description = "Create replacement nodes before draining the old ones during upgrades. Costs one extra node briefly; avoids capacity dips."
  type        = bool
  default     = true
  nullable    = false
}

variable "isolated_workers" {
  description = "Provision worker nodes without public IPv4 addresses. The DOKS control plane endpoint stays public regardless — DigitalOcean has no private control plane. Egress then requires a NAT path, so leave false until one exists."
  type        = bool
  default     = false
  nullable    = false
}

variable "registry_integration" {
  description = "Bind the account's DigitalOcean Container Registry to the cluster, injecting an imagePullSecret into namespaces. Not required to run the platform — DOKS pulls from any registry via imagePullSecrets, and the platform charts are published to GHCR."
  type        = bool
  default     = false
  nullable    = false
}

variable "cluster_subnet" {
  description = "CIDR for pod IPs. Null (default) accepts the DigitalOcean-assigned range. Immutable after creation."
  type        = string
  default     = null
}

variable "service_subnet" {
  description = "CIDR for service ClusterIPs. Null (default) accepts the DigitalOcean-assigned range. Immutable after creation."
  type        = string
  default     = null
}

variable "kubeconfig_expire_seconds" {
  description = "Lifetime of the credential embedded in the generated kubeconfig. 0 (default) uses the DigitalOcean default of 7 days."
  type        = number
  default     = 0
  nullable    = false
}

variable "destroy_all_associated_resources" {
  description = "On cluster destroy, also delete load balancers, volumes and volume snapshots the cluster created. Off by default so a `terraform destroy` cannot silently take data volumes with it."
  type        = bool
  default     = false
  nullable    = false
}

variable "maintenance_policy" {
  description = "Maintenance window for control-plane patching. `day` accepts any/monday..sunday; `start_time` is a 24h UTC hour like \"04:00\". Null (default) leaves DigitalOcean's own schedule in place."
  type = object({
    day        = optional(string)
    start_time = optional(string)
  })
  default = null
}

variable "cluster_autoscaler_configuration" {
  description = "Tuning for the DOKS-managed cluster autoscaler. Null (default) keeps DigitalOcean's defaults."
  type = object({
    expanders                        = optional(list(string))
    scale_down_unneeded_time         = optional(string)
    scale_down_utilization_threshold = optional(number)
  })
  default = null
}

variable "coredns_autoscaler_enabled" {
  description = "Scale CoreDNS with cluster size. Null (default) leaves the DigitalOcean default untouched."
  type        = bool
  default     = null
}

variable "routing_agent_enabled" {
  description = "DigitalOcean routing agent. Null (default) leaves the DigitalOcean default untouched."
  type        = bool
  default     = null
}

variable "cluster_sso" {
  description = "OIDC single sign-on for the cluster API. Null (default) disables it. `required` forces every kubectl session through the issuer."
  type = object({
    enabled    = bool
    issuer_url = optional(string)
    client_id  = optional(string)
    required   = optional(bool)
  })
  default = null
}

# ---------------------------------------------------------------------------
# DOKS — control plane firewall (API server allowlist)
#
# The DigitalOcean equivalent of the AKS `api_server_authorized_ip_ranges` and
# the EKS `public_access_cidrs`. Same variable names as the other providers so
# a downstream carries across unchanged.
#
# What DigitalOcean does NOT have is a private control plane: the endpoint is
# always reachable from the internet and this allowlist is the only thing in
# front of it. There is no cluster_endpoint_private_access equivalent to fall
# back on, which makes the allowlist load-bearing rather than defence in depth.
# ---------------------------------------------------------------------------

variable "control_plane_firewall_enabled" {
  description = "Restrict the DOKS API server to authorized_ip_ranges (plus the operator IP when autodetected). Disabling it leaves the API server open to the internet."
  type        = bool
  default     = true
  nullable    = false
}

variable "authorized_ip_ranges" {
  description = "CIDRs allowed to reach the Kubernetes API server. Empty with control_plane_firewall_enabled = true and allow_public_api_endpoint = false fails the safety check below rather than silently opening the API."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "allow_public_api_endpoint" {
  description = "Explicit acknowledgement that the API server may be reachable from any address. Required to apply with the firewall disabled, or enabled with an empty allowlist."
  type        = bool
  default     = false
  nullable    = false
}

variable "operator_ip_autodetect" {
  description = "Append the applying machine's public IP to the API allowlist. Convenient from a laptop; a liability from CI, where the address comes from a shared pool, changes every run, and accumulates in the allowlist. Set false for any non-interactive apply and declare the CIDRs instead."
  type        = bool
  default     = true
  nullable    = false
}

# ---------------------------------------------------------------------------
# DOKS — node pools
#
# The default pool is declared inline on the cluster because DigitalOcean
# requires a cluster to always have one. The inline block accepts labels and
# tags but NOT taints — that is a DigitalOcean schema limitation, not a
# choice here. Pools that need taints go in additional_node_pools, which is
# rendered as separate digitalocean_kubernetes_node_pool resources.
# ---------------------------------------------------------------------------

variable "default_node_pool" {
  description = <<-EOT
    The cluster's built-in node pool. auto_scale honours min_nodes/max_nodes;
    node_count is used only when auto_scale is false.

    Defaults to a SINGLE node, pinned (min == max). Two reasons:

      - A cluster with nothing on it costs what its floor costs. One node runs
        the DaemonSets (cilium, csi, telemetry) plus coredns, konnectivity and
        hubble in roughly 800m of 1900m allocatable CPU — comfortable.
      - Pinning min == max stops the transient scale-up seen on every bootstrap:
        pods go briefly unschedulable while nodes are still joining, the
        autoscaler reacts, and the cluster sits at max for ten minutes before
        collapsing back. With a spread of 2..4 that is 96 USD/month of nodes
        that exist for a few minutes and then vanish.

    THIS DOES NOT FIT THE PLATFORM STACK. ArgoCD, Grafana, Loki, Mimir, Alloy,
    Tempo, Vault, Trivy, Velero and CNPG together need several nodes. Raise
    this before those land, sized against their actual requests rather than by
    guess. A single node also means no HA at all: a node upgrade or reboot is
    total downtime, and surge_upgrade has no capacity to build a replacement
    first.
  EOT
  type = object({
    name       = optional(string, "default")
    size       = optional(string, "s-2vcpu-4gb")
    auto_scale = optional(bool, true)
    node_count = optional(number, 1)
    min_nodes  = optional(number, 1)
    max_nodes  = optional(number, 1)
    labels     = optional(map(string), {})
    tags       = optional(list(string), [])
  })
  default  = {}
  nullable = false
}

variable "additional_node_pools" {
  description = "Extra node pools keyed by name, created as standalone resources so they can carry taints. Deleting a key destroys the pool and drains its nodes."
  type = map(object({
    size       = string
    auto_scale = optional(bool, true)
    node_count = optional(number, 1)
    min_nodes  = optional(number, 1)
    max_nodes  = optional(number, 3)
    labels     = optional(map(string), {})
    tags       = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = optional(string, "")
      effect = string
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for pool in var.additional_node_pools : alltrue([
        for taint in pool.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], taint.effect)
      ])
    ])
    error_message = "Taint effect must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  }
}

# ---------------------------------------------------------------------------
# Spaces — Terraform state bucket
#
# Spaces credentials are NOT the DigitalOcean API token. The provider takes
# them separately (spaces_access_id / spaces_secret_key), and without them
# every bucket operation fails with a signature error rather than a clear
# permission message. Prefer the environment variables so neither value ever
# reaches a tfvars file or the state.
# ---------------------------------------------------------------------------

variable "tfstate_bucket_enabled" {
  description = "Create the Spaces bucket that will hold Terraform state. Requires Spaces credentials. Set false to run entirely on local state."
  type        = bool
  default     = true
  nullable    = false
}

variable "spaces_access_id" {
  description = "Spaces access key ID. Prefer exporting SPACES_ACCESS_KEY_ID instead of setting this — a value here is recorded in the state."
  type        = string
  default     = ""
  nullable    = false
  sensitive   = true
}

variable "spaces_secret_key" {
  description = "Spaces secret key. Prefer exporting SPACES_SECRET_ACCESS_KEY instead of setting this — a value here is recorded in the state."
  type        = string
  default     = ""
  nullable    = false
  sensitive   = true
}

variable "spaces_region" {
  description = "Region for the state bucket. Empty (default) follows var.region. Override when the cluster runs in a region where Spaces is not offered."
  type        = string
  default     = ""
  nullable    = false
}

variable "tfstate_bucket_name_override" {
  description = "Full bucket name, bypassing the derived `{name_prefix}-tfstate-{env}-{suffix}`. Spaces bucket names are globally unique across all DigitalOcean accounts, so a fixed name can collide with a stranger's."
  type        = string
  default     = ""
  nullable    = false
}

variable "tfstate_versioning_enabled" {
  description = "Keep prior versions of the state object. This is the rollback path when a write corrupts state — turning it off is a decision to have none."
  type        = bool
  default     = true
  nullable    = false
}

variable "tfstate_force_destroy" {
  description = "Allow `terraform destroy` to delete the state bucket while it still holds objects. False keeps DigitalOcean refusing, which is what stops a stray destroy from taking the state with it."
  type        = bool
  default     = false
  nullable    = false
}

variable "tfstate_deny_insecure_transport" {
  description = "Attach a bucket policy denying non-TLS requests. INCOMPATIBLE with tfstate_key_enabled: DigitalOcean only allows account-wide keys on a bucket that has a policy. Defaults off so the scoped key is possible."
  type        = bool
  default     = false
  nullable    = false
}

variable "project_mode" {
  description = "How this deployment relates to a DigitalOcean Project. `create` provisions one and attaches the cluster (and state bucket); `existing` attaches to var.project_id; `none` leaves resources in the account default."
  type        = string
  default     = "create"
  nullable    = false

  validation {
    condition     = contains(["create", "existing", "none"], var.project_mode)
    error_message = "project_mode must be one of: create, existing, none."
  }
}

variable "project_id" {
  description = "UUID of an existing project. Required when project_mode = \"existing\"."
  type        = string
  default     = ""
  nullable    = false
}

variable "project_name" {
  description = "Project name. Empty derives `{name_prefix}-platform-{env}`. Unlike most names here, this one is shown to humans in the console, so a downstream may well want something like \"N-Sights IDP Platform\"."
  type        = string
  default     = ""
  nullable    = false
}

variable "project_description" {
  description = "Project description shown in the DigitalOcean console."
  type        = string
  default     = "Estabilis Platform deployment"
  nullable    = false
}

variable "project_purpose" {
  description = "Project purpose. DigitalOcean suggests a fixed list in the UI but accepts free text; anything unrecognised is stored as `Other: <value>`."
  type        = string
  default     = "Service or API"
  nullable    = false
}

variable "tfstate_key_enabled" {
  description = "Create the Spaces key the backend authenticates with. Independent of tfstate_bucket_enabled on purpose: the key is created with the API token and must exist BEFORE the bucket, because creating a bucket requires Spaces credentials. Its secret is stored in the Terraform state."
  type        = bool
  default     = true
  nullable    = false
}

variable "tfstate_bootstrap_key_enabled" {
  description = "Create a TEMPORARY account-wide Spaces key so the state bucket can be created at all. DigitalOcean rejects a bucket-scoped grant for a bucket that does not exist, so this is the only way in. Set false once the bucket and the scoped key exist — leaving it on is how an account accumulates fullaccess keys."
  type        = bool
  default     = false
  nullable    = false
}

# ---------------------------------------------------------------------------
# VPC NAT Gateway
# ---------------------------------------------------------------------------

variable "nat_gateway_enabled" {
  description = "Provision a VPC NAT Gateway to give the VPC an egress path. Required before isolated_workers can be turned on — isolated nodes have no other way out."
  type        = bool
  default     = false
  nullable    = false
}

variable "nat_gateway_name_override" {
  description = "Gateway name. Empty derives `nat-{name_prefix}-platform-{env}-{region}`."
  type        = string
  default     = ""
  nullable    = false
}

variable "nat_gateway_type" {
  description = "Gateway type. PUBLIC is the value the API accepts; anything else returns `invalid nat gateway type passed`."
  type        = string
  default     = "PUBLIC"
  nullable    = false
}

variable "nat_gateway_size" {
  description = "Gateway size, as a count. The API accepts 1 and 2; 4 returns `exceeded NAT Gateway size limit`. No published pricing — cost appears on the invoice."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.nat_gateway_size >= 1 && var.nat_gateway_size <= 2
    error_message = "nat_gateway_size must be 1 or 2 — DigitalOcean rejects larger values."
  }
}

variable "nat_gateway_tcp_timeout_seconds" {
  description = "Idle TCP flow timeout. Null keeps the DigitalOcean default."
  type        = number
  default     = null
}

variable "nat_gateway_udp_timeout_seconds" {
  description = "Idle UDP flow timeout. Null keeps the DigitalOcean default."
  type        = number
  default     = null
}

variable "nat_gateway_icmp_timeout_seconds" {
  description = "Idle ICMP flow timeout. Null keeps the DigitalOcean default."
  type        = number
  default     = null
}

# ---------------------------------------------------------------------------
# Platform component storage
#
# Off by default. Turn each on with the component that consumes it — see
# storage.tf.
# ---------------------------------------------------------------------------

variable "observability_bucket_enabled" {
  description = "Bucket and scoped key for Loki, Mimir and Tempo. Enable with those components."
  type        = bool
  default     = false
  nullable    = false
}

variable "velero_bucket_enabled" {
  description = "Bucket and scoped key for Velero backups. Enable with components.velero."
  type        = bool
  default     = false
  nullable    = false
}

variable "cnpg_bucket_enabled" {
  description = "Bucket and scoped key for CNPG backups. Unlikely on DigitalOcean, where Grafana uses a managed PostgreSQL instead of CNPG."
  type        = bool
  default     = false
  nullable    = false
}

variable "velero_noncurrent_retention_days" {
  description = "Expire non-current Velero object versions after N days. 0 keeps them forever."
  type        = number
  default     = 30
  nullable    = false
}

# ============================================================================
# Container registry
# ============================================================================
# A deliberately smaller surface than ecr_* or acr_*. See registry.tf: the
# missing capabilities are missing from DigitalOcean, not from this module.

variable "registry_enabled" {
  description = "Create a DigitalOcean Container Registry. Off by default. Note that the subscription tier is account-wide, and that starter and basic permit only one registry per account — an account already holding one cannot create a second on those tiers."
  type        = bool
  default     = false
  nullable    = false
}

variable "registry_sole_account_registry" {
  description = "Acknowledge that this deployment owns the account's only container registry. Required when registry_subscription_tier is starter or basic, because those tiers permit one registry and set the subscription for the entire account. Leave false on a shared account and use professional, which permits ten."
  type        = bool
  default     = false
  nullable    = false
}

variable "registry_subscription_tier" {
  description = "starter (free, 1 repo, 500 MiB), basic (USD 5/mo, 5 repos, 5 GiB) or professional (USD 20/mo, unlimited repos, 100 GiB, up to 10 registries). ACCOUNT-WIDE: this sets the subscription covering every registry on the account."
  type        = string
  default     = "basic"
  nullable    = false

  validation {
    condition     = contains(["starter", "basic", "professional"], var.registry_subscription_tier)
    error_message = "registry_subscription_tier must be starter, basic or professional."
  }
}

variable "registry_purpose" {
  description = "Naming discriminator, as acr_purpose is on Azure: `<name_prefix>[-<purpose>]-<env>[-<suffix>]`. Empty by default."
  type        = string
  default     = ""
  nullable    = false
}

variable "registry_random_suffix_enabled" {
  description = "Append the deployment's shared 6-character suffix to the registry name. On by default: registry names are globally unique across DigitalOcean, so a bare `<prefix>-<env>` collides with any other account that thought of it first."
  type        = bool
  default     = true
  nullable    = false
}

variable "registry_name_override" {
  description = "Exact registry name, bypassing the derived one. Globally unique across DigitalOcean, lowercase alphanumeric and hyphens."
  type        = string
  default     = null
}

variable "registry_region" {
  description = "Registry region. Defaults to the deployment region. Fixed at creation and not all regions host registries."
  type        = string
  default     = ""
  nullable    = false
}

variable "registry_ci_credentials_enabled" {
  description = "Emit a read-write Docker credential for CI to push with. Registry-wide: DigitalOcean has no scope maps, so a credential that may push may push to every repository. The cluster does not need this — registry_integration covers pulls."
  type        = bool
  default     = false
  nullable    = false
}

variable "registry_pull_credentials_enabled" {
  description = "Emit a read-only Docker credential, for pulls from outside the cluster. In-cluster pulls are covered by registry_integration."
  type        = bool
  default     = false
  nullable    = false
}

variable "registry_credentials_expiry_seconds" {
  description = "Lifetime of the emitted Docker credentials. 0 leaves them non-expiring. A finite value is safer and noisier: Terraform proposes a new credential once the expiry passes, and whatever consumes it must be re-fed on that cadence."
  type        = number
  default     = 0
  nullable    = false
}
