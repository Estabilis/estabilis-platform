# ---------------------------------------------------------------------------
# GitHub App credentials for ArgoCD — AWS-side wiring.
#
# Composed of two pieces:
#
#  1. modules/github-app-credentials/ creates the in-cluster Kubernetes
#     Secret ArgoCD reads (cloud-agnostic — same module is used by
#     providers/azure/, providers/gcp/, ...).
#
#  2. AWS Secrets Manager stores the PEM as source-of-truth for audit
#     and rotation. When platform-secrets chart is in place (post-seed),
#     ExternalSecrets Operator reconciles the Kubernetes Secret with the
#     SM entry — rotation in SM propagates to the K8s Secret within the
#     refresh interval without a Terraform apply.
#
# Both parts are gated on `github_app_private_key != ""` so a deployment
# that opts for a different auth path (deploy keys, per-user PATs) can
# leave all four github_app_* variables empty and nothing is created.
# ---------------------------------------------------------------------------

# Validation that composes across multiple inputs — can't live in a
# single variable's validation block because it needs to inspect several
# values.
resource "null_resource" "github_app_vars_validation" {
  count = var.github_app_id != "" || var.github_app_installation_id != "" || var.github_app_private_key != "" || var.github_org_url != "" ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.github_app_id != "" && var.github_app_installation_id != "" && var.github_app_private_key != "" && var.github_org_url != ""
      error_message = "When using GitHub App authentication, all four of github_app_id, github_app_installation_id, github_app_private_key, and github_org_url must be set. Leave all four empty to disable."
    }
  }
}

module "github_app_credentials" {
  count  = var.github_app_private_key != "" && var.platform_outputs_enabled ? 1 : 0
  source = "../../modules/github-app-credentials"

  github_app_id              = var.github_app_id
  github_app_installation_id = var.github_app_installation_id
  github_app_private_key     = var.github_app_private_key
  github_org_url             = var.github_org_url
  namespace                  = "argocd"

  depends_on = [
    kubernetes_namespace_v1.argocd,
  ]
}

# ---------------------------------------------------------------------------
# AWS Secrets Manager mirror — source of truth for ExternalSecrets
# reconciliation post-bootstrap.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "github_app_private_key" {
  count                   = var.github_app_private_key != "" ? 1 : 0
  name                    = "${local.secrets_path_prefix}/platform-github-app-private-key"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "github_app_private_key" {
  count         = var.github_app_private_key != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.github_app_private_key[0].id
  secret_string = var.github_app_private_key
}

resource "aws_secretsmanager_secret_policy" "github_app_private_key" {
  count               = var.github_app_private_key != "" && var.secretsmanager_resource_policy_enabled ? 1 : 0
  secret_arn          = aws_secretsmanager_secret.github_app_private_key[0].arn
  policy              = data.aws_iam_policy_document.platform_secret_policy[0].json
  block_public_policy = true
}
