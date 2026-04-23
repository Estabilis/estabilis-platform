# ---------------------------------------------------------------------------
# Core identification
# ---------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix used for all resource names. Override per client."
  type        = string
  default     = "estabilis"
}

variable "region" {
  description = "AWS region for all resources (e.g., us-east-1, us-east-2, sa-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "domain" {
  description = "DNS zone root (e.g. estabilis.io). Must match the actual zone in Route53 or Cloudflare. Hostnames are derived as {app}.{cluster_name}.{domain}."
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

variable "deployment_id" {
  description = "Deployment identifier used as key in the client GitOps repo (e.g., platform-aws-us-east-1-hml). Maps to platforms/{deployment_id}/ in the gitops repo."
  type        = string

  validation {
    condition     = length(var.deployment_id) > 0
    error_message = "deployment_id is required (e.g., platform-aws-us-east-1-hml)."
  }
}

variable "aws_profile" {
  description = "Optional AWS CLI profile name (from ~/.aws/credentials). Leave empty to use the default provider credential chain (environment variables, SSO, IAM role)."
  type        = string
  default     = ""
}

variable "platform_outputs_enabled" {
  description = "Write platform infrastructure values to a ConfigMap and Secret in the argocd namespace. Used by ArgoCD to configure platform components without the CLI."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Repository pointers
# ---------------------------------------------------------------------------

variable "platform_repo_url" {
  description = "Git repository URL for the platform manifests."
  type        = string
}

variable "platform_version" {
  description = "Version of the platform chart / manifests to deploy (deprecated — prefer platform_revision). Kept for backward compatibility."
  type        = string
  default     = "0.1.0-alpha"
}

variable "platform_revision" {
  description = "Git revision for the platform repo (tag OR branch, e.g. 'v0.13.1' or 'main'). Empty falls back to platform_version for backward compatibility."
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
  description = "Git tag for the config repository (deprecated — prefer config_repo_revision). Kept for backward compatibility."
  type        = string
  default     = ""
}

variable "config_repo_revision" {
  description = "Git revision for the config repository (tag OR branch, e.g. 'v1.0.0' or 'release/prod'). Empty falls back to config_repo_version. ADR 0020."
  type        = string
  default     = ""
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

variable "client_gitops_repo_version" {
  description = "Git tag for the client GitOps repo (deprecated — prefer client_gitops_repo_revision). Kept for backward compatibility."
  type        = string
  default     = ""
}

variable "client_gitops_repo_revision" {
  description = "Git revision for the client GitOps repo (tag OR branch). Empty falls back to client_gitops_repo_version. ADR 0020."
  type        = string
  default     = ""
}

variable "client_gitops_repo_token" {
  description = "Git access token for the client GitOps repository. Pass via secrets.auto.tfvars. Required if the repo is private."
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# EKS cluster
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.34"
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to the EKS API server endpoint. When true, authorized_ip_ranges controls the allowed source CIDRs."
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to the EKS API server from within the VPC. Keep true unless operator access is exclusively via public endpoint."
  type        = bool
  default     = true
}

variable "authorized_ip_ranges" {
  description = "Source IP CIDRs allowed to reach the EKS API server public endpoint. Empty list = 0.0.0.0/0 (public — operator accepts the risk; must also set allow_public_api_endpoint = true). Equivalent to Azure's authorized_ip_ranges."
  type        = list(string)
  default     = []
}

variable "allow_public_api_endpoint" {
  description = "Explicit acknowledgement that a public EKS API server with NO source IP allowlist is intentional. Must be true when cluster_endpoint_public_access = true AND authorized_ip_ranges is empty. Prevents accidentally exposing the API to the internet."
  type        = bool
  default     = false
}

variable "cluster_log_types" {
  description = "EKS control-plane log types to publish to CloudWatch. Recommended: api, audit, authenticator, controllerManager, scheduler."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "Retention in days for EKS control-plane CloudWatch logs."
  type        = number
  default     = 30
}

variable "cluster_secrets_encryption_enabled" {
  description = "Enable EKS envelope encryption for Kubernetes Secrets using a customer-managed KMS key."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# EKS — Authentication (Access Entries, AWS best practice — replaces aws-auth)
# ---------------------------------------------------------------------------

variable "authentication_mode" {
  description = "EKS authentication mode. 'API' uses Access Entries exclusively (recommended). 'API_AND_CONFIG_MAP' keeps compatibility with the legacy aws-auth ConfigMap during migrations."
  type        = string
  default     = "API"

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be one of: API, API_AND_CONFIG_MAP."
  }
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Grant AmazonEKSClusterAdminPolicy to the IAM principal that runs terraform apply. Convenient for bootstrap; consider disabling after Access Entries for ops team are in place."
  type        = bool
  default     = true
}

variable "eks_access_entries" {
  description = "List of EKS Access Entry definitions (AWS best practice, replaces aws-auth ConfigMap). Each entry binds an IAM principal to an EKS access policy."
  type = list(object({
    principal_arn     = string
    kubernetes_groups = optional(list(string), [])
    policy_arn        = optional(string, "") # e.g. arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
    access_scope_type = optional(string, "cluster")
    namespaces        = optional(list(string), [])
  }))
  default = []
}

# ---------------------------------------------------------------------------
# EKS — Node groups (Fargate for control-plane addons + Karpenter/CAS)
# ---------------------------------------------------------------------------

variable "fargate_profile_namespaces" {
  description = "Additional Kubernetes namespaces that must run on Fargate. kube-system and karpenter are always included."
  type        = list(string)
  default     = []
}

variable "autoscaler" {
  description = "Node autoscaling strategy. 'karpenter' (recommended): Fargate for system + Karpenter provisions EC2 on demand. 'cluster_autoscaler': managed node groups with ASG-based autoscaling. 'none': bring-your-own node groups via ArgoCD/manual."
  type        = string
  default     = "karpenter"

  validation {
    condition     = contains(["karpenter", "cluster_autoscaler", "none"], var.autoscaler)
    error_message = "autoscaler must be one of: karpenter, cluster_autoscaler, none."
  }
}

# --- Managed Node Group (only used when autoscaler = "cluster_autoscaler") ---

variable "mng_instance_types" {
  description = "EC2 instance types for the managed node group (cluster_autoscaler mode). First matching type is used; extras provide capacity fallback."
  type        = list(string)
  default     = ["t3a.medium", "t3.medium"]
}

variable "mng_capacity_type" {
  description = "Capacity type for the managed node group: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.mng_capacity_type)
    error_message = "mng_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "mng_min_size" {
  description = "Minimum number of nodes in the managed node group."
  type        = number
  default     = 2
}

variable "mng_max_size" {
  description = "Maximum number of nodes in the managed node group."
  type        = number
  default     = 4
}

variable "mng_desired_size" {
  description = "Desired (initial) number of nodes in the managed node group."
  type        = number
  default     = 2
}

variable "mng_disk_size_gb" {
  description = "Root EBS volume size (GB) for the managed node group."
  type        = number
  default     = 50
}

variable "mng_ami_type" {
  description = "AMI type for the managed node group. AL2023_x86_64_STANDARD is the current AWS default."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

# --- Karpenter (only used when autoscaler = "karpenter") ---

variable "karpenter_node_iam_role_additional_policies" {
  description = "Extra IAM policy ARNs to attach to the Karpenter node IAM role. Note: SSM is intentionally NOT attached by default (pods could escalate via Session Manager)."
  type        = map(string)
  default     = {}
}

variable "karpenter_discovery_tag_key" {
  description = "Tag key used by Karpenter's EC2NodeClass subnetSelectorTerms + securityGroupSelectorTerms to discover AWS resources. Defaults to the community convention 'karpenter.sh/discovery'. Override only when the VPC already hosts another Karpenter-managed cluster using that key — AWS allows a single value per tag-key per resource, so sharing the key would make the clusters overwrite each other's subnet tags. Recommended override when sharing: 'estabilis.io/discovery'."
  type        = string
  default     = "karpenter.sh/discovery"

  validation {
    condition     = length(var.karpenter_discovery_tag_key) > 0
    error_message = "karpenter_discovery_tag_key cannot be empty."
  }
}

# ---------------------------------------------------------------------------
# EKS — Addons
# ---------------------------------------------------------------------------

variable "cluster_addons" {
  description = "Map of EKS managed addons to install. Each entry maps addon name to its configuration (most_recent, configuration_values, etc.). Leave empty for sensible defaults applied in eks.tf."
  type        = any
  default     = {}
}

variable "ebs_encryption_by_default_enabled" {
  description = "Enable EBS encryption by default at the account/region level using the s3_data KMS key. Ensures every new EBS volume (including future RDS/snapshots) is encrypted without per-resource configuration."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Networking — VPC
# ---------------------------------------------------------------------------

variable "vpc_mode" {
  description = "VPC provisioning strategy. 'create': Terraform creates a new VPC with subnets, IGW, NAT, route tables. 'existing': look up an existing VPC via vpc_id and subnet IDs (BYO networking). Mirrors the AKS pattern of managing or consuming networking."
  type        = string
  default     = "create"

  validation {
    condition     = contains(["create", "existing"], var.vpc_mode)
    error_message = "vpc_mode must be one of: create, existing."
  }
}

variable "vpc_id" {
  description = "Existing VPC ID. Required when vpc_mode = 'existing'. Ignored when vpc_mode = 'create'."
  type        = string
  default     = ""

  validation {
    condition     = var.vpc_mode != "existing" || length(var.vpc_id) > 0
    error_message = "vpc_id is required when vpc_mode = 'existing'."
  }
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs for EKS node placement. Required (length >= 2) when vpc_mode = 'existing'. Must span distinct AZs."
  type        = list(string)
  default     = []

  validation {
    condition     = var.vpc_mode != "existing" || length(var.private_subnet_ids) >= 2
    error_message = "private_subnet_ids must contain at least 2 subnets across distinct AZs when vpc_mode = 'existing' (EKS requires multi-AZ)."
  }
}

variable "public_subnet_ids" {
  description = "Existing public subnet IDs (for ALB / NLB placement). Optional when vpc_mode = 'existing' — required only if public_subnets_enabled = true."
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (create mode). Must not overlap with on-prem or peered networks."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of AZs to span when vpc_mode = 'create'. EKS requires at least 2; 3 is recommended for production HA."
  type        = number
  default     = 3

  validation {
    condition     = var.availability_zone_count >= 2 && var.availability_zone_count <= 6
    error_message = "availability_zone_count must be between 2 and 6 (EKS requires at least 2)."
  }
}

variable "private_subnet_newbits" {
  description = "Number of bits to add to vpc_cidr when slicing private subnets (create mode). Default /20 per AZ (/16 + 4). 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20, ..."
  type        = number
  default     = 4
}

variable "public_subnet_newbits" {
  description = "Number of bits to add to vpc_cidr when slicing public subnets (create mode). Default /24 per AZ. Public subnets are small — they only host NAT Gateways and public LBs."
  type        = number
  default     = 8
}

variable "public_subnet_offset" {
  description = "Offset applied to the subnet index when slicing public subnets, keeping private and public ranges from overlapping. Default 100 → 10.0.100.0/24, 10.0.101.0/24, ..."
  type        = number
  default     = 100
}

variable "public_subnets_enabled" {
  description = "Provision public subnets (create mode). Required when NAT Gateway is enabled or when ingress_controller = 'alb' (public-facing ALB needs public subnets). Disable only for fully-private clusters."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Networking — NAT Gateway
# ---------------------------------------------------------------------------

variable "nat_gateway_enabled" {
  description = "Provision NAT Gateway(s) for outbound internet from private subnets. Equivalent to Azure NAT Gateway. Required unless all egress goes through VPC endpoints + PrivateLink."
  type        = bool
  default     = true
}

variable "nat_gateway_az_count" {
  description = "Number of NAT Gateways to provision. 1 = single NAT shared by all AZs (cheap, SPOF). availability_zone_count = one NAT per AZ (HA, expensive — each NAT is ~$32/mo + $0.045/GB)."
  type        = number
  default     = 1

  validation {
    condition     = var.nat_gateway_az_count >= 1 && var.nat_gateway_az_count <= 6
    error_message = "nat_gateway_az_count must be between 1 and 6."
  }
}

# ---------------------------------------------------------------------------
# Networking — Security Groups (defense in depth for the node subnet)
#
# Mirrors the AKS pattern: a custom SG on the cluster + explicit HTTP(S)
# ingress rules when traefik_enabled = true. When ingress_controller = 'alb',
# the ALB Controller manages its own security groups and rules here are not
# needed on the node SG.
# ---------------------------------------------------------------------------

variable "security_groups_hardening_enabled" {
  description = "Apply security hardening: revoke all rules on the VPC default SG, create a dedicated cluster additional SG, and enforce TLS-only on S3 buckets. Recommended ON."
  type        = bool
  default     = true
}

variable "ingress_allowed_ip_ranges" {
  description = "Source IP CIDRs allowed to reach ingress ports 80/443 when ingress_controller = 'traefik'. Empty list = 0.0.0.0/0 (public). Distinct from authorized_ip_ranges (which is for the EKS API server)."
  type        = list(string)
  default     = []
}

variable "extra_ingress_rules" {
  description = "Additional custom ingress rules applied to the cluster additional SG. Useful for on-prem peering, SaaS callbacks, etc."
  type = map(object({
    description              = optional(string, "")
    from_port                = number
    to_port                  = number
    protocol                 = optional(string, "tcp")
    cidr_blocks              = optional(list(string), [])
    ipv6_cidr_blocks         = optional(list(string), [])
    source_security_group_id = optional(string, "")
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Networking — VPC Endpoints (AWS best practice — reduces NAT cost + keeps
# traffic inside the AWS network for AWS service API calls)
# ---------------------------------------------------------------------------

variable "vpc_endpoints_gateway" {
  description = "Gateway VPC endpoints (free). Map of service name to toggle. Recommended ON for S3 and DynamoDB — they are heavily used by EKS addons and are completely free."
  type        = map(bool)
  default = {
    s3       = true
    dynamodb = true
  }
}

variable "vpc_endpoints_interface" {
  description = "Interface VPC endpoints (~$7/mo each + $0.01/GB). Toggle per service. Enable for services with heavy traffic or sensitivity: ecr_api, ecr_dkr, sts, secretsmanager, kms, logs, ec2, elasticloadbalancing, autoscaling."
  type        = map(bool)
  default = {
    ecr_api              = false
    ecr_dkr              = false
    sts                  = false
    secretsmanager       = false
    kms                  = false
    logs                 = false
    ec2                  = false
    elasticloadbalancing = false
    autoscaling          = false
  }
}

variable "vpc_endpoints_private_dns_enabled" {
  description = "Enable private DNS on interface VPC endpoints so AWS SDK calls transparently use the endpoint. Leave true unless conflicting with a Route53 Resolver setup."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Networking — VPC Flow Logs (security audit + troubleshooting)
# ---------------------------------------------------------------------------

variable "vpc_flow_logs_enabled" {
  description = "Enable VPC Flow Logs for audit and troubleshooting. Destination is an S3 bucket provisioned alongside. Cost: ~$10-30/mo depending on traffic volume."
  type        = bool
  default     = false
}

variable "vpc_flow_logs_traffic_type" {
  description = "Flow log traffic type: ACCEPT, REJECT, or ALL. ALL is the most useful for security reviews."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.vpc_flow_logs_traffic_type)
    error_message = "vpc_flow_logs_traffic_type must be ACCEPT, REJECT, or ALL."
  }
}

variable "vpc_flow_logs_retention_days" {
  description = "Retention in days for VPC Flow Logs in S3 (lifecycle rule). 0 = keep forever."
  type        = number
  default     = 90
}

# ---------------------------------------------------------------------------
# Ingress (L7) — single toggle that selects the ingress controller model.
# Mirror in ArgoCD via components.traefik / components.alb-controller in
# overrides/platform-root/values.yaml.
# ---------------------------------------------------------------------------

variable "ingress_controller" {
  description = "Ingress controller strategy. 'traefik': Traefik + NLB/ELB (consistent with Azure path). 'alb': AWS Load Balancer Controller + ALB (AWS-native, ACM-friendly). 'none': no public ingress (internal-only cluster)."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["traefik", "alb", "none"], var.ingress_controller)
    error_message = "ingress_controller must be one of: traefik, alb, none."
  }
}

variable "traefik_internal_enabled" {
  description = "Deploy a second Traefik instance for internal (VPC-only) exposures, producing ingressClass 'traefik-internal' backed by an internal NLB. Only applies when ingress_controller = 'traefik'."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# DNS provider
# ---------------------------------------------------------------------------

variable "dns_provider" {
  description = "DNS provider for external-dns and cert-manager DNS-01 solver. 'route53' uses AWS Route53 + IRSA (Terraform manages the zone + IAM role). 'cloudflare' uses Cloudflare API with a static token (zone must already exist). 'none' disables external-dns + DNS-01 issuance (useful when DNS is manual)."
  type        = string
  default     = "route53"

  validation {
    condition     = contains(["route53", "cloudflare", "none"], var.dns_provider)
    error_message = "dns_provider must be one of: route53, cloudflare, none."
  }
}

variable "route53_zone_mode" {
  description = "Route53 zone management. 'create' creates a public hosted zone for var.domain. 'existing' looks up the zone by name (must already exist). Ignored when dns_provider != 'route53'."
  type        = string
  default     = "create"

  validation {
    condition     = contains(["create", "existing"], var.route53_zone_mode)
    error_message = "route53_zone_mode must be one of: create, existing."
  }
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID (UUID from the Cloudflare Dashboard). Required when dns_provider = 'cloudflare'."
  type        = string
  default     = ""

  validation {
    condition     = var.dns_provider != "cloudflare" || length(var.cloudflare_zone_id) > 0
    error_message = "cloudflare_zone_id is required when dns_provider = 'cloudflare'."
  }
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
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt ACME account registration (used by cert-manager)."
  type        = string
}

# ---------------------------------------------------------------------------
# ACM (AWS Certificate Manager) — alternative to cert-manager, used when
# ingress_controller = 'alb' to terminate TLS directly on the ALB.
# ---------------------------------------------------------------------------

variable "acm_enabled" {
  description = "Provision a wildcard ACM certificate for *.{cluster_name}.{domain}. Useful with ALB + ACM integration (avoids cert-manager for public endpoints). Terraform runs the DNS-01 validation automatically when dns_provider = 'route53'."
  type        = bool
  default     = false
}

variable "acm_extra_domain_names" {
  description = "Additional Subject Alternative Names (SANs) to include on the ACM wildcard certificate. Leave empty for single wildcard."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# App exposures — same shape as Azure (ADR 0014). Each entry is a separate
# Ingress + Middleware (Traefik) or ALB listener rule, with cert issuance
# and optional basic-auth.
# ---------------------------------------------------------------------------

variable "grafana_exposures" {
  description = "Grafana ingress exposures. One entry per network profile. Leave empty to not expose. When host is empty, it is auto-derived as {app}.{cluster_name}.{domain} (app: 'grafana')."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false)
  }))
  default = {}
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
  }))
  default = {}
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
  }))
  default = {}
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
  }))
  default = {}
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
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# ArgoCD
# ---------------------------------------------------------------------------

