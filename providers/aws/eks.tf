# ---------------------------------------------------------------------------
# EKS cluster
#
# Provisioned via the terraform-aws-modules/eks/aws module (v20.x series),
# which owns the cluster IAM role, OIDC provider, managed addons, and the
# node / cluster security groups. We add:
#   - Cluster encryption for Kubernetes Secrets via aws_kms_key.cluster_secrets
#   - Authentication in API-only mode + Access Entries (eks_access_entries)
#   - Fargate profiles for kube-system + karpenter namespaces (when
#     autoscaler = "karpenter"), plus any extras in fargate_profile_namespaces
#   - The additional SG from security-groups.tf for operator ingress/extras
#   - karpenter.sh/discovery tag on cluster + node SG (so Karpenter can find
#     them for nodeClass lookups)
# ---------------------------------------------------------------------------

locals {
  # Default addons — merged with var.cluster_addons (user override wins).
  # eks-pod-identity-agent is installed even though IRSA is the primary auth
  # path; keeps the door open for per-pod migrations without a cluster
  # upgrade later.
  default_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        computeType = "Fargate"
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
        }
      })
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  effective_addons = length(keys(var.cluster_addons)) > 0 ? var.cluster_addons : local.default_addons

  # Fargate profiles — kube-system is always included (addons land here),
  # karpenter when autoscaler = "karpenter". Extras appended from var.
  fargate_profiles_default = merge(
    {
      kube_system = {
        name = "kube-system"
        selectors = [
          { namespace = "kube-system" },
        ]
        subnet_ids = local.private_subnet_ids
      }
    },
    var.autoscaler == "karpenter" ? {
      karpenter = {
        name = "karpenter"
        selectors = [
          { namespace = "karpenter" },
        ]
        subnet_ids = local.private_subnet_ids
      }
    } : {},
    {
      for ns in var.fargate_profile_namespaces : replace(ns, "-", "_") => {
        name = ns
        selectors = [
          { namespace = ns },
        ]
        subnet_ids = local.private_subnet_ids
      }
    },
  )

  # Access entries converted from our flat variable shape to the module shape.
  eks_access_entries_map = {
    for idx, entry in var.eks_access_entries : "entry_${idx}" => {
      principal_arn     = entry.principal_arn
      kubernetes_groups = entry.kubernetes_groups
      policy_associations = entry.policy_arn != "" ? {
        default = {
          policy_arn = entry.policy_arn
          access_scope = {
            type       = entry.access_scope_type
            namespaces = entry.namespaces
          }
        }
      } : {}
    }
  }
}

# ---------------------------------------------------------------------------
# IRSA for EBS CSI driver (needed by the addon; separated from iam.tf so
# eks.tf stays self-contained for the cluster boot path)
# ---------------------------------------------------------------------------

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  # --- Networking ----------------------------------------------------------
  vpc_id                   = local.vpc_id
  subnet_ids               = local.private_subnet_ids
  control_plane_subnet_ids = local.private_subnet_ids

  cluster_additional_security_group_ids = var.security_groups_hardening_enabled ? [aws_security_group.cluster_additional[0].id] : []

  # --- Endpoint access -----------------------------------------------------
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access ? local.authorized_ips : null

  # --- Control-plane logging ----------------------------------------------
  cluster_enabled_log_types              = var.cluster_log_types
  cloudwatch_log_group_retention_in_days = var.cluster_log_retention_days

  # --- Secrets encryption (envelope) --------------------------------------
  cluster_encryption_config = var.cluster_secrets_encryption_enabled ? {
    resources        = ["secrets"]
    provider_key_arn = aws_kms_key.cluster_secrets.arn
  } : {}

  # --- Authentication (Access Entries, AWS best practice) -----------------
  authentication_mode                      = var.authentication_mode
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  access_entries                           = local.eks_access_entries_map

  # --- Addons --------------------------------------------------------------
  cluster_addons = local.effective_addons

  # --- Fargate profiles ---------------------------------------------------
  fargate_profiles = local.fargate_profiles_default

  # --- Managed node groups (only when cluster_autoscaler is selected;
  # karpenter mode uses Fargate + Karpenter-provisioned EC2) --------------
  eks_managed_node_groups = var.autoscaler == "cluster_autoscaler" ? {
    default = {
      name           = "${local.cluster_name}-default"
      instance_types = var.mng_instance_types
      capacity_type  = var.mng_capacity_type
      min_size       = var.mng_min_size
      max_size       = var.mng_max_size
      desired_size   = var.mng_desired_size
      disk_size      = var.mng_disk_size_gb
      ami_type       = var.mng_ami_type
      subnet_ids     = local.private_subnet_ids
      labels = {
        "estabilis.io/workload-type" = "platform"
        "estabilis.io/pool-type"     = "regular"
        "estabilis.io/schedulable"   = "regular"
      }
    }
  } : {}

  # --- Node SG rules — allow Karpenter nodes to talk to each other and to
  # the coredns/kube-proxy Fargate workers. Module defaults already cover
  # most EKS needs; this lets future operator overrides live here without
  # touching the module call. ---------------------------------------------
  node_security_group_additional_rules = {}

  # --- Node SG tags for Karpenter discovery -------------------------------
  node_security_group_tags = var.autoscaler == "karpenter" ? {
    (var.karpenter_discovery_tag_key) = local.cluster_name
  } : {}

  tags = {
    # Karpenter uses this to find the cluster when provisioning new nodes.
    # Tag-key is configurable via var.karpenter_discovery_tag_key so multiple
    # Karpenter-managed clusters can share a VPC without overwriting each
    # other's subnet tags.
    (var.karpenter_discovery_tag_key) = local.cluster_name
  }
}

# ---------------------------------------------------------------------------
# Subnet tag re-inforcement for existing-VPC mode. When the operator brings
# their own subnets, we can only best-effort add the discovery tags — they
# are required for ALB Controller + Karpenter to find the subnets.
# ---------------------------------------------------------------------------

resource "aws_ec2_tag" "existing_private_karpenter_discovery" {
  for_each = var.vpc_mode == "existing" && var.autoscaler == "karpenter" ? toset(var.private_subnet_ids) : []

  resource_id = each.value
  key         = var.karpenter_discovery_tag_key
  value       = local.cluster_name
}

resource "aws_ec2_tag" "existing_private_internal_elb" {
  for_each = var.vpc_mode == "existing" ? toset(var.private_subnet_ids) : []

  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

resource "aws_ec2_tag" "existing_public_elb" {
  for_each = var.vpc_mode == "existing" ? toset(var.public_subnet_ids) : []

  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}
