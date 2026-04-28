# ---------------------------------------------------------------------------
# AWS Load Balancer Controller — IRSA only
#
# The Helm chart itself is installed by ArgoCD as part of the platform-root
# App-of-Apps (when ingress_controller = 'alb'). This file provides the IAM
# role + policy that the controller's ServiceAccount assumes via IRSA.
#
# The upstream iam-role-for-service-accounts-eks submodule bundles the full
# ALB Controller IAM policy (auto-kept in sync with AWS's published policy).
# ---------------------------------------------------------------------------

module "alb_controller_irsa" {
  count = var.ingress_controller == "alb" ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.5"

  # v6 default flipped use_name_prefix to true; pin false (see eks.tf).
  use_name_prefix                        = false
  name                                   = "${local.cluster_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["aws-load-balancer-controller:aws-load-balancer-controller"]
    }
  }
}
