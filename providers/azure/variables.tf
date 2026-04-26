variable "name_prefix" {
  description = "Prefix used for all resource names. Override per client."
  type        = string
  default     = "estabilis"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "domain" {
  description = "DNS zone root (e.g. estabilis.io). Must match the actual zone in Cloudflare or Azure DNS. Hostnames are derived as {app}.{cluster_name}.{domain}."
  type        = string
}

variable "environment" {
  description = "Deployment environment identifier."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "uat", "hml", "stg", "prd", "prod"], var.environment)
    error_message = "Environment must be one of: dev, uat, hml, stg, prd, prod."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster."
  type        = string
  default     = "1.34"
}

variable "auto_upgrade_channel" {
  description = "AKS auto-upgrade channel. Use 'patch' for production (security patches only), 'none' for manual control."
  type        = string
  default     = "patch"
}

variable "sku_tier" {
  description = "AKS SKU tier. 'Standard' for production SLA (99.95%, ~$75/mo), 'Free' for dev/test."
  type        = string
  default     = "Free"
}

variable "run_command_enabled" {
  description = "Enable Azure run command on AKS. Disable to reduce attack surface."
  type        = bool
  default     = false
}

variable "image_cleaner_enabled" {
  description = "Enable automatic image cleaner on AKS nodes to remove unused images."
  type        = bool
  default     = true
}

variable "image_cleaner_interval_hours" {
  description = "Interval in hours for the image cleaner scan."
  type        = number
  default     = 48
}

variable "platform_repo_url" {
  description = "Git repository URL for the platform manifests."
  type        = string
}

