# ---------------------------------------------------------------------------
# Cluster Autoscaler (alternative to Karpenter)
#
# When var.autoscaler = "cluster_autoscaler" we rely on the managed node
# group defined in eks.tf and provide the IRSA role for the cluster
# autoscaler controller. The Helm chart itself is installed by ArgoCD.
#
# When var.autoscaler != "cluster_autoscaler" this file is a no-op.
# ---------------------------------------------------------------------------

module "cluster_autoscaler_irsa" {
  count = var.autoscaler == "cluster_autoscaler" ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"

  role_name                        = "${local.cluster_name}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}
