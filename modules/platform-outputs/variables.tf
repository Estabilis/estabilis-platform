variable "platform_repo_url" {
  description = "Git repository URL for the platform manifests."
  type        = string
  default     = ""
  nullable    = false
}
variable "platform_version" {
  description = <<-EOT
    [LEGACY/OVERRIDE] Version of the platform chart / manifests to deploy.

    Leave empty (default) for the recommended path: the module
    auto-derives the version from the VERSION file at the cloned source
    ref. Set explicitly only when overriding (local-path module sources,
    branch refs without VERSION, etc).

    Backward-compat: explicit value still wins over VERSION file.
  EOT
  type        = string
  default     = ""
  nullable    = false
}
variable "platform_revision" {
  description = <<-EOT
    [OVERRIDE] Git revision for the platform repo (tag OR branch).

    Leave empty (default) — the module auto-derives from the VERSION
    file at the cloned source ref via file($${path.module}/../../VERSION).
    Single source of truth: bump only `main.tf` `ref=...`.

    Set explicitly only for overrides (e.g. local-path development
    sources, when path.module isn't a git-cloned ref).
  EOT
  type        = string
  default     = ""
  nullable    = false
}
variable "config_repo_url" {
  description = "Git repository URL for client-specific value overrides (downstream config repo)."
  type        = string

  validation {
    condition     = var.config_repo_url == "" || (length(var.config_repo_url) > 0)
    error_message = "Empty is allowed and means the platform handoff is not in use; when it is, platform_outputs_enabled fails the plan instead. Otherwise: config_repo_url is required. Set it to the downstream config repo URL."
  }
  default  = ""
  nullable = false
}
variable "config_repo_version" {
  description = "Git tag for the config repository (deprecated — prefer config_repo_revision). Kept for backward compatibility."
  type        = string
  default     = ""
  nullable    = false
}
variable "config_repo_revision" {
  description = "Git revision for the config repository (tag OR branch, e.g. 'v1.0.0' or 'release/prod'). Empty falls back to config_repo_version. ADR 0020."
  type        = string
  default     = ""
  nullable    = false
}
variable "client_gitops_repo_url" {
  description = "Git repository URL for the client GitOps repo (apps, policies, workload overrides)."
  type        = string

  validation {
    condition     = var.client_gitops_repo_url == "" || (length(var.client_gitops_repo_url) > 0)
    error_message = "Empty is allowed and means the platform handoff is not in use; when it is, platform_outputs_enabled fails the plan instead. Otherwise: client_gitops_repo_url is required. Set it to the client GitOps repo URL."
  }
  default  = ""
  nullable = false
}
variable "client_gitops_repo_version" {
  description = "Git tag for the client GitOps repo (deprecated — prefer client_gitops_repo_revision). Kept for backward compatibility."
  type        = string
  default     = ""
  nullable    = false
}
variable "client_gitops_repo_revision" {
  description = "Git revision for the client GitOps repo (tag OR branch). Empty falls back to client_gitops_repo_version. ADR 0020."
  type        = string
  default     = ""
  nullable    = false
}
variable "deployment_id" {
  description = "Deployment identifier used as key in the client GitOps repo (e.g., platform-digitalocean-nyc3-prd). Maps to platforms/{deployment_id}/ in the gitops repo."
  type        = string

  validation {
    condition     = length(var.deployment_id) > 0
    error_message = "deployment_id is required (e.g., platform-digitalocean-nyc3-prd)."
  }
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
variable "region" {
  description = "DigitalOcean region slug for all resources (e.g., nyc3, atl1, fra1). Must be a region where DOKS is offered."
  type        = string
  default     = "nyc3"
  nullable    = false
}
variable "domain" {
  description = "DNS zone root (e.g. estabilis.io). Must match the actual zone in Route53 or Cloudflare. Hostnames are derived as {app}.{cluster_name}.{domain}."
  type        = string
  default     = ""
  nullable    = false
}
variable "dns_provider" {
  description = "DNS provider for external-dns and cert-manager DNS-01 solver. 'route53' uses AWS Route53 + IRSA (Terraform manages the zone + IAM role). 'cloudflare' uses Cloudflare API with a static token (zone must already exist). 'none' disables external-dns + DNS-01 issuance (useful when DNS is manual)."
  type        = string
  default     = "route53"

  validation {
    condition     = contains(["route53", "cloudflare", "none"], var.dns_provider)
    error_message = "dns_provider must be one of: route53, cloudflare, none."
  }
  nullable = false
}
variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID (UUID from the Cloudflare Dashboard). Required when dns_provider = 'cloudflare'."
  type        = string
  default     = ""

  validation {
    condition     = var.dns_provider != "cloudflare" || length(var.cloudflare_zone_id) > 0
    error_message = "cloudflare_zone_id is required when dns_provider = 'cloudflare'."
  }
  nullable = false
}
variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read + DNS:Edit scopes. Required when dns_provider = 'cloudflare'. Pass via secrets.auto.tfvars or TF_VAR_cloudflare_api_token."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.dns_provider != "cloudflare" || length(var.cloudflare_api_token) > 0
    error_message = "cloudflare_api_token is required when dns_provider = 'cloudflare'."
  }
  nullable = false
}
variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt ACME account registration (used by cert-manager)."
  type        = string
  default     = ""
  nullable    = false
}
variable "ingress_controller" {
  description = "Ingress controller strategy. 'traefik': Traefik + NLB/ELB (consistent with Azure path). 'alb': AWS Load Balancer Controller + ALB (AWS-native, ACM-friendly). 'none': no public ingress (internal-only cluster)."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["traefik", "alb", "none"], var.ingress_controller)
    error_message = "ingress_controller must be one of: traefik, alb, none."
  }
  nullable = false
}
variable "traefik_internal" {
  description = "Whether the deployment runs a second, internal-only Traefik alongside the public one."
  type        = bool
  default     = false
  nullable    = false
}
variable "argocd_url" {
  description = "External URL ArgoCD answers on. Empty derives `https://argocd.<domain>`, which is the convention every other exposure follows."
  type        = string
  default     = ""
  nullable    = false
}
variable "argocd_exposures" {
  description = "ArgoCD UI ingress exposures. Typically internal — ops team accesses via VPN. When host is empty, auto-derived (app: 'argocd')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false)

    # ALB-specific (only consumed when ingress_class = "alb").
    # Provider-agnostic shape so Azure exposures keep the same type.
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "acm")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default  = {}
  nullable = false
}
variable "grafana_exposures" {
  description = "Grafana ingress exposures. One entry per network profile. Leave empty to not expose. When host is empty, it is auto-derived as {app}.{cluster_name}.{domain} (app: 'grafana')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false)

    # ALB-specific (only consumed when ingress_class = "alb").
    # Provider-agnostic shape so Azure exposures keep the same type.
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "acm")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default  = {}
  nullable = false
}
variable "loki_exposures" {
  description = "Loki push-API ingress exposures. Typically 'internal' for cluster-to-cluster log shipping. When host is empty, auto-derived (app: 'loki')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik-internal")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, true)

    # ALB-specific (only consumed when ingress_class = "alb").
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "acm")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default  = {}
  nullable = false
}
variable "mimir_exposures" {
  description = "Mimir remote-write ingress exposures. Used by workload clusters to push metrics to the hub. When host is empty, auto-derived (app: 'mimir')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false)

    # ALB-specific (only consumed when ingress_class = "alb").
    # Provider-agnostic shape so Azure exposures keep the same type.
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "acm")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default  = {}
  nullable = false
}
variable "vault_exposures" {
  description = "Vault UI ingress exposures (multi-network ingress per profile). Same shape as the other *_exposures vars. Typically internal — ops team accesses via VPN. When host is empty, it is auto-derived (app name: 'vault')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik-internal")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false) # Vault has its own UI auth

    # ALB-specific fields kept for type parity with AWS (Azure inert).
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "/v1/sys/health?standbyok=true")
    alb_certificate_source = optional(string, "acm")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default  = {}
  nullable = false
}
variable "hubble_ui_exposures" {
  description = "Hubble UI ingress exposures. Only rendered when Cilium + Hubble is enabled via components.hubble-ui in the platform-root override. When host is empty, auto-derived (app: 'hubble')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false)

    # ALB-specific (only consumed when ingress_class = "alb").
    # Provider-agnostic shape so Azure exposures keep the same type.
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "acm")
    alb_cloudflare_proxied = optional(bool, false)
  }))
  default  = {}
  nullable = false
}
variable "velero_backup_schedule" {
  description = "Cron schedule for Velero full cluster backups."
  type        = string
  default     = "0 2 * * *"
  nullable    = false
}
variable "velero_backup_retention_hours" {
  description = "Retention period in hours for Velero backups (CR TTL + S3 lifecycle alignment)."
  type        = number
  default     = 720
  nullable    = false
}
variable "cnpg_backup_schedule" {
  description = "Cron schedule for CloudNativePG daily backups."
  type        = string
  default     = "0 2 * * *"
  nullable    = false
}
variable "cnpg_backup_retention_days" {
  description = "Retention period in days for CloudNativePG base backups (S3 lifecycle + CNPG retention policy)."
  type        = number
  default     = 7
  nullable    = false
}
variable "slack_alerting_enabled" {
  description = "Master toggle for the Mimir Alertmanager Slack alerting pipeline. When true, terraform creates 3 SM secrets and the platform-root chart enables the mimir-alertmanager-config Slack templates. Requires all 3 slack_webhook_alertmanager_* variables non-empty."
  type        = bool
  default     = false
  nullable    = false
}
variable "openai_api_key_enabled" {
  description = "Whether an OpenAI key is provisioned for platform components that can use one."
  type        = bool
  default     = false
  nullable    = false
}
variable "argocd_namespace" {
  description = "Namespace the platform handoff is written into, and where ArgoCD will live. Created by this module."
  type        = string
  default     = "argocd"
  nullable    = false
}
variable "hub_cluster_secret_enabled" {
  description = "Write the ArgoCD cluster Secret describing this cluster to itself. On by default: naming the cluster is what lets an ApplicationSet target it by label instead of every Application hard-coding a URL."
  type        = bool
  default     = true
  nullable    = false
}
variable "github_app_credentials_enabled" {
  description = "Deliver the GitHub App credentials to the cluster as an ArgoCD repository credential. Requires the three github_app_* values."
  type        = bool
  default     = false
  nullable    = false
}
variable "github_app_id" {
  description = "GitHub App ID (numeric string). Leave empty to skip the ArgoCD GitHub App credential setup (fallback: config_repo_token / client_gitops_repo_token)."
  type        = string
  default     = ""
  nullable    = false
}
variable "github_app_installation_id" {
  description = "GitHub App Installation ID (numeric string). Found in the URL after installing the App on the organization."
  type        = string
  default     = ""
  nullable    = false
}
variable "github_app_private_key" {
  description = "PEM-encoded private key downloaded from the GitHub App settings. Pass via secrets.auto.tfvars or TF_VAR_github_app_private_key (do not commit). Sensitive."
  type        = string
  default     = ""
  sensitive   = true
  nullable    = false
}
variable "github_org_url" {
  description = "Organization URL for GitHub App credential matching (ArgoCD matches repos by URL prefix). Example: 'https://github.com/Cortex-Innovation'. Required when github_app_id is set."
  type        = string
  default     = ""
  nullable    = false
}
variable "platform_outputs_extra" {
  description = <<-EOT
    Extra keys merged into the platform-infrastructure ConfigMap, overriding the
    module's own on collision.

    This exists because DigitalOcean deployments know things this module cannot.
    Vault's seal lives in Google Cloud KMS — DigitalOcean has no KMS at all — and
    that key belongs to the deployment, not here. Rather than give this module a
    dependency on a cloud it does not manage, the downstream injects what only it
    knows.

    Values are strings: a ConfigMap holds no other type.
  EOT
  type        = map(string)
  default     = {}
  nullable    = false
}
variable "platform_outputs_extra_sensitive" {
  description = "Extra keys merged into the platform-infrastructure-sensitive Secret, overriding the module's own on collision. Same purpose as platform_outputs_extra, for values that must not be readable from a ConfigMap."
  type        = map(string)
  default     = {}
  sensitive   = true
  nullable    = false
}