variable "platform_version" {
  description = <<-EOT
    [OVERRIDE] Version of the platform chart / manifests to deploy.

    Leave empty (default) — the module auto-derives from the VERSION
    file at the cloned source ref via file($${path.module}/../../VERSION).
    Single source of truth: bump only `main.tf` `ref=...`.

    Set explicitly only for overrides (e.g. local-path development
    sources, when path.module isn't a git-cloned ref).
  EOT
  type        = string
  default     = ""
}

variable "config_repo_url" {
  description = "Git repository URL for client-specific value overrides (downstream config repo)."
  type        = string

  validation {
    condition     = length(var.config_repo_url) > 0
    error_message = "config_repo_url is required. Set it to the downstream config repo URL."
  }
}

variable "config_repo_version" {
  description = "Git tag for the config repository (e.g., v1.0.0). Must be a pinned tag, not HEAD or a branch."
  type        = string

  validation {
    condition     = length(var.config_repo_version) > 0
    error_message = "config_repo_version is required. Set it to the downstream config repo git tag."
  }
}

variable "config_repo_token" {
  description = "Git access token for the config repository. Pass via secrets.auto.tfvars or TF_VAR_config_repo_token. Required if config_repo_url is a private repo."
  type        = string
  default     = ""
  sensitive   = true
}

variable "client_gitops_repo_url" {
  description = "Git repository URL for the client GitOps repo (apps, policies, workload overrides)."
  type        = string

  validation {
    condition     = length(var.client_gitops_repo_url) > 0
    error_message = "client_gitops_repo_url is required. Set it to the client GitOps repo URL."
  }
}

variable "deployment_id" {
  description = "Deployment identifier used as key in the client GitOps repo (e.g., platform-azure-eastus2-hml). Maps to platforms/{deployment_id}/ in the gitops repo."
  type        = string

  validation {
    condition     = length(var.deployment_id) > 0
    error_message = "deployment_id is required (e.g., platform-azure-eastus2-hml)."
  }
}

variable "client_gitops_repo_token" {
  description = "Git access token for the client GitOps repository. Pass via secrets.auto.tfvars. Required if clientGitopsRepoUrl (in overrides) points to a private repo."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure AD tenant ID. Can also be set via ARM_TENANT_ID environment variable."
  type        = string
  sensitive   = true
}

variable "platform_outputs_enabled" {
  description = "Write platform infrastructure values to a ConfigMap and Secret in the argocd namespace. Used by ArgoCD to configure platform components without the CLI."
  type        = bool
  default     = true
}

variable "subscription_id" {
  description = "Azure subscription ID. Can also be set via ARM_SUBSCRIPTION_ID environment variable."
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# AKS – System node pool
# ---------------------------------------------------------------------------

variable "system_vm_size" {
  description = "VM size for the system node pool. B2s (4GB) is sufficient when only_critical_addons_enabled = true."
  type        = string
  default     = "Standard_B2s"
}

variable "only_critical_addons_enabled" {
  description = "Taint system pool with CriticalAddonsOnly. Only AKS system components can run on it. Requires a workload pool for platform components."
  type        = bool
  default     = true
}

variable "system_node_count" {
  description = "Number of nodes in the system node pool. Used as initial count when autoscaling is enabled."
  type        = number
  default     = 3
}

variable "system_auto_scaling_enabled" {
  description = "Enable cluster autoscaler on the system node pool."
  type        = bool
  default     = false
}

variable "system_min_count" {
  description = "Minimum nodes in the system pool when autoscaling is enabled."
  type        = number
  default     = 2
}

variable "system_max_count" {
  description = "Maximum nodes in the system pool when autoscaling is enabled."
  type        = number
  default     = 4
}

variable "system_os_disk_size_gb" {
  description = "OS disk size (GB) for system nodes. Must fit VM cache disk for ephemeral OS (B2s=30GB, D2s_v3=50GB, D4s_v3=100GB)."
  type        = number
  default     = 30
}

variable "system_max_surge" {
  description = "Max surge for system node pool upgrades (percentage or absolute number)."
  type        = string
  default     = "10%"
}

# ---------------------------------------------------------------------------
# AKS – Workload node pool
# ---------------------------------------------------------------------------

variable "workload_regular_enabled" {
  description = "Enable the regular workload node pool. Required when only_critical_addons_enabled = true."
  type        = bool
  default     = true
}

variable "workload_spot_enabled" {
  description = "Enable the spot workload node pool."
  type        = bool
  default     = false
}

variable "workload_vm_size" {
  description = "VM size for the workload node pool."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "workload_os_disk_size_gb" {
  description = "OS disk size (GB) for workload nodes. Align to Azure managed disk tiers to avoid overpaying: 32 (P4 ~$1.54/mo), 64 (P6 ~$2.85/mo), 128 (P10 ~$3.80/mo), 256 (P15 ~$7.26/mo)."
  type        = number
  default     = 64
}

variable "workload_spot_max_count" {
  description = "Maximum nodes in the Spot workload pool."
  type        = number
  default     = 3
}

variable "workload_regular_min_count" {
  description = "Minimum nodes in the Regular workload pool. Use >= 2 for multi-zone HA."
  type        = number
  default     = 2
}

variable "workload_regular_max_count" {
  description = "Maximum nodes in the Regular workload pool."
  type        = number
  default     = 4
}

variable "workload_max_surge" {
  description = "Max surge for workload regular node pool upgrades (percentage or absolute number)."
  type        = string
  default     = "10%"
}

variable "workload_drain_timeout_in_minutes" {
  description = "Timeout for draining workload nodes during upgrades. 0 = no timeout."
  type        = number
  default     = 0
}

variable "workload_node_soak_duration_in_minutes" {
  description = "Duration to wait after draining a workload node before upgrading the next. 0 = no wait."
  type        = number
  default     = 0
}

variable "spot_max_price" {
  description = "Max price per hour for Spot node pool. -1 = market price (no limit)."
  type        = number
  default     = -1
}

# ---------------------------------------------------------------------------
# AKS – Network
# ---------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_nodes_prefix" {
  description = "Address prefix for the AKS nodes subnet."
  type        = string
  default     = "10.0.0.0/22"
}

variable "subnet_pods_prefix" {
  description = "Address prefix for the AKS pods subnet."
  type        = string
  default     = "10.0.4.0/22"
}

variable "service_cidr" {
  description = "CIDR for Kubernetes services."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes DNS service."
  type        = string
  default     = "172.16.0.10"
}

variable "pod_cidr" {
  description = "CIDR for Kubernetes pods (overlay)."
  type        = string
  default     = "10.244.0.0/16"
}

variable "network_dataplane" {
  description = "Network dataplane for AKS. Options: default (Azure), cilium (managed Cilium, no Hubble), cilium-acns (managed Cilium + Hubble/FQDN, ~$70/mo)."
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "cilium", "cilium-acns"], var.network_dataplane)
    error_message = "Network dataplane must be one of: default, cilium, cilium-acns."
  }
}

