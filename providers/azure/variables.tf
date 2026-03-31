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
  description = "Primary domain name for the platform (e.g. estabilis.io)."
  type        = string
}

variable "host_pattern" {
  description = "How application hostnames are constructed: subdomain (app.env.domain), prefix (env-app.domain), suffix (app-env.domain)."
  type        = string
  default     = "subdomain"

  validation {
    condition     = contains(["subdomain", "prefix", "suffix"], var.host_pattern)
    error_message = "host_pattern must be one of: subdomain, prefix, suffix."
  }
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
  description = "Version of the platform chart / manifests to deploy."
  type        = string
  default     = "0.1.0-alpha"
}

variable "config_repo_url" {
  description = "Git repository URL for client-specific value overrides. Leave empty to skip."
  type        = string
  default     = ""
}

variable "config_repo_version" {
  description = "Git revision (branch, tag, or SHA) for the config repository. Required if config_repo_url is set."
  type        = string
  default     = ""
}

variable "config_repo_token" {
  description = "Git access token for the config repository. Pass via secrets.auto.tfvars or TF_VAR_config_repo_token. Required if config_repo_url is a private repo."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure AD tenant ID. Can also be set via ARM_TENANT_ID environment variable."
  type        = string
  sensitive   = true
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
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D2s_v3"
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
  description = "OS disk size (GB) for system nodes. Must fit VM cache disk for ephemeral OS (D2s_v3=50GB, D4s_v3=100GB)."
  type        = number
  default     = 50
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
  description = "Enable the regular workload node pool."
  type        = bool
  default     = false
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

variable "workload_regular_max_count" {
  description = "Maximum nodes in the Regular (fallback) workload pool."
  type        = number
  default     = 2
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

variable "availability_zones" {
  description = "Availability zones for AKS node pools. Use [1,2,3] for production. Empty list disables zones."
  type        = list(string)
  default     = ["1", "2", "3"]
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

variable "nsg_enabled" {
  description = "Enable Network Security Group on AKS node subnet for defense in depth."
  type        = bool
  default     = true
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

variable "loki_external_ingress_enabled" {
  description = "Expose Loki push API externally via Traefik with BasicAuth. Requires loki-ingress-auth secret in grafana namespace."
  type        = bool
  default     = false
}

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

variable "storage_firewall_enabled" {
  description = "Enable network firewall (Deny by default) on storage accounts. When false, storage accounts are publicly accessible (authenticated only)."
  type        = bool
  default     = true
}

variable "storage_tfstate_extra_allowed_ips" {
  description = "Additional IP ranges allowed on tfstate storage only (on top of operator IP and NAT Gateway)."
  type        = list(string)
  default     = []
}

variable "storage_cnpg_extra_allowed_ips" {
  description = "Additional IP ranges allowed on CNPG backup storage only (on top of operator IP and NAT Gateway)."
  type        = list(string)
  default     = []
}

variable "storage_velero_extra_allowed_ips" {
  description = "Additional IP ranges allowed on Velero backup storage only (on top of operator IP and NAT Gateway)."
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

variable "loki_allowed_cidrs" {
  description = "Comma-separated list of CIDRs allowed to push logs to Loki external ingress. Empty string disables IP restriction."
  type        = string
  default     = ""
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
# Tags
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Default tags applied to every resource."
  type        = map(string)
  default = {
    project    = "estabilis"
    managed-by = "terraform"
  }
}