variable "cluster_name" {
  description = "Name of the cluster this describes. Appears in the hub-cluster Secret and in global.clusterName."
  type        = string
  nullable    = false
}

variable "kubernetes_version" {
  description = "Version the cluster REPORTS, not the one requested. With a version prefix the exact patch is the provider's choice."
  type        = string
  default     = ""
  nullable    = false
}

variable "vpc_uuid" {
  description = "VPC the cluster sits in."
  type        = string
  default     = ""
  nullable    = false
}

variable "spaces_region" {
  description = "Region of the object storage the components read and write."
  type        = string
  default     = ""
  nullable    = false
}

variable "registry_endpoint" {
  description = "Container registry endpoint, empty when the deployment manages none. Never the account's own registry: naming one Terraform did not create tells the platform to pull from something nobody here controls."
  type        = string
  default     = ""
  nullable    = false
}

variable "observability_bucket_name" {
  description = "Bucket Loki, Mimir and Tempo write to. Empty when disabled."
  type        = string
  default     = ""
  nullable    = false
}

variable "velero_bucket_name" {
  description = "Bucket Velero writes backups to. Empty when disabled."
  type        = string
  default     = ""
  nullable    = false
}

variable "cnpg_bucket_name" {
  description = "Bucket CNPG writes backups to. Empty when disabled."
  type        = string
  default     = ""
  nullable    = false
}