variable "system_os_disk_type" {
  description = "OS disk type for system node pool. Ephemeral uses VM local SSD (faster, no cost, limited by cache size)."
  type        = string
  default     = "Ephemeral"
}

variable "workload_os_disk_type" {
  description = "OS disk type for workload node pools. Managed allows larger disks (128GB default). Ephemeral is limited by VM cache."
  type        = string
  default     = "Managed"
}

variable "system_availability_zones" {
  description = "Availability zones for the system node pool."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "workload_availability_zones" {
  description = "Availability zones for workload node pools."
  type        = list(string)
  default     = ["1", "2", "3"]
}

# ---------------------------------------------------------------------------
# AKS – Azure AD & RBAC
# ---------------------------------------------------------------------------

variable "aad_managed_enabled" {
  description = "Enable Azure AD managed integration for AKS authentication."
  type        = bool
  default     = true
}

variable "azure_rbac_enabled" {
  description = "Enable Azure RBAC for Kubernetes authorization. Requires aad_managed_enabled."
  type        = bool
  default     = true
}

variable "local_account_disabled" {
  description = "Disable local accounts (certificate-based access). Requires aad_managed_enabled and aad_admin_group_ids configured."
  type        = bool
  default     = false
}

variable "aad_admin_group_ids" {
  description = "List of Azure AD group object IDs that receive cluster-admin role. Required when local_account_disabled = true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.local_account_disabled || length(var.aad_admin_group_ids) > 0
    error_message = "Cannot disable local accounts without configuring aad_admin_group_ids. Add at least one AAD group before setting local_account_disabled = true."
  }
}

variable "aks_role_assignments" {
  description = "List of Azure RBAC role assignments on the AKS cluster. Each entry needs principal_id and role name."
  type = list(object({
    principal_id = string
    role         = string
  }))
  default = []
}

variable "maintenance_window_day" {
  description = "Day of week for AKS planned maintenance window (e.g., Saturday)."
  type        = string
  default     = "Saturday"
}

variable "maintenance_window_start_hour" {
  description = "Start hour (UTC) for AKS planned maintenance window."
  type        = number
  default     = 2
}

variable "maintenance_window_duration" {
  description = "Duration in hours for AKS planned maintenance window."
  type        = number
  default     = 4
}

variable "azure_monitor_enabled" {
  description = "Enable Azure Monitor Agent on AKS nodes for infrastructure-level metrics. Opt-in — platform uses Grafana/Alloy/Mimir by default."
  type        = bool
  default     = false
}

variable "keyvault_soft_delete_days" {
  description = "Retention days for Key Vault soft delete. Minimum 7, maximum 90."
  type        = number
  default     = 7
}

variable "keyvault_purge_protection" {
  description = "Enable purge protection on Key Vault. Once enabled, cannot be disabled. Prevents teardown from purging KV immediately — must wait retention period (7 days). Disable for dev/test environments that do frequent destroy/recreate cycles."
  type        = bool
  default     = false
}

variable "nat_gateway_enabled" {
  description = "Enable NAT Gateway for controlled outbound traffic with static IP. Required for outboundType userDefinedRouting."
  type        = bool
  default     = true
}

variable "nat_gateway_idle_timeout" {
  description = "Idle timeout in minutes for NAT Gateway. Increase for long-lived connections (WebSocket, streaming). Max 120."
  type        = number
  default     = 4
}

