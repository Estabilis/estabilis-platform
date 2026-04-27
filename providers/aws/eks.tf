# ---------------------------------------------------------------------------
# EKS cluster
#
# Provisioned via the terraform-aws-modules/eks/aws module (v20.x series),
# which owns the cluster IAM role, OIDC provider, managed addons, and the
# node / cluster security groups. We add:
#   - Cluster encryption for Kubernetes Secrets via aws_kms_key.cluster_secrets
#   - Authentication in API-only mode + Access Entries (eks_access_entries)
#   - Fargate profiles for kube-system + karpenter namespaces (when
#     autoscaler is "karpenter" or "hybrid"), plus any extras in
#     fargate_profile_namespaces
#   - Managed Node Group for control-plane workloads (when autoscaler is
#     "cluster_autoscaler" or "hybrid")
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
      # MINIMUM_IP_TARGET + WARM_IP_TARGET is the canonical AWS pattern
      # for closing the cold-start race observed during the v0.29.0 MNG
      # rolling replacement on cortex 2026-04-26 (new nodes registered
      # Ready before aws-node finished allocating the first /28 prefix,
      # leaving a ~30s window of FailedCreatePodSandBox).
      #
      # The previous v0.29.1 attempt (WARM_PREFIX_TARGET=2 +
      # MINIMUM_IP_TARGET=10) was non-canonical: per the AWS VPC CNI
      # docs, MINIMUM_IP_TARGET only overrides WARM_PREFIX_TARGET when
      # WARM_IP_TARGET is *also* set. With only one of the pair set,
      # behavior is undefined and was observed leaving fresh nodes with
      # zero prefixes during multi-node Karpenter bursts (cortex prd
      # 2026-04-27 incident).
      #
      # Canonical config: MINIMUM_IP_TARGET pre-allocates the floor
      # before the node reports Ready (covers cold-start), WARM_IP_TARGET
      # keeps a small slack for micro-bursts. ENABLE_PREFIX_DELEGATION
      # remains so each allocation is a /28 (16 IPs) instead of a
      # single secondary IP — scales to high pod density on large
      # instances without ENI exhaustion.
      #
      # Refs:
      # - https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/prefix-and-ip-target.md
      # - https://github.com/aws/amazon-vpc-cni-k8s#warm_ip_target
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          MINIMUM_IP_TARGET        = "10"
          WARM_IP_TARGET           = "2"
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
  # karpenter namespace when autoscaler uses Karpenter ("karpenter" or
  # "hybrid"). Extras appended from var.
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
    contains(["karpenter", "hybrid"], var.autoscaler) ? {
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

  # MNG name + IAM role name selection per replacement strategy.
  # See var.mng_replacement_strategy + var.mng_generation for full rationale.
  # 'static' preserves historical names (`<cluster>-default`) for
  # backward-compat with existing deployments. 'rolling' suffixes the
  # generation so force_new changes can roll over via create_before_destroy.
  mng_default_name = var.mng_replacement_strategy == "rolling" ? (
    "${local.cluster_name}-default-gen${var.mng_generation}"
    ) : (
    "${local.cluster_name}-default"
  )
  mng_default_iam_role_name = var.mng_replacement_strategy == "rolling" ? (
    "${local.cluster_name}-default-node-gen${var.mng_generation}"
    ) : (
    "${local.cluster_name}-default-node"
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
# Validation rail: MNG size ordering (min <= desired <= max).
# Variable-level validation can't express cross-variable relations, so this
# precondition runs at plan time and fails loud if the operator inverts
# the relationship.
# ---------------------------------------------------------------------------

resource "terraform_data" "mng_size_guard" {
  count = contains(["cluster_autoscaler", "hybrid"], var.autoscaler) ? 1 : 0

  input = "${var.mng_min_size}-${var.mng_desired_size}-${var.mng_max_size}"

  lifecycle {
    precondition {
      condition     = var.mng_min_size <= var.mng_desired_size && var.mng_desired_size <= var.mng_max_size
      error_message = "MNG size ordering invalid: requires mng_min_size <= mng_desired_size <= mng_max_size. Got min=${var.mng_min_size}, desired=${var.mng_desired_size}, max=${var.mng_max_size}."
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
  # Ternary must return matching types on both branches (Terraform 1.7+
  # strict type check). `null` disables encryption cleanly without forcing
  # the "false" branch to echo the full object shape.
  cluster_encryption_config = var.cluster_secrets_encryption_enabled ? {
    resources        = ["secrets"]
    provider_key_arn = aws_kms_key.cluster_secrets.arn
  } : null

  # --- Authentication (Access Entries, AWS best practice) -----------------
  authentication_mode                      = var.authentication_mode
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  access_entries                           = local.eks_access_entries_map

  # --- IAM role naming ----------------------------------------------------
  # The EKS module defaults to `iam_role_use_name_prefix = true`, which
  # caps role names at 38 chars (AWS IAM name_prefix limit — the module
  # leaves room for the 26-char Terraform-generated suffix inside the
  # 64-char total budget). Our CAF-style cluster names
  # (`eks-{prefix}-platform-{env}-{region}`) plus the module's `-cluster`
  # suffix routinely exceed 38 chars. Using `false` switches to
  # name-mode, which allows the full 64-char budget.
  iam_role_use_name_prefix = false

  # --- Addons --------------------------------------------------------------
  cluster_addons = local.effective_addons

  # --- Fargate profiles ---------------------------------------------------
  fargate_profiles = local.fargate_profiles_default

  # --- Managed node groups -------------------------------------------------
  # Created when autoscaler provisions a persistent EC2 fleet:
  #   - 'cluster_autoscaler': MNG is the only compute (no Karpenter)
  #   - 'hybrid': MNG hosts platform control-plane; Karpenter layers on
  #     top for workloads
  # Skipped for 'karpenter' (Karpenter-only) and 'none' (BYO).
  #
  # Naming strategy: see var.mng_replacement_strategy. 'static' keeps
  # the historical name `<cluster>-default` (force_new changes require
  # manual destroy before apply). 'rolling' suffixes `-gen<N>` so that
  # force_new changes can roll over with zero downtime via create_before_destroy.
  eks_managed_node_groups = contains(["cluster_autoscaler", "hybrid"], var.autoscaler) ? {
    default = {
      name           = local.mng_default_name
      instance_types = var.mng_instance_types
      capacity_type  = var.mng_capacity_type
      min_size       = var.mng_min_size
      max_size       = var.mng_max_size
      desired_size   = var.mng_desired_size
      disk_size      = var.mng_disk_size_gb
      ami_type       = var.mng_ami_type
      subnet_ids     = local.private_subnet_ids

      # Two name-prefix overflows to disable on the submodule when the
      # cluster name is long (our CAF-style naming blows past both):
      #
      #  1. IAM role: submodule constructs `{cluster}-{ng}-eks-node-group-`
      #     before AWS appends its 26-char random suffix. 38-char cap.
      #     Switch off the prefix and supply an explicit role name.
      #
      #  2. Node-group resource: submodule constructs `{ng}-` (where
      #     {ng} is the computed name `{cluster}-{default}`). 37-char cap
      #     for the node_group_name_prefix. Switch off the prefix and let
      #     the submodule use our explicit `name` directly.
      #
      # Both constraints are the same family as module.eks (v0.15.0) and
      # module.karpenter (v0.15.2). Pinning explicit names keeps future
      # additional MNGs colliding-free.
      use_name_prefix          = false
      iam_role_use_name_prefix = false
      iam_role_name            = local.mng_default_iam_role_name

      # Attach the EKS cluster primary security group to the MNG nodes.
      # Without this, the MNG ENIs only receive the module's node
      # shared SG, which is a DIFFERENT SG from the cluster primary
      # (the SG EKS auto-creates and attaches to Fargate pod ENIs).
      # Result: traffic between MNG pods and Fargate pods (including
      # CoreDNS!) is not in the same intra-cluster trust boundary,
      # and DNS queries from MNG pods time out because the kube-dns
      # service endpoints are Fargate ENIs using a different SG.
      #
      # Observed on cortex seed 2026-04-24: DNS fully broken from
      # MNG pods, ArgoCD Application Controller unable to reach
      # argocd-redis or repo-server by service name, platform-root
      # stuck in "ComparisonError: dns: A record lookup error".
      #
      # The legacy cortex-eks-prod cluster (provisioned outside this
      # module) works because its MNG nodes end up with the cluster
      # primary SG attached directly.
      attach_cluster_primary_security_group = true

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
  # Applied whenever Karpenter is present (both 'karpenter' and 'hybrid').
  # The cluster-membership tag (kubernetes.io/cluster/<name>) is deliberately
  # NOT set here — see null_resource.untag_node_sg_cluster_membership below
  # for the deletion logic and main.tf provider's ignore_tags for the
  # drift-suppression pair.
  node_security_group_tags = contains(["karpenter", "hybrid"], var.autoscaler) ? {
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
  for_each = var.vpc_mode == "existing" && contains(["karpenter", "hybrid"], var.autoscaler) ? toset(var.private_subnet_ids) : []

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

# Cluster-membership tag. ALB Controller filters subnets by
# `kubernetes.io/cluster/<cluster-name>` to determine which subnets belong
# to this cluster — without it, public ALB provisioning fails with
# "couldn't auto-discover subnets: tagged for other clusters" when the VPC
# is shared with another EKS cluster (e.g. legacy + new running side by
# side during a migration). `shared` (vs `owned`) is appropriate because
# the platform module does NOT own the subnet lifecycle in vpc_mode =
# existing — it only annotates membership.
resource "aws_ec2_tag" "existing_subnets_cluster_membership" {
  for_each = var.vpc_mode == "existing" ? toset(concat(var.public_subnet_ids, var.private_subnet_ids)) : []

  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.cluster_name}"
  value       = "shared"
}

# ---------------------------------------------------------------------------
# Node SG cluster-tag deletion.
#
# `terraform-aws-modules/eks` v20 hardcodes
# `kubernetes.io/cluster/<name>=owned` in the node SG's tags map; combined
# with the EKS-managed cluster primary SG (auto-tagged by AWS), this gives
# every node ENI TWO cluster-tagged SGs. ALB Controller's algorithm rejects
# this state with:
#
#     "expected exactly one securityGroup tagged with
#      kubernetes.io/cluster/<name> for eni <id>, got: [<node-sg> <cluster-sg>]"
#
# blocking target rule injection on every Ingress/Service. Module exposes no
# knob to suppress; setting the value via `node_security_group_tags = { ...
# = "" }` keeps the tag KEY (which is what the controller filters on),
# making that workaround a no-op. The only effective fix is an actual
# delete-tags API call after every apply.
#
# `triggers = { always = timestamp() }` re-runs the local-exec on every
# apply, so even when the EKS module re-asserts the tag (which it will,
# every plan/apply, since terraform's drift detection sees the tag missing
# from AWS but present in the module's tags map), this resource immediately
# re-deletes it. Operators will see a small drift in plan output for the
# node SG `tags` attribute — that is the expected steady state and tracks
# the upstream module bug:
#   https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2997
#
# Provider-level `ignore_tags` would suppress the plan-output drift but
# would also disable drift detection on `aws_ec2_tag.existing_subnets_*`
# (which uses the same key), creating a silent failure mode for the subnet
# tagging fix in v0.25.0. Trading clean plan output for safer subnet drift
# detection — the local-exec idempotency keeps the cluster healthy in
# between any actual applies.
# ---------------------------------------------------------------------------
resource "null_resource" "untag_node_sg_cluster_membership" {
  triggers = {
    sg_id        = module.eks.node_security_group_id
    cluster_name = local.cluster_name
    region       = var.region
    always_run   = timestamp()
  }

  provisioner "local-exec" {
    command = "aws ec2 delete-tags --resources ${self.triggers.sg_id} --tags Key=kubernetes.io/cluster/${self.triggers.cluster_name} --region ${self.triggers.region}"
  }

  depends_on = [module.eks]
}
