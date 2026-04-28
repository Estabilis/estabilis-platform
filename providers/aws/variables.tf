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
# Provenance tags — applied to every AWS resource via provider default_tags.
# Mirrors the cortex-postgres-aws-* pattern: every resource carries pointers
# back to the source repo + version that produced it, surfacing in AWS
# Cost Explorer, Resource Groups, and Tag Editor for forensics + chargeback.
#
# `platform_source` + `platform_version` are derived inside this module
# (constant URL + VERSION file at the cloned ref). The client passes
# `repo_url` + `client_version` so each cluster also tags its own repo +
# semver. Both pairs filter empty values out — clients that don't pass
# anything just don't get those two tags.
# ---------------------------------------------------------------------------

variable "repo_url" {
  description = "Client repository URL (https://...). Tagged on every AWS resource as `source` for provenance. Should be a https:// URL — git@ won't render as clickable in the AWS console. Empty value (default) skips the tag."
  type        = string
  default     = ""
}

variable "client_version" {
  description = "Client deployment semver (e.g. \"1.10.5\"). Computed in the client tfvars from CHANGELOG.md regex (see cortex-postgres-aws-* for canonical pattern). Tagged on every AWS resource as `version`. Empty value (default) skips the tag."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Repository pointers
# ---------------------------------------------------------------------------

variable "platform_repo_url" {
  description = "Git repository URL for the platform manifests."
  type        = string
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
# GitHub App — organization-scoped credential for ArgoCD git access.
# Preferred over per-repo deploy keys or per-user PATs because the App
# belongs to the GitHub organization (not a specific user), permissions
# are fine-grained, and ArgoCD renews installation tokens automatically.
# See modules/github-app-credentials/ for the full pattern.
# ---------------------------------------------------------------------------

variable "github_app_id" {
  description = "GitHub App ID (numeric string). Leave empty to skip the ArgoCD GitHub App credential setup (fallback: config_repo_token / client_gitops_repo_token)."
  type        = string
  default     = ""
}

variable "github_app_installation_id" {
  description = "GitHub App Installation ID (numeric string). Found in the URL after installing the App on the organization."
  type        = string
  default     = ""
}

variable "github_app_private_key" {
  description = "PEM-encoded private key downloaded from the GitHub App settings. Pass via secrets.auto.tfvars or TF_VAR_github_app_private_key (do not commit). Sensitive."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_org_url" {
  description = "Organization URL for GitHub App credential matching (ArgoCD matches repos by URL prefix). Example: 'https://github.com/Cortex-Innovation'. Required when github_app_id is set."
  type        = string
  default     = ""
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
  description = <<-EOT
    Enable EKS envelope encryption for Kubernetes Secrets using a
    customer-managed KMS key.

    !!! IRREVERSIBLE WARNING !!!
    EKS encryption_config is ONE-WAY (add-only) at the AWS API level.
      - false -> true on a running cluster: in-place update via UpdateClusterConfig.
      - true  -> false on a running cluster: NOT supported by AWS. Terraform will
        plan a full cluster destroy + recreate, which deletes EVERYTHING
        (worker nodes, EBS volumes, EKS API endpoint, ENIs, etc.).

    Default true. Once enabled in production, treat as immutable. If you
    must remove encryption, plan a full cluster migration (new cluster +
    velero restore), not a flip of this variable.
  EOT
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
  description = <<-EOT
    Node autoscaling strategy. Four modes:

    - 'hybrid' (recommended): managed node group (MNG) with a small
      always-on EC2 fleet for platform control-plane (ArgoCD,
      cert-manager, external-secrets, kyverno, ...) + Karpenter
      infrastructure ready to provision EC2 nodes on demand for
      workloads. Mirrors the AKS `system pool + user pool` model and
      eliminates the chicken-and-egg where ArgoCD needs nodes to run
      but Karpenter's NodePool is created BY ArgoCD.

    - 'karpenter': Fargate for system + karpenter namespaces;
      Karpenter provisions EC2 for everything else. Requires Karpenter
      NodePool to be installed via a pre-seed path (not via ArgoCD) or
      the MNG-less variant of this mode has a chicken-and-egg on
      ArgoCD bootstrap. Kept for parity with earlier deployments.

    - 'cluster_autoscaler': MNG only, with ASG-based autoscaling.
      No Karpenter. Simplest model but less flexibility on instance
      types for workloads.

    - 'none': bring-your-own node groups via ArgoCD or manual
      Terraform resources in the downstream repo.
  EOT
  type        = string
  default     = "hybrid"

  validation {
    condition     = contains(["hybrid", "karpenter", "cluster_autoscaler", "none"], var.autoscaler)
    error_message = "autoscaler must be one of: hybrid, karpenter, cluster_autoscaler, none."
  }
}

# --- Managed Node Group (only used when autoscaler = "cluster_autoscaler") ---

variable "mng_instance_types" {
  description = <<-EOT
    EC2 instance types for the managed node group. First matching type is
    used; extras provide capacity fallback (especially valuable for SPOT
    capacity-optimized allocation).

    REPLACEMENT NOTE: changing this on a running cluster forces NG
    recreation. The behavior depends on `mng_replacement_strategy`:
      - 'static' (default): collides with itself on the explicit name
        (HTTP 409 ResourceInUseException). Operator must
        `terraform destroy -target=...eks_managed_node_group["default"]`
        before `terraform apply`.
      - 'rolling': bump `mng_generation` in the same change to swap to a
        new NG name; create_before_destroy gives zero-downtime rollover.
  EOT
  type        = list(string)
  default     = ["t3a.medium", "t3.medium"]
}

variable "mng_capacity_type" {
  description = <<-EOT
    Capacity type for the managed node group: ON_DEMAND or SPOT.
    REPLACEMENT NOTE: same as mng_instance_types — changing forces NG
    recreation. See `mng_replacement_strategy` to control rollover.
  EOT
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

  validation {
    condition     = var.mng_min_size >= 0
    error_message = "mng_min_size must be >= 0."
  }
}

variable "mng_max_size" {
  description = "Maximum number of nodes in the managed node group."
  type        = number
  default     = 4

  validation {
    condition     = var.mng_max_size >= 1
    error_message = "mng_max_size must be >= 1."
  }
}

variable "mng_desired_size" {
  description = "Desired (initial) number of nodes in the managed node group."
  type        = number
  default     = 2

  validation {
    condition     = var.mng_desired_size >= 0
    error_message = "mng_desired_size must be >= 0."
  }
}

variable "mng_disk_size_gb" {
  description = <<-EOT
    Root EBS volume size (GB) for the managed node group.
    REPLACEMENT NOTE: changing forces NG recreation.
    See `mng_replacement_strategy`.
  EOT
  type        = number
  default     = 50
}

variable "mng_ami_type" {
  description = <<-EOT
    AMI type for the managed node group. AL2023_x86_64_STANDARD is the
    current AWS default.
    REPLACEMENT NOTE: changing forces NG recreation.
    See `mng_replacement_strategy`.
  EOT
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

# --- MNG replacement strategy (force_new safety rails) -----------------------
#
# Why this exists: aws_eks_node_group has multiple force_new fields
# (instance_types, capacity_type, ami_type, disk_size). The upstream
# terraform-aws-modules/eks module hardcodes lifecycle.create_before_destroy
# on the resource — combined with the explicit NG name we are forced to use
# (IAM role 38-char prefix budget overflow on long cluster names), any
# force_new change collides with itself on the name, failing apply with
# `409 ResourceInUseException: NodeGroup already exists`.
#
# This pair of variables exposes two strategies for handling that:
#
#   - 'static' (default, backward-compat): NG name is `<cluster>-default`.
#     On force_new changes, operator runs `terraform destroy -target` first.
#     Workload migrates to Karpenter / other compute during the drain.
#
#   - 'rolling': NG name includes `-gen<mng_generation>`. To trigger a
#     replacement, operator bumps mng_generation in the SAME change. The
#     module's create_before_destroy provisions the new NG before draining
#     the old, giving zero-downtime rollover.
#
# Defaults preserve current behavior; new clusters can opt into 'rolling'
# from day 1 for safer instance-type / capacity changes.
# ---------------------------------------------------------------------------

variable "mng_replacement_strategy" {
  description = <<-EOT
    How the module handles force_new changes on the managed node group
    (instance_types, capacity_type, ami_type, disk_size).

    - 'static' (default): NG name is `<cluster>-default`. Backward-compat
      with deployments that already exist. Force_new changes require
      `terraform destroy -target` on the NG before `terraform apply`,
      because the module's create_before_destroy collides with itself
      on the explicit name.

    - 'rolling': NG name is `<cluster>-default-gen<mng_generation>`.
      Force_new changes are made by bumping `mng_generation` in the same
      apply: a new NG comes up with the new name, then the old one
      drains+destroys via the module's create_before_destroy. Zero-downtime
      rollover. Recommended for clusters that have other compute (Karpenter,
      additional NGs) able to absorb workloads during the brief window
      where both NGs coexist.

    SWITCHING FROM static -> rolling: the NG itself is renamed, which is
    a force_new event on `name`. The module's create_before_destroy makes
    this safe (zero-downtime), but it IS a real replacement.
  EOT
  type        = string
  default     = "static"

  validation {
    condition     = contains(["static", "rolling"], var.mng_replacement_strategy)
    error_message = "mng_replacement_strategy must be 'static' or 'rolling'."
  }
}

variable "mng_generation" {
  description = <<-EOT
    Generation suffix appended to the MNG name when
    mng_replacement_strategy='rolling'. Bump this integer in the same
    `terraform apply` that changes a force_new field (instance_types,
    capacity_type, ami_type, disk_size) to trigger zero-downtime rollover.

    Ignored when mng_replacement_strategy='static'.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.mng_generation >= 1
    error_message = "mng_generation must be >= 1."
  }
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

variable "existing_subnet_role_tags_management" {
  description = <<-EOT
    Only meaningful when vpc_mode = "existing". Controls whether Terraform
    manages the shared `kubernetes.io/role/elb` and
    `kubernetes.io/role/internal-elb` tags on the operator-supplied
    subnets. Ignored (and validated against) when vpc_mode = "create",
    where Terraform always owns the subnets and their tags.

    These role tags are required by AWS Load Balancer Controller for
    subnet auto-discovery, but their KEYS are NOT cluster-scoped — the
    controller hardcodes them. When N Estabilis deployments share the
    same VPC, each TF state would otherwise own the same tag, causing
    `terraform destroy` of one cluster to remove tags relied upon by
    the survivors.

    Modes:
      - "create" (default): Terraform creates and owns the role tags.
        Use for the FIRST cluster sharing a VPC, or any standalone
        deployment.
      - "skip": Terraform does NOT manage the role tags. Use for the
        SECOND/Nth cluster sharing a VPC where another deployment
        (or the operator) already owns them. Eliminates cross-state
        ownership and makes `terraform destroy` non-destructive to the
        surviving cluster's ALB subnet discovery.

    Naming follows the convention of `private_subnet_ids` /
    `public_subnet_ids` / `vpc_id`: the `existing_` prefix signals that
    the variable is only consumed in vpc_mode = "existing".

    The cluster-membership tag (`kubernetes.io/cluster/<cluster-name>=shared`)
    and the per-cluster Karpenter discovery tag are always managed — they
    are cluster-scoped and never collide between deployments.
  EOT
  type        = string
  default     = "create"

  validation {
    condition     = contains(["create", "skip"], var.existing_subnet_role_tags_management)
    error_message = "existing_subnet_role_tags_management must be one of: create, skip."
  }
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
  description = "Provision a wildcard ACM certificate for *.{cluster_name}.{domain}. Required when ingress_controller = 'alb' (ALB Controller only consumes ACM certificates — k8s Secrets are not supported). DNS validation is automatic for both 'route53' and 'cloudflare' DNS providers."
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

    # ALB-specific (only consumed when ingress_class = "alb").
    alb_group              = optional(string, "platform")
    alb_scheme             = optional(string, "internet-facing")
    alb_target_type        = optional(string, "ip")
    alb_ssl_policy         = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alb_healthcheck_path   = optional(string, "")
    alb_certificate_source = optional(string, "acm")
    alb_cloudflare_proxied = optional(bool, false)
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
  description = "List of platform-managed ECR repository names (no account/region prefix). Use ONLY for repositories the platform/CLI publishes declaratively (e.g. workload-operator image and chart). Workload application repos must NOT be declared here — CI creates them on push via the OIDC IAM role. Each platform repo gets scan-on-push, KMS encryption, IMMUTABLE tags, and the lifecycle policy below."
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
  description = "Enable ECR pull-through cache rules. When true with an empty `ecr_pull_through_cache_upstreams`, a 2-prefix anonymous default is provisioned: { k8s, public-ecr }. AWS requires Secrets Manager credentials for ghcr.io, quay.io, gitlab-registry.com, and Docker Hub — those are NOT in the default. Cached repos auto-created by ECR inherit KMS + lifecycle from `aws_ecr_repository_creation_template.pull_through_cache`."
  type        = bool
  default     = false
}

variable "ecr_pull_through_cache_upstreams" {
  description = "Pull-through cache upstreams: prefix -> upstream_registry_url. Empty + `ecr_pull_through_cache_enabled = true` activates the anonymous default { k8s = registry.k8s.io, public-ecr = public.ecr.aws }. To cache from an auth-required upstream (ghcr.io, quay.io, gitlab-registry.com, docker-hub), set this map explicitly AND provide credentials — `ecr_dockerhub_credentials_secret_arn` for Docker Hub; other authenticated upstreams currently require module extension (planned for v0.32.0)."
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

# ---------------------------------------------------------------------------
# HashiCorp Vault (v0.27.0+ — multi-provider opt-in component)
# ---------------------------------------------------------------------------
# Toggle to provision the AWS-side Vault infrastructure (KMS unseal key,
# S3 backup bucket, IRSA). When false, NO resources are created — clean
# teardown on flip back to false.
#
# Companion: estabilis-platform-gitops v0.38.0+ ships the chart values
# overlay (values/platform/vault.yaml, vault-aws.yaml) and the triple-belt
# coverage (network-policies, resource-quotas, kyverno-policies).
#
# Foundation scope only: chart deployment + auto-unseal infrastructure.
# Bootstrap (auth methods, policies, KV mount, ClusterSecretStore) is
# deferred to client-specific overlays / operational follow-up.

variable "vault_enabled" {
  description = "Provision Vault infrastructure (KMS unseal key, S3 backup bucket, IRSA) and render the platform-root Application. Toggle false to remove all Vault resources cleanly."
  type        = bool
  default     = false
}

variable "vault_chart_version" {
  description = "HashiCorp Vault Helm chart version (https://helm.releases.hashicorp.com)."
  type        = string
  default     = "0.29.1"
}

variable "vault_backup_retention_days" {
  description = "Days to retain Raft snapshot backups in S3. The CronJob that uploads snapshots is deferred to a follow-up release; the bucket + lifecycle is provisioned here so future enablement needs no IAM change."
  type        = number
  default     = 30
}

variable "vault_backup_bucket_naming" {
  description = <<-EOT
    Naming strategy for the Vault Raft snapshot backup S3 bucket.

    - 'static' (default): bucket name is `<cluster>-vault-backup`. Backward-
      compat with existing deployments. Risk: if the bucket is destroyed
      (toggle vault_enabled false → true) within the AWS S3 60-90 day
      name retention window, recreating with the same name fails.

    - 'random_suffix': bucket name is `<cluster>-vault-<random_suffix>`,
      consistent with the other 6 platform buckets (observability, velero,
      cnpg, tfstate, flow_logs, cur). Avoids the global-namespace retention
      trap on teardown+recreate cycles.

    SWITCHING FROM static -> random_suffix on a cluster that already has
    Vault data: the bucket name changes, which forces destroy+create.
    Snapshot history is lost. Plan accordingly.
  EOT
  type        = string
  default     = "static"

  validation {
    condition     = contains(["static", "random_suffix"], var.vault_backup_bucket_naming)
    error_message = "vault_backup_bucket_naming must be 'static' or 'random_suffix'."
  }
}

variable "vault_kms_deletion_window_days" {
  description = "AWS KMS deletion window for the dedicated Vault unseal key. Range 7-30 days. Lower = faster destroy on toggle off; higher = bigger window to recover an accidentally-disabled deployment."
  type        = number
  default     = 7

  validation {
    condition     = var.vault_kms_deletion_window_days >= 7 && var.vault_kms_deletion_window_days <= 30
    error_message = "vault_kms_deletion_window_days must be between 7 and 30."
  }
}

# ---------------------------------------------------------------------------
# Vault GitHub auth — config inputs for the downstream bootstrap script
# (`vault auth enable github` + `vault write auth/github/config`). The
# script reads these via `terraform output -raw`, so the values flow:
# tfvars → variable → output → bootstrap script. No TF resources consume
# them here.
# ---------------------------------------------------------------------------

variable "vault_github_org" {
  description = "GitHub organization mapped onto Vault's github auth method (token_no_default_policy=true). Org membership grants the developer policy; explicit user maps grant admin / org-admin. Required when bootstrapping the github auth method downstream."
  type        = string
  default     = ""
}

variable "vault_github_admins" {
  description = "Comma-separated GitHub usernames mapped to Vault `admin` policy (full root-equivalent access). Empty allowed but discouraged in real clusters."
  type        = string
  default     = ""
}

variable "vault_github_org_admins" {
  description = "Comma-separated GitHub usernames mapped to Vault `org-admin` policy (read/write on all secrets, no Vault-internal config)."
  type        = string
  default     = ""
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
  default = {}
}

# ---------------------------------------------------------------------------
# Default StorageClass (gp3) — see storage.tf
# ---------------------------------------------------------------------------

variable "create_default_storage_class" {
  description = <<-EOT
    Create the `gp3` StorageClass via the kubernetes provider.

    EKS 1.30+ does not ship a default in-tree gp2 StorageClass anymore,
    so leaving this off on a fresh cluster will leave every PVC Pending
    until the operator brings their own. Set to false only when the
    operator already manages a default class out-of-band.
  EOT
  type        = bool
  default     = true
}

variable "default_storage_class_is_default" {
  description = <<-EOT
    Annotate the `gp3` StorageClass with
    `storageclass.kubernetes.io/is-default-class=true`. Set to false
    when the cluster already carries another class that should be the
    cluster default (e.g., io2 for high-perf workloads).
  EOT
  type        = bool
  default     = true
}

variable "default_storage_class_encrypted" {
  description = <<-EOT
    Encrypt at rest every PVC provisioned through the `gp3`
    StorageClass. Defaults to true to match the EC2NodeClass root-disk
    policy (every node EBS is encrypted). Disabling here only makes
    sense on dev clusters where the operator has measured the
    encryption overhead on a specific workload — production should
    leave this true.
  EOT
  type        = bool
  default     = true
}

variable "default_storage_class_throughput" {
  description = <<-EOT
    gp3 baseline throughput is 125 MiB/s; AWS bills any value above
    that. Leave null to inherit the AWS free-tier baseline.
  EOT
  type        = number
  default     = null

  # Ternary, NOT `null || (...)` — Terraform's `||` does not
  # short-circuit inside `validation { condition }`, so the right-hand
  # comparison still evaluates against null and explodes with
  # "argument must not be null". The ternary form *does* short-circuit
  # and is the canonical workaround for nullable validations.
  validation {
    condition     = var.default_storage_class_throughput == null ? true : (var.default_storage_class_throughput >= 125 && var.default_storage_class_throughput <= 1000)
    error_message = "gp3 throughput must be between 125 and 1000 MiB/s when set."
  }
}

variable "default_storage_class_iops" {
  description = <<-EOT
    gp3 baseline IOPS is 3000; AWS bills any value above that. Leave
    null to inherit the AWS free-tier baseline.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.default_storage_class_iops == null ? true : (var.default_storage_class_iops >= 3000 && var.default_storage_class_iops <= 16000)
    error_message = "gp3 IOPS must be between 3000 and 16000 when set."
  }
}

# ---------------------------------------------------------------------------
# Container Network Observability — Amazon CloudWatch Network Flow Monitor
# (NFM) wired to the EKS cluster. See network-observability.tf and AWS docs:
# https://docs.aws.amazon.com/eks/latest/userguide/network-observability.html
# ---------------------------------------------------------------------------

variable "network_observability_enabled" {
  description = <<-EOT
    Enable the EKS Container Network Observability feature backed by Amazon
    CloudWatch Network Flow Monitor (NFM). Provisions an NFM Scope (or reuses
    an existing one), an NFM Monitor scoped to this EKS cluster, the
    `aws-network-flow-monitoring-agent` EKS addon, and a Pod Identity
    association binding the agent to a least-privilege IAM role.

    NFM is a paid service — see CloudWatch pricing before enabling
    cluster-wide. Disabled by default.
  EOT
  type        = bool
  default     = false
}

variable "network_observability_scope_mode" {
  description = <<-EOT
    Scope provisioning strategy. NFM's `Scope` resource is account+region
    singleton — operators with multiple clusters in the same AWS
    account+region SHOULD set `existing` on the second/Nth cluster and pass
    the existing Scope ARN via `network_observability_existing_scope_arn`.

    Valid values:
      - "create"   : provision a new Scope (default; safe for the first
                     cluster in an account+region).
      - "existing" : reuse a Scope already provisioned by a sibling
                     cluster, paying only for one Scope per account+region.
  EOT
  type        = string
  default     = "create"

  validation {
    condition     = contains(["create", "existing"], var.network_observability_scope_mode)
    error_message = "network_observability_scope_mode must be one of: \"create\", \"existing\"."
  }
}

variable "network_observability_existing_scope_arn" {
  description = <<-EOT
    ARN of an existing NFM Scope to reuse. Only consumed when
    `network_observability_scope_mode = \"existing\"`. Read this from the
    output `network_observability_scope_arn` of the cluster that owns the
    Scope.
  EOT
  type        = string
  default     = ""
}

variable "network_observability_monitor_name" {
  description = <<-EOT
    Override the NFM Monitor name. Leave empty to default to
    `<cluster-name>-monitor`. NFM Monitor names are immutable post-creation;
    set this if you need to align with an external naming convention before
    the first apply.
  EOT
  type        = string
  default     = ""
}

variable "network_observability_remote_resources" {
  description = <<-EOT
    NFM Monitor `remote_resource` blocks. Defaults to monitoring flows that
    stay within the cluster's region (`AWS::EC2::Region` keyed on
    `var.region`). Operators tracking cross-region or cross-VPC flows
    override this list — same five resource types as `local_resource`:
    AWS::EC2::VPC, AWS::EC2::Subnet, AWS::EC2::AvailabilityZone,
    AWS::EC2::Region, AWS::EKS::Cluster.

    Example:
      network_observability_remote_resources = [
        { type = "AWS::EC2::VPC",       identifier = "arn:aws:ec2:us-east-1:111122223333:vpc/vpc-abc" },
        { type = "AWS::EC2::Region",    identifier = "us-west-2" },
      ]
  EOT
  type = list(object({
    type       = string
    identifier = string
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.network_observability_remote_resources :
      contains(["AWS::EC2::VPC", "AWS::EC2::Subnet", "AWS::EC2::AvailabilityZone", "AWS::EC2::Region", "AWS::EKS::Cluster"], r.type)
    ])
    error_message = "Each remote_resource.type must be one of: AWS::EC2::VPC, AWS::EC2::Subnet, AWS::EC2::AvailabilityZone, AWS::EC2::Region, AWS::EKS::Cluster."
  }
}

variable "network_observability_addon_version" {
  description = <<-EOT
    Pin the `aws-network-flow-monitoring-agent` EKS addon version (e.g.
    `v1.1.0-eksbuild.1`). Leave null to track the most recent version
    compatible with the cluster's Kubernetes minor — matches the
    `most_recent = true` pattern used for the platform addons in eks.tf.
  EOT
  type        = string
  default     = null
}

variable "network_observability_addon_config" {
  description = <<-EOT
    Override map merged into the NFM agent addon's
    `configuration_values`. Operators expose Prometheus-style metrics from
    the agent by setting `OPEN_METRICS`, `OPEN_METRICS_ADDRESS`,
    `OPEN_METRICS_PORT`. Defaults follow AWS documentation:

      OPEN_METRICS         = "off"
      OPEN_METRICS_ADDRESS = "127.0.0.1"
      OPEN_METRICS_PORT    = 80

    Only override the keys you care about — the merge keeps the rest.
  EOT
  type        = map(any)
  default     = {}
}

variable "network_observability_agent_namespace" {
  description = <<-EOT
    Kubernetes namespace where the NFM agent runs. The addon installs the
    agent here on first apply; downstream operators referencing this name
    via Pod Identity SHOULD leave the default unless they have a strong
    reason to override.
  EOT
  type        = string
  default     = "amazon-network-flow-monitor"
}

variable "network_observability_agent_service_account" {
  description = <<-EOT
    Kubernetes ServiceAccount name used by the NFM agent. The Pod Identity
    association binds {namespace, service_account} to the IAM role; both
    sides MUST agree, so override only if the upstream addon changes the
    SA name.
  EOT
  type        = string
  default     = "aws-network-flow-monitor-agent-service-account"
}

# ---------------------------------------------------------------------------
# Fargate pod logging — see fargate-logging.tf
# ---------------------------------------------------------------------------

variable "fargate_logging_enabled" {
  description = <<-EOT
    Enable EKS Fargate pod log shipping to CloudWatch via the built-in
    Fluent Bit agent. Provisions the `aws-observability` namespace +
    `aws-logging` ConfigMap + per-Fargate-profile IAM policy granting
    CloudWatch Logs write to `/aws/eks/<cluster>/fargate`.

    Without this, Fargate pods silently drop stdout/stderr and emit
    `LoggingDisabled` warning events. Independent from `cluster_log_types`
    (control-plane logs).

    Default `true` because losing pod logs by default is a foot-gun —
    even operators using Alloy/Loki should keep this on for Fargate-bound
    pods (CoreDNS, Karpenter, ebs-csi-controller) that aren't covered by
    the Alloy DaemonSet (DaemonSets don't run on Fargate).

    Cost: CloudWatch Logs ingestion + storage. Typically $5-20/mo per
    cluster in steady state — only Fargate pods log here.
  EOT
  type        = bool
  default     = true
}

variable "fargate_log_retention_days" {
  description = <<-EOT
    Override CloudWatch Logs retention for `/aws/eks/<cluster>/fargate`.
    `null` falls back to `var.cluster_log_retention_days` (same as the
    cluster control-plane log group). Set to a different value if you
    want longer retention on pod logs vs control-plane.
  EOT
  type        = number
  default     = null
}

variable "fargate_log_kms_key_arn" {
  description = <<-EOT
    Override the KMS key used to encrypt the `/aws/eks/<cluster>/fargate`
    log group. Empty string (default) uses `aws_kms_key.s3_data` (the
    same key that encrypts observability/velero/cnpg/cost-export buckets).
  EOT
  type        = string
  default     = ""
}

variable "fargate_log_filters" {
  description = <<-EOT
    Additional Fluent Bit config snippet appended to the `aws-logging`
    ConfigMap, after the `[OUTPUT]` block. Use to add `[FILTER]` blocks
    for redaction, multi-output, drop-by-tag, etc. Format is raw Fluent
    Bit config syntax. Empty string (default) means just `[OUTPUT]`
    with no extra filters.

    Example:
      fargate_log_filters = <<-EOC
        [FILTER]
            Name modify
            Match *
            Remove sensitive_field
      EOC
  EOT
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# vpc-cni — see eks.tf vpc-cni addon block for context
# ---------------------------------------------------------------------------

variable "vpc_cni_enable_prefix_delegation" {
  description = <<-EOT
    Enable IPv4 prefix delegation on the vpc-cni addon. When `true`, each
    ENI is allocated /28 prefix chunks (16 IPs each) instead of individual
    secondary IPs, raising max pods/node from ~50 to ~110 on
    c6a.xlarge-class.

    REQUIRES contiguous /28 blocks available in EVERY subnet the cluster
    uses. In shared VPCs (multiple clusters / EC2 / RDS coexisting) the
    available IPs are usually fragmented across the subnet — prefix
    delegation fails with `InsufficientCidrBlocks` on
    `AssignPrivateIpAddresses` and pods stay in `ContainerCreating` with
    `failed to assign an IP address to container`.

    Observed on cortex-prd 2026-04-28 in shared VPC
    `vpc-main-tech-services` (subnet `subnet-0e7ee2c1d44ff476a` had only
    377/512 IPs free, fragmented across the /23 — no /28 chunks available).

    Default `false` mirrors legacy cortex-eks-prod (always-works,
    fragmentation-tolerant). Flip `true` only on dedicated VPCs.
  EOT
  type        = bool
  default     = false
}