variable "nsg_enabled" {
  description = "Enable Network Security Group on AKS node subnet for defense in depth."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Ingress (L7) — single toggle that controls Traefik presence, NSG HTTP(S)
# rules, and the public LoadBalancer. Mirror in ArgoCD via
# components.traefik in overrides/platform-root/values.yaml. Defaults OFF:
# clusters without external endpoints don't pay for Traefik / LB and don't
# open 80/443 on the node subnet.
# ---------------------------------------------------------------------------

variable "traefik_enabled" {
  description = "Enable Traefik ingress controller. When true, NSG opens 80/443 for ingress_allowed_ip_ranges and the chart is installed (components.traefik must also be true in the platform-root override)."
  type        = bool
  default     = false
}

variable "ingress_allowed_ip_ranges" {
  description = "Source IP CIDRs allowed to reach the Traefik public LoadBalancer on ports 80/443. Empty list means 'public' (0.0.0.0/0). Distinct from authorized_ip_ranges (which is for the AKS API server)."
  type        = list(string)
  default     = []
}

variable "traefik_internal_enabled" {
  description = "Enable a second Traefik instance dedicated to internal (VNet-only) exposures. When true, installs core/components/traefik-internal chart producing an ingressClass 'traefik-internal' backed by an Azure Internal LoadBalancer. Consumed by exposures with ingress_class='traefik-internal'."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# App exposures — map(object) model (ADR 0014). Each entry is a separate
# K8s Ingress + Traefik Middleware(s) + Certificate. Operator chooses
# ingress_class per profile to pin public vs internal routing.
#
# Key convention: profile name (e.g. "internal", "external", "vpn"); becomes
# part of resource names.
# ---------------------------------------------------------------------------

variable "grafana_exposures" {
  description = "Grafana ingress exposures. One entry per network profile. Leave empty to not expose Grafana. When host is empty, it is auto-derived as {app}.{cluster_name}.{domain} (app name: 'grafana')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")        # empty => auto-derived (see locals._app_host in main.tf)
    ingress_class = optional(string, "traefik") # "traefik" (public) or "traefik-internal"
    allowed_cidrs = optional(string, "")        # CSV; empty = no Middleware L7 filter
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false) # BasicAuth Middleware (htpasswd via ExternalSecret)

    # ALB-specific fields kept for type parity with AWS (Azure inert).
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "cert-manager")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default = {}
}

variable "loki_exposures" {
  description = "Loki push-API ingress exposures. Typically 'internal' for cluster-to-cluster log shipping. Leave empty to not expose Loki. When host is empty, it is auto-derived (app name: 'loki')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik-internal") # default to internal — loki push is usually VNet-scoped
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, true) # loki uses BasicAuth by default for push API

    # ALB-specific fields kept for type parity with AWS (Azure inert).
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "cert-manager")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default = {}
}

variable "mimir_exposures" {
  description = "Mimir remote-write ingress exposures. Used by workload clusters to push metrics to the hub. When host is empty, it is auto-derived (app name: 'mimir')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false)

    # ALB-specific fields kept for type parity with AWS (Azure inert).
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "cert-manager")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default = {}
}

variable "argocd_exposures" {
  description = "ArgoCD UI ingress exposures. Typically internal — ops team accesses via VPN. When host is empty, it is auto-derived (app name: 'argocd')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false) # ArgoCD has its own SSO

    # ALB-specific fields kept for type parity with AWS (Azure inert).
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "cert-manager")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default = {}
}

variable "hubble_ui_exposures" {
  description = "Hubble UI (Cilium ACNS) ingress exposures. Only rendered when network_dataplane=cilium-acns and components.hubble-ui=true. When host is empty, it is auto-derived (app name: 'hubble')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false)

    # ALB-specific fields kept for type parity with AWS (Azure inert).
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "cert-manager")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default = {}
}