variable "vault_backup_bucket_name" {
  description = "Bucket Vault writes Raft snapshots to. Empty when disabled."
  type        = string
  default     = ""
  nullable    = false
}

variable "observability_access_key_id" {
  description = "Access key for the observability bucket. A credential, not an identity: DigitalOcean has no workload identity, so the component holds a key scoped to its own bucket."
  type        = string
  default     = ""
  nullable    = false
}

variable "observability_secret_access_key" {
  description = "Secret for the observability bucket key."
  type        = string
  default     = ""
  sensitive   = true
  nullable    = false
}

variable "velero_access_key_id" {
  description = "Access key for the velero bucket. A credential, not an identity: DigitalOcean has no workload identity, so the component holds a key scoped to its own bucket."
  type        = string
  default     = ""
  nullable    = false
}

variable "velero_secret_access_key" {
  description = "Secret for the velero bucket key."
  type        = string
  default     = ""
  sensitive   = true
  nullable    = false
}

variable "cnpg_access_key_id" {
  description = "Access key for the cnpg bucket. A credential, not an identity: DigitalOcean has no workload identity, so the component holds a key scoped to its own bucket."
  type        = string
  default     = ""
  nullable    = false
}

variable "cnpg_secret_access_key" {
  description = "Secret for the cnpg bucket key."
  type        = string
  default     = ""
  sensitive   = true
  nullable    = false
}

variable "vault_backup_access_key_id" {
  description = "Access key for the vault backup bucket. A credential, not an identity: DigitalOcean has no workload identity, so the component holds a key scoped to its own bucket."
  type        = string
  default     = ""
  nullable    = false
}

variable "vault_backup_secret_access_key" {
  description = "Secret for the vault backup bucket key."
  type        = string
  default     = ""
  sensitive   = true
  nullable    = false
}
