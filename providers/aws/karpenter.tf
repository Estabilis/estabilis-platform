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
# Only rendered when var.autoscaler = "karpenter".
# ---------------------------------------------------------------------------

module "karpenter" {
  count = var.autoscaler == "karpenter" ? 1 : 0

  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.37"

  cluster_name = module.eks.cluster_name

  # Create IAM role for the Karpenter controller (IRSA).
  enable_irsa            = true
  irsa_oidc_provider_arn = module.eks.oidc_provider_arn

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

# Allow Karpenter controller to garbage-collect orphaned instance profiles.
resource "aws_iam_role_policy" "karpenter_instance_profile_gc" {
  count = var.autoscaler == "karpenter" ? 1 : 0

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