variable "authorized_ip_ranges" {
  description = "List of authorized IP ranges for AKS API server access. Empty list makes API server private."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# ArgoCD
# ---------------------------------------------------------------------------

variable "argocd_chart_version" {
  description = "Helm chart version for ArgoCD."
  type        = string
  default     = "9.4.7"
}

# ---------------------------------------------------------------------------
# Observability – External Access
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

variable "cnpg_backup_retention_days" {
  description = "Retention period in days for CloudNativePG base backups."
  type        = number
  default     = 7
}

variable "cnpg_backup_schedule" {
  description = "Cron schedule for CloudNativePG daily backups."
  type        = string
  default     = "0 2 * * *"
}

variable "velero_backup_retention_hours" {
  description = "Retention period in hours for Velero backups."
  type        = number
  default     = 720
}

variable "velero_backup_schedule" {
  description = "Cron schedule for Velero full cluster backups."
  type        = string
  default     = "0 2 * * *"
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

variable "storage_replication_type" {
  description = "Default replication type for storage accounts. Per-storage overrides take precedence when set."
  type        = string
  default     = "ZRS"
}

variable "storage_replication_type_tfstate" {
  description = "Replication type for Terraform state storage. Empty string uses storage_replication_type."
  type        = string
  default     = ""
}

variable "storage_replication_type_observability" {
  description = "Replication type for observability storage (Loki/Mimir). Empty string uses storage_replication_type."
  type        = string
  default     = ""
}

variable "storage_replication_type_cnpg" {
  description = "Replication type for CNPG backup storage. Empty string uses storage_replication_type."
  type        = string
  default     = ""
}

variable "storage_replication_type_velero" {
  description = "Replication type for Velero backup storage. Empty string uses storage_replication_type."
  type        = string
  default     = ""
}

variable "storage_replication_type_cost_exports" {
  description = "Replication type for cost exports storage. Empty string uses storage_replication_type."
  type        = string
  default     = ""
}

variable "cost_export_enabled" {
  description = "Enable Azure Cost Management export and OpenCost integration. Disable if not using OpenCost or if another export already covers this subscription."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# ACR (Azure Container Registry)
# ---------------------------------------------------------------------------

variable "acr_enabled" {
  description = "Enable Azure Container Registry for private images and/or proxy cache."
  type        = bool
  default     = false
}

variable "shared_acr_login_server" {
  description = "Login server of the shared ACR (e.g. acrtransferosharedhml.azurecr.io). Used by ArgoCD Image Updater to monitor container registries. Leave empty if not using Image Updater."
  type        = string
  default     = ""
}

variable "acr_sku" {
  description = "ACR SKU. Basic (~$5/mo), Standard (~$10/mo), Premium (~$50/mo, supports private endpoint + geo-replication)."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be one of: Basic, Standard, Premium."
  }
}

variable "acr_aks_attach_enabled" {
  description = "Attach ACR to AKS with AcrPull role. Disable if using external ACR or CI-only registry."
  type        = bool
  default     = true
}

variable "acr_cache_enabled" {
  description = "Enable cache rules for public registries (Docker Hub, GHCR, Quay, etc.). Requires acr_enabled."
  type        = bool
  default     = true
}

variable "acr_cache_dockerhub_enabled" {
  description = "Enable Docker Hub cache rule. Requires acr_dockerhub_username and acr_dockerhub_token."
  type        = bool
  default     = false
}

variable "acr_dockerhub_username" {
  description = "Docker Hub username for authenticated cache pulls. Required when acr_cache_dockerhub_enabled = true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "acr_dockerhub_token" {
  description = "Docker Hub Personal Access Token for authenticated cache pulls. Required when acr_cache_dockerhub_enabled = true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "acr_firewall_enabled" {
  description = "Enable network firewall on ACR (Deny all + allow operator IP and AKS). Requires Premium SKU."
  type        = bool
  default     = true
}

variable "acr_content_trust_enabled" {
  description = "Enable content trust (image signing verification). Requires Premium SKU."
  type        = bool
  default     = false
}

variable "acr_retention_days" {
  description = "Days to retain untagged manifests. 0 = disabled. Requires Premium SKU."
  type        = number
  default     = 30
}

variable "acr_private_endpoint_enabled" {
  description = "Enable private endpoint for ACR (no public access). Requires Premium SKU."
  type        = bool
  default     = false
}

variable "acr_georeplications" {
  description = "List of Azure regions for geo-replication. Requires Premium SKU."
  type        = list(string)
  default     = []
}

variable "acr_push_principal_ids" {
  description = "List of Azure AD principal IDs (users, groups, service principals) to grant AcrPush."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Azure DevOps automation (ADR 0015) — opt-in feature: Terraform creates an
# AAD App + SP + AcrPush role + ADO Service Connection (Workload Identity
# Federation, Manual mode) + Federated Identity Credential. Pipelines then
# reference the Service Connection by name to push images/charts to the ACR
# without managing any secret.
#
# Caller permissions required when enabled:
#   - Tenant: Application Administrator (to create AAD App + SP)
#   - ADO project: Project Administrator OR Service Connection Administrator
# Authentication is via az cli (no PAT) — provider piggybacks on AZURE_CONFIG_DIR.
# ---------------------------------------------------------------------------

variable "azdo_push_automation_enabled" {
  description = "Create a Terraform-managed Service Principal + ADO Service Connection (WIF) for ACR push. When true, azdo_organization_url and azdo_project must be set."
  type        = bool
  default     = false
}

variable "azdo_organization_url" {
  description = "Azure DevOps organization URL (e.g., https://dev.azure.com/<org>). Required when azdo_push_automation_enabled=true."
  type        = string
  default     = ""
}

variable "azdo_project" {
  description = "Azure DevOps project name where the Service Connection will be created. Required when azdo_push_automation_enabled=true."
  type        = string
  default     = ""
}

variable "acr_ci_identity_enabled" {
  description = "Create a dedicated managed identity for CI/CD push to ACR. Outputs client_id for federated credential setup."
  type        = bool
  default     = false
}

variable "acr_extra_allowed_ips" {
  description = "Additional IP ranges allowed on ACR only (on top of global firewall rules). Requires Premium SKU."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Resource Firewall (centralized network access control)
# ---------------------------------------------------------------------------

variable "firewall_enabled" {
  description = "Enable network firewall on all resources (Key Vault, Storage). When false, all resources are publicly accessible (authenticated only)."
  type        = bool
  default     = true
}

variable "firewall_allowed_ips" {
  description = "IP ranges allowed on ALL firewalled resources (VPN, CI/CD, office IPs). Operator IP and NAT Gateway IP are always included automatically."
  type        = list(string)
  default     = []
}

variable "firewall_allowed_subnet_ids" {
  description = "Subnet IDs allowed on ALL firewalled resources. AKS node subnet is always included automatically."
  type        = list(string)
  default     = []
}

variable "keyvault_extra_allowed_ips" {
  description = "Additional IP ranges allowed on Key Vault only (on top of global firewall rules)."
  type        = list(string)
  default     = []
}

variable "storage_tfstate_extra_allowed_ips" {
  description = "Additional IP ranges allowed on tfstate storage only (on top of global firewall rules)."
  type        = list(string)
  default     = []
}

variable "storage_cnpg_extra_allowed_ips" {
  description = "Additional IP ranges allowed on CNPG backup storage only (on top of global firewall rules)."
  type        = list(string)
  default     = []
}

variable "storage_velero_extra_allowed_ips" {
  description = "Additional IP ranges allowed on Velero backup storage only (on top of global firewall rules)."
  type        = list(string)
  default     = []
}

variable "storage_soft_delete_enabled" {
  description = "Enable blob and container soft delete on all storage accounts."
  type        = bool
  default     = true
}

variable "storage_soft_delete_retention_days" {
  description = "Retention days for blob and container soft delete on all storage accounts. Only used when storage_soft_delete_enabled is true."
  type        = number
  default     = 14
}

variable "storage_protect_critical" {
  description = "Apply Azure resource locks on critical storage accounts (tfstate, cnpg-backup, velero) to prevent accidental deletion. Must be removed before teardown/destroy."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

variable "diagnostics_enabled" {
  description = "Enable AKS diagnostic settings (Log Analytics + audit logs). Disable for dev/test to save costs."
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Retention days for Log Analytics Workspace (AKS audit logs)."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# DNS provider
# ---------------------------------------------------------------------------

variable "dns_provider" {
  description = "DNS provider for external-dns and cert-manager DNS-01 solver. 'azure' uses Azure DNS + Workload Identity (Terraform manages the zone, managed identity, and role assignment). 'cloudflare' uses Cloudflare API with a static API token — the zone must already exist in Cloudflare and NS records must be delegated there."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "cloudflare"], var.dns_provider)
    error_message = "dns_provider must be one of: azure, cloudflare."
  }
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID (UUID shown in the Cloudflare Dashboard → domain → Overview → API section). Required when dns_provider = 'cloudflare'."
  type        = string
  default     = ""

  validation {
    condition     = var.dns_provider != "cloudflare" || length(var.cloudflare_zone_id) > 0
    error_message = "cloudflare_zone_id is required when dns_provider = 'cloudflare'."
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read + DNS:Edit scopes on the target zone. Required when dns_provider = 'cloudflare'. Pass via secrets.auto.tfvars or TF_VAR_cloudflare_api_token."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.dns_provider != "cloudflare" || length(var.cloudflare_api_token) > 0
    error_message = "cloudflare_api_token is required when dns_provider = 'cloudflare'."
  }
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt ACME account registration."
  type        = string
}

# ---------------------------------------------------------------------------
# LLM / AI
# ---------------------------------------------------------------------------

variable "openai_api_key" {
  description = "OpenAI API key for Grafana LLM plugin (flame graph AI analysis). Pass via secrets.auto.tfvars or TF_VAR_openai_api_key."
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Tags (Azure CAF recommended)
# ---------------------------------------------------------------------------

# --- Functional ---

variable "tag_app" {
  description = "CAF Functional: application name. Defaults to name_prefix if empty."
  type        = string
  default     = ""
}

variable "tag_tier" {
  description = "CAF Functional: application tier (infrastructure, platform, application)."
  type        = string
  default     = "platform"

  validation {
    condition     = var.tag_tier == "" || contains(["infrastructure", "platform", "application", "database", "web", "api"], var.tag_tier)
    error_message = "Tier must be one of: infrastructure, platform, application, database, web, api (or empty to omit)."
  }
}

# --- Classification ---

variable "tag_criticality" {
  description = "CAF Classification: criticality level."
  type        = string
  default     = ""

  validation {
    condition     = var.tag_criticality == "" || contains(["mission-critical", "high", "medium", "low"], var.tag_criticality)
    error_message = "Criticality must be one of: mission-critical, high, medium, low (or empty to omit)."
  }
}

variable "tag_confidentiality" {
  description = "CAF Classification: data confidentiality level."
  type        = string
  default     = ""

  validation {
    condition     = var.tag_confidentiality == "" || contains(["public", "internal", "confidential", "restricted"], var.tag_confidentiality)
    error_message = "Confidentiality must be one of: public, internal, confidential, restricted (or empty to omit)."
  }
}

variable "tag_sla" {
  description = "CAF Classification: expected SLA (e.g., 99.9, 99.95, 99.99)."
  type        = string
  default     = ""
}

# --- Accounting ---

variable "tag_costcenter" {
  description = "CAF Accounting: cost center for billing attribution."
  type        = string
  default     = ""
}

variable "tag_department" {
  description = "CAF Accounting: department responsible for the cost."
  type        = string
  default     = ""
}

variable "tag_budget" {
  description = "CAF Accounting: budget associated with the workload."
  type        = string
  default     = ""
}

# --- Purpose ---

variable "tag_businessprocess" {
  description = "CAF Purpose: business process this workload supports."
  type        = string
  default     = ""
}

variable "tag_businessimpact" {
  description = "CAF Purpose: impact if this workload is unavailable."
  type        = string
  default     = ""

  validation {
    condition     = var.tag_businessimpact == "" || contains(["critical", "high", "moderate", "low", "none"], var.tag_businessimpact)
    error_message = "Business impact must be one of: critical, high, moderate, low, none (or empty to omit)."
  }
}

variable "tag_revenueimpact" {
  description = "CAF Purpose: revenue impact if this workload is unavailable."
  type        = string
  default     = ""

  validation {
    condition     = var.tag_revenueimpact == "" || contains(["high", "moderate", "low", "none"], var.tag_revenueimpact)
    error_message = "Revenue impact must be one of: high, moderate, low, none (or empty to omit)."
  }
}

# --- Ownership ---

variable "tag_opsteam" {
  description = "CAF Ownership: operations team responsible for this workload."
  type        = string
  default     = ""
}

variable "tag_businessunit" {
  description = "CAF Ownership: business unit that owns this workload."
  type        = string
  default     = ""
}

# --- Extra ---

variable "extra_tags" {
  description = "Additional tags to merge with the CAF set."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Shared Hub Key Vault (cross-deployment secret sharing)
# ---------------------------------------------------------------------------

variable "shared_hub_kv_enabled" {
  description = "Create a shared RG with a Key Vault for hub connection values consumed by workload clusters. Required when workload clusters use data sources instead of manual tfvars."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# HashiCorp Vault (v0.27.0+ — multi-provider opt-in component)
# ---------------------------------------------------------------------------
# Toggle to provision the Azure-side Vault infrastructure (dedicated Key
# Vault for unseal key, Storage Account for snapshot backups, Workload
# Identity). When false, NO resources are created — clean teardown on
# flip back to false (no purge_protection on the dedicated KV).
#
# Companion: estabilis-platform-gitops v0.38.0+ ships the chart values
# overlay (values/platform/vault.yaml, vault-azure.yaml) and the triple-belt
# coverage (network-policies, resource-quotas, kyverno-policies).

variable "vault_enabled" {
  description = "Provision Vault infrastructure (dedicated KV unseal key, Storage Account backup, Workload Identity) and render the platform-root Application. Toggle false to remove all Vault resources cleanly (no purge protection on the dedicated KV)."
  type        = bool
  default     = false
}

variable "vault_chart_version" {
  description = "HashiCorp Vault Helm chart version (https://helm.releases.hashicorp.com)."
  type        = string
  default     = "0.29.1"
}

variable "vault_backup_retention_days" {
  description = "Days to retain Raft snapshot backups in the Storage Account container. CronJob is deferred to a follow-up; the bucket + lifecycle is provisioned here so future enablement needs no role assignment."
  type        = number
  default     = 30
}

variable "vault_kv_soft_delete_days" {
  description = "Soft-delete retention on the dedicated Vault Key Vault. Range 7-90 days. Set low for cleaner toggle-off; set higher when teams want a wider undelete window. NO purge_protection here — `vault_enabled = false` must remove the resource."
  type        = number
  default     = 7

  validation {
    condition     = var.vault_kv_soft_delete_days >= 7 && var.vault_kv_soft_delete_days <= 90
    error_message = "vault_kv_soft_delete_days must be between 7 and 90."
  }
}

variable "vault_storage_replication_type" {
  description = "Replication type for the Vault Raft snapshot Storage Account. LRS=cheapest single-region; ZRS=zone-redundant; GRS/RAGRS=geo-redundant. Defaults to LRS for foundation cost; clients with HA backup needs override to ZRS or GRS."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.vault_storage_replication_type)
    error_message = "vault_storage_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "vault_exposures" {
  description = "Vault UI ingress exposures (multi-network ingress per profile). Same shape as other *_exposures vars. Typically internal — ops team via VPN. When host is empty, it is auto-derived (app name: 'vault')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik-internal")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false)

    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "/v1/sys/health?standbyok=true")
    alb_certificate_source = optional(string, "cert-manager")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default = {}
}
