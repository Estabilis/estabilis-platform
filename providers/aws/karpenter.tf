# ---------------------------------------------------------------------------
# Karpenter — IAM roles + SQS interruption queue only
#
# Important architectural choice: the Helm chart itself (karpenter 1.9.x) is
# NOT installed here. It is deployed by ArgoCD as part of the platform-root
# App-of-Apps, so that Karpenter follows the same GitOps lifecycle as every
# other platform component. This file only provisions the AWS-side infra
# that Karpenter needs before the Helm chart can function:
#
#   - Controller IAM role (IRSA) — for talking to EC2 + SQS
#   - Node IAM role — attached to instance profile used by EC2 nodes
#   - SQS interruption queue — receives EC2 Spot interruption notices
#
# The EC2NodeClass + NodePool custom resources are Kubernetes manifests and
# live in core/components/karpenter/ (Phase 2).
#
# Rendered when var.autoscaler includes Karpenter ("karpenter" or "hybrid").
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "karpenter_irsa_trust" {
  count = contains(["karpenter", "hybrid"], var.autoscaler) ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

module "karpenter" {
  count = contains(["karpenter", "hybrid"], var.autoscaler) ? 1 : 0

  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.19"

  cluster_name = module.eks.cluster_name

  # v21 of the karpenter sub-module switched the default authentication
  # path to Pod Identity (`create_pod_identity_association = true`) and
  # REMOVED the IRSA flags (`enable_irsa`, `irsa_oidc_provider_arn`).
  # Pod Identity REQUIRES the `eks-pod-identity-agent` DaemonSet running
  # on the node where the pod lands. Fargate does NOT run DaemonSets.
  #
  # Both `autoscaler = "karpenter"` (pure) and `autoscaler = "hybrid"`
  # land Karpenter pods on the `karpenter` namespace Fargate profile
  # (selectors take precedence over MNG nodes), so Pod Identity is
  # non-functional for Karpenter in ALL our modes — controller hangs
  # waiting for AWS APIs (`AWS_CONTAINER_CREDENTIALS_FULL_URI`
  # endpoint `169.254.170.23` unreachable from Fargate without the
  # agent), health probes time out, pods stuck `0/1 Ready` forever.
  # Observed on cortex-prd 2026-04-28 v0.35.0 bootstrap.
  #
  # Fix (matches legacy `cortex-eks-prod`): disable Pod Identity
  # association and add IRSA federation to the trust policy via
  # `iam_role_source_assume_policy_documents` (data block above —
  # additive merge with the module's default `pods.eks.amazonaws.com`
  # statement). The Karpenter helm chart values annotate the SA with
  # `eks.amazonaws.com/role-arn` (via platform-root helm parameters),
  # so the AWS SDK uses `AssumeRoleWithWebIdentity`.
  #
  # NOTE: AWS SDKs do NOT auto-fall-back between credential providers —
  # Pod Identity webhook injecting `AWS_CONTAINER_CREDENTIALS_FULL_URI`
  # would lock the SDK to that path. We therefore DELETE the Pod
  # Identity association entirely (not coexist with it).
  create_pod_identity_association = false

  iam_role_source_assume_policy_documents = [
    data.aws_iam_policy_document.karpenter_irsa_trust[0].json,
  ]

  # v21 controller policy exceeds the 6144-char AWS IAM customer-managed
  # policy size cap (observed on cortex 2026-04-28: `LimitExceeded:
  # Cannot exceed quota for PolicySize: 6144`). Switching to inline mode
  # uses the 10240-char inline-policy budget instead. Documented in the
  # upstream module as the canonical workaround for this exact error.
  enable_inline_policy = true

  # Node IAM role (used by EC2NodeClass). SSM is intentionally omitted —
  # pods on those nodes could escalate via Session Manager otherwise.
  node_iam_role_additional_policies = var.karpenter_node_iam_role_additional_policies

  # Default namespace + service account for the controller (must match the
  # Helm chart values.yaml that ArgoCD will render).
  namespace       = "karpenter"
  service_account = "karpenter"

  # Same IAM role naming constraint as module.eks — our cluster names
  # exceed the 38-char name_prefix budget. Use full names (64-char
  # budget) so `Karpenter-${cluster_name}` fits.
  iam_role_use_name_prefix      = false
  node_iam_role_use_name_prefix = false

  # Explicit per-cluster names. Without this override, the upstream module
  # defaults the controller role to the generic `KarpenterController`
  # (hardcoded string) and the node role to `Karpenter-<cluster>`. Two
  # Estabilis deployments in the same AWS account would collide on
  # `KarpenterController`. Pinning both to include the cluster name gives
  # unambiguous ownership per deployment.
  iam_role_name      = "Karpenter-${module.eks.cluster_name}"
  node_iam_role_name = "KarpenterNode-${module.eks.cluster_name}"

  tags = {
    (var.karpenter_discovery_tag_key) = local.cluster_name
  }
}

# Validation rail: cluster_name length must be enough to keep Karpenter IAM
# role names (`Karpenter-<cluster>` / `KarpenterNode-<cluster>`) unique
# across deployments in the same AWS account. Without this rail, two
# deployments with very short or identical cluster_name prefixes would
# silently collide on the IAM role names — a foot-gun discovered when
# auditing replacement collisions.
resource "terraform_data" "karpenter_naming_guard" {
  count = contains(["karpenter", "hybrid"], var.autoscaler) ? 1 : 0

  input = local.cluster_name

  lifecycle {
    precondition {
      condition     = length(local.cluster_name) >= 8
      error_message = "cluster_name must be >= 8 chars when Karpenter is enabled, to keep IAM role names (`Karpenter-<cluster>` / `KarpenterNode-<cluster>`) unique across deployments in the same AWS account. Current length: ${length(local.cluster_name)}."
    }
  }
}

# Allow Karpenter controller to garbage-collect orphaned instance profiles.
resource "aws_iam_role_policy" "karpenter_instance_profile_gc" {
  count = contains(["karpenter", "hybrid"], var.autoscaler) ? 1 : 0

  name = "${local.cluster_name}-karpenter-instance-profile-gc"
  role = module.karpenter[0].iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iam:ListInstanceProfiles"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/karpenter/*"
      },
    ]
  })
}
