# ---------------------------------------------------------------------------
# Provider configuration
#
# AWS provider picks up credentials from (in order): environment variables,
# the aws_profile variable if set, IAM instance profile, SSO/SSM. Tags on
# resources that support tagging are automatically merged with default_tags.
# ---------------------------------------------------------------------------

provider "aws" {
  region  = var.region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = local.tags
  }
}

# Kubernetes + Helm providers authenticate against the freshly-provisioned
# EKS cluster via `aws eks get-token`. exec() is the supported pattern for
# long-running applies where the IAM auth token would otherwise expire
# between plan and apply.

provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = local.cluster_ca_certificate
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = local.cluster_ca_certificate
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.region]
    }
  }
}

# ---------------------------------------------------------------------------
# Account + region context
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# CAF naming + tags — kept byte-compatible with the Azure provider so client
# downstream tfvars can reuse the same CAF tag keys across providers.
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

  # Region code used in resource names. Uses the AWS-official region string
  # (with dashes) so names match every AWS CLI, tag, and documentation.
  # Example: us-east-1 -> eks-{prefix}-platform-{env}-us-east-1. Dashes
  # inside region_code are harmless — every AWS resource name that we
  # derive (EKS cluster, IAM roles, S3 buckets, KMS aliases) allows them.
  region_code = var.region

  base_name = "${var.name_prefix}-platform-${local.env_code}-${local.region_code}"

  cluster_name = "eks-${local.base_name}"

  # CAF tags — automatic + optional (empty values filtered out). Applied to
  # every resource via provider default_tags. Per-resource blocks may add
  # AWS-specific tags (e.g., karpenter.sh/discovery); AWS merges them.
  caf_tags = {
    for k, v in {
      # Functional
      app        = coalesce(var.tag_app, var.name_prefix)
      env        = local.env_code
      region     = var.region
      tier       = var.tag_tier
      managed-by = "terraform"
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
# Cluster reference shortcuts — populated in eks.tf. Centralizing here keeps
# the provider blocks above stable regardless of how eks.tf evolves.
# ---------------------------------------------------------------------------

locals {
  cluster_endpoint          = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate    = try(base64decode(module.eks.cluster_certificate_authority_data), "")
  cluster_oidc_issuer_url   = try(module.eks.cluster_oidc_issuer_url, "")
  cluster_oidc_provider_arn = try(module.eks.oidc_provider_arn, "")
}

# ---------------------------------------------------------------------------
# Host derivation — {app}.{cluster_name}.{domain}. Identical shape to the
# Azure provider so exposure maps behave the same.
# ---------------------------------------------------------------------------

locals {
  _app_host = {
    for app in ["grafana", "argocd", "loki", "mimir", "hubble", "vault"] : app =>
    "${app}.${local.cluster_name}.${var.domain}"
  }

  grafana_exposures_resolved = {
    for k, v in var.grafana_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.grafana
    })
  }
  loki_exposures_resolved = {
    for k, v in var.loki_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.loki
    })
  }
  mimir_exposures_resolved = {
    for k, v in var.mimir_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.mimir
    })
  }
  argocd_exposures_resolved = {
    for k, v in var.argocd_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.argocd
    })
  }
  hubble_ui_exposures_resolved = {
    for k, v in var.hubble_ui_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.hubble
    })
  }
  vault_exposures_resolved = {
    for k, v in var.vault_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.vault
    })
  }
}

# ---------------------------------------------------------------------------
# Revision resolution — bridges legacy *_version vars and the new *_revision
# vars introduced by ADR 0020 (branch tracking). The resolved values flow
# into platform-outputs.tf to become ArgoCD Application targetRevision.
# ---------------------------------------------------------------------------

locals {
  platform_revision_effective      = length(var.platform_revision) > 0 ? var.platform_revision : var.platform_version
  config_repo_revision_effective   = length(var.config_repo_revision) > 0 ? var.config_repo_revision : var.config_repo_version
  client_gitops_revision_effective = length(var.client_gitops_repo_revision) > 0 ? var.client_gitops_repo_revision : var.client_gitops_repo_version
}

# ---------------------------------------------------------------------------
# Operator IP — auto-detected. Used to:
#   - Append to authorized_ip_ranges for the EKS API server allowlist when
#     cluster_endpoint_public_access = true and authorized_ip_ranges is set.
#   - Seed S3 bucket policies that restrict access by source IP when the
#     deployment is fully public-endpoint.
# ---------------------------------------------------------------------------

data "http" "operator_ip" {
  url = "https://api.ipify.org"
}

locals {
  operator_ip = "${chomp(data.http.operator_ip.response_body)}/32"

  # EKS API allowlist: user-provided CIDRs + operator IP. If the user did
  # not provide any CIDR and the public endpoint is enabled, fall back to
  # 0.0.0.0/0 (documented behavior in the authorized_ip_ranges variable —
  # must be consciously opted in via allow_public_api_endpoint = true).
  authorized_ips = length(var.authorized_ip_ranges) > 0 ? distinct(concat(var.authorized_ip_ranges, [local.operator_ip])) : ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Safety check — refuse to expose the EKS API to the internet without an
# explicit acknowledgement. Public endpoint + empty allowlist =
# 0.0.0.0/0 effectively; that is almost always a mistake.
# ---------------------------------------------------------------------------

check "public_api_endpoint_requires_acknowledgement" {
  assert {
    condition = !(
      var.cluster_endpoint_public_access &&
      length(var.authorized_ip_ranges) == 0 &&
      !var.allow_public_api_endpoint
    )
    error_message = "Public EKS endpoint with no CIDR allowlist requires var.allow_public_api_endpoint = true. Either set authorized_ip_ranges to a non-empty list, disable cluster_endpoint_public_access, or opt in explicitly."
  }
}

# ---------------------------------------------------------------------------
# Subnet CIDR computation (vpc_mode = "create"). When vpc_mode = "existing"
# these locals are unused — vpc.tf consumes var.private_subnet_ids /
# var.public_subnet_ids directly.
# ---------------------------------------------------------------------------

locals {
  azs_available = data.aws_availability_zones.available.names

  azs_selected = slice(local.azs_available, 0, var.availability_zone_count)

  private_subnet_cidrs = [
    for i in range(var.availability_zone_count) : cidrsubnet(var.vpc_cidr, var.private_subnet_newbits, i)
  ]

  public_subnet_cidrs = [
    for i in range(var.availability_zone_count) : cidrsubnet(var.vpc_cidr, var.public_subnet_newbits, var.public_subnet_offset + i)
  ]
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# ---------------------------------------------------------------------------
# Random suffix — used by globally-unique S3 bucket names (tfstate,
# observability, velero, cost-export). AWS S3 bucket names are globally
# unique across all accounts, so a stable suffix is mandatory.
# ---------------------------------------------------------------------------

resource "random_string" "bucket_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}
