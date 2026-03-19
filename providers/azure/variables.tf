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

variable "environment" {
  description = "Deployment environment identifier."
  type        = string
  default     = "homolog"

  validation {
    condition     = contains(["dev", "homolog", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, homolog, staging, production."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster."
  type        = string
  default     = "1.34"
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
  description = "Number of nodes in the system node pool."
  type        = number
  default     = 2
}

variable "system_os_disk_size_gb" {
  description = "OS disk size (GB) for system nodes."
  type        = number
  default     = 50
}

# ---------------------------------------------------------------------------
# AKS – Workload node pool
# ---------------------------------------------------------------------------

variable "workload_vm_size" {
  description = "VM size for the workload node pool."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "workload_os_disk_size_gb" {
  description = "OS disk size (GB) for workload nodes."
  type        = number
  default     = 50
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
  default     = "10.0.1.0/24"
}

variable "subnet_pods_prefix" {
  description = "Address prefix for the AKS pods subnet."
  type        = string
  default     = "10.0.2.0/23"
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