variable "argocd_chart_version" {
  description = "Helm chart version for ArgoCD (seed via Terraform)."
  type        = string
  default     = "9.4.7"
}

# ---------------------------------------------------------------------------
# Secrets Manager — 1:1 mirror of Azure Key Vault pattern.
# Secret names follow the path convention estabilis/{deployment_id}/<name>
# so IAM policies can scope access per deployment via ARN prefix.
# ---------------------------------------------------------------------------

variable "secretsmanager_recovery_days" {
  description = "Recovery window in days before a deleted secret is permanently removed. Range 0 (immediate) or 7-30. AWS default is 30. Equivalent to Azure KV soft_delete_retention_days."
  type        = number
  default     = 7

  validation {
    condition     = var.secretsmanager_recovery_days == 0 || (var.secretsmanager_recovery_days >= 7 && var.secretsmanager_recovery_days <= 30)
    error_message = "secretsmanager_recovery_days must be 0 (immediate delete) or between 7 and 30."
  }
}

variable "secretsmanager_resource_policy_enabled" {
  description = "Attach a resource policy to each platform secret denying cross-deployment access (analog of Key Vault RBAC isolation). Recommended ON for multi-tenant AWS accounts."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# KMS
# ---------------------------------------------------------------------------

variable "kms_deletion_window_days" {
  description = "Waiting period before a scheduled KMS key deletion is finalized. Range 7-30. Use the maximum (30) for production to allow human override."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

variable "kms_enable_rotation" {
  description = "Enable automatic annual key rotation for customer-managed KMS keys."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# S3 — applies to all platform-managed buckets (tfstate, observability,
# velero, cost-export, flow-logs). Per-bucket overrides live in s3.tf.
# ---------------------------------------------------------------------------

variable "s3_force_destroy" {
  description = "Allow terraform destroy to delete non-empty buckets. Keep false for production — prevents accidental data loss."
  type        = bool
  default     = false
}

variable "s3_versioning_enabled" {
  description = "Enable bucket versioning on all platform-managed buckets. Strongly recommended ON."
  type        = bool
  default     = true
}

variable "s3_tfstate_replication_enabled" {
  description = "Enable cross-region replication on the tfstate bucket for disaster recovery. Destination bucket must be pre-provisioned in tfstate_replication_destination_bucket_arn."
  type        = bool
  default     = false
}

variable "s3_tfstate_replication_destination_bucket_arn" {
  description = "ARN of the tfstate replication destination bucket. Required when s3_tfstate_replication_enabled = true."
  type        = string
  default     = ""
}

variable "s3_tfstate_protect_critical" {
  description = "Enable Object Lock (governance mode) + 'prevent_destroy' on the tfstate bucket. Must be removed before teardown. Equivalent to Azure storage_protect_critical."
  type        = bool
  default     = false
}

variable "s3_observability_lifecycle_days" {
  description = "Days before observability objects (Loki, Mimir blocks) are deleted. 0 = no lifecycle rule."
  type        = number
  default     = 90
}

variable "s3_velero_lifecycle_days" {
  description = "Days before Velero backup objects are deleted. Align with velero_backup_retention_hours. 0 = no lifecycle rule."
  type        = number
  default     = 30
}

variable "s3_flow_logs_lifecycle_days" {
  description = "Days before VPC Flow Logs objects are deleted. Align with vpc_flow_logs_retention_days. 0 = no lifecycle rule."
  type        = number
  default     = 90
}

# ---------------------------------------------------------------------------
# ECR (Elastic Container Registry) — optional, mirrors ACR toggles
# ---------------------------------------------------------------------------

variable "ecr_enabled" {
  description = "Provision ECR repositories and optional pull-through caches. Disable when using external registries or when Image Updater points to a shared registry."
  type        = bool
  default     = false
}

variable "ecr_repositories" {
  description = "List of ECR repository names to create (without the account/region prefix). Each repo gets scan-on-push and the lifecycle policy defined below."
  type        = list(string)
  default     = []
}

variable "ecr_image_tag_mutability" {
  description = "Tag mutability: IMMUTABLE (recommended for prod — prevents tag overwrites) or MUTABLE."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ecr_image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "ecr_scan_on_push" {
  description = "Enable automatic image scanning on push (basic scan, free)."
  type        = bool
  default     = true
}

variable "ecr_lifecycle_untagged_days" {
  description = "Days before untagged images are deleted by the lifecycle policy. 0 = disabled."
  type        = number
  default     = 14
}

variable "ecr_pull_through_cache_enabled" {
  description = "Enable pull-through cache rules for public upstream registries. Equivalent to Azure ACR cache rules."
  type        = bool
  default     = false
}

variable "ecr_pull_through_cache_upstreams" {
  description = "Map of pull-through cache rules: prefix -> upstream_registry_url. Examples: { docker-hub = 'registry-1.docker.io', quay = 'quay.io', ghcr = 'ghcr.io', k8s = 'registry.k8s.io', public-ecr = 'public.ecr.aws' }."
  type        = map(string)
  default     = {}
}

variable "ecr_dockerhub_credentials_secret_arn" {
  description = "ARN of a Secrets Manager secret holding { username, accessToken } for authenticated Docker Hub pull-through cache. Required when 'docker-hub' is in ecr_pull_through_cache_upstreams."
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Diagnostics (CloudWatch)
# ---------------------------------------------------------------------------

variable "diagnostics_enabled" {
  description = "Enable CloudWatch diagnostics for EKS (control-plane logs + Container Insights if Azure Monitor analog is enabled). Disable for dev/test to save cost."
  type        = bool
  default     = true
}

variable "container_insights_enabled" {
  description = "Enable CloudWatch Container Insights (AWS-native alternative to the Grafana stack). Cost: ~$2/node/mo. Opt-in — platform uses Grafana/Alloy/Mimir by default."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

variable "cnpg_backup_retention_days" {
  description = "Retention period in days for CloudNativePG base backups (S3 lifecycle + CNPG retention policy)."
  type        = number
  default     = 7
}

variable "cnpg_backup_schedule" {
  description = "Cron schedule for CloudNativePG daily backups."
  type        = string
  default     = "0 2 * * *"
}

variable "velero_backup_retention_hours" {
  description = "Retention period in hours for Velero backups (CR TTL + S3 lifecycle alignment)."
  type        = number
  default     = 720
}

variable "velero_backup_schedule" {
  description = "Cron schedule for Velero full cluster backups."
  type        = string
  default     = "0 2 * * *"
}

# ---------------------------------------------------------------------------
# Cost export (AWS CUR — Cost and Usage Report)
# ---------------------------------------------------------------------------

variable "cost_export_enabled" {
  description = "Create an AWS Cost and Usage Report (CUR) exported to S3, consumed by OpenCost. Only one CUR per granularity type per account — Terraform fails loudly if a conflicting report exists."
  type        = bool
  default     = false
}

variable "cost_export_report_name" {
  description = "Name of the CUR report. Defaults to {name_prefix}-{deployment_id} when empty."
  type        = string
  default     = ""
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
# Shared Hub Secrets (cross-deployment secret sharing, analog of the shared
# Azure Key Vault). Published via Secrets Manager under a shared path that
# workload clusters read.
# ---------------------------------------------------------------------------

variable "shared_hub_secrets_enabled" {
  description = "Create a shared Secrets Manager path for hub connection values consumed by workload clusters (e.g., Mimir remote-write endpoint, Loki push endpoint). Required when workload clusters rely on data sources instead of manual tfvars."
  type        = bool
  default     = true
}

variable "shared_hub_secrets_prefix" {
  description = "Prefix for shared hub Secrets Manager entries. Defaults to 'estabilis/shared/{name_prefix}' when empty."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Tags (CAF-equivalent — AWS supports the same tagging model as Azure CAF,
# kept byte-compatible so downstream client tfvars can reuse the same keys
# across providers.)
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
