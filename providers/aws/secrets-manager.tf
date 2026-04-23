# ---------------------------------------------------------------------------
# Secrets Manager — platform secrets (1:1 mirror of keyvault.tf in the
# Azure provider).
#
# Secrets live at: estabilis/{deployment_id}/<name>
# IAM policies scope access via the path prefix so cross-deployment access
# is denied even inside the same AWS account.
#
# Each secret has SSE with aws_kms_key.platform_secrets. When
# secretsmanager_resource_policy_enabled = true a resource policy is also
# attached to double-enforce the scoping (belt + braces for multi-tenant).
# ---------------------------------------------------------------------------

# shared_hub_secrets_prefix_effective is in locals.tf (shared with
# iam.tf, platform-outputs.tf, outputs.tf).
locals {
  secrets_path_prefix = "estabilis/${var.deployment_id}"
}

# ---------------------------------------------------------------------------
# Generated values
# ---------------------------------------------------------------------------

resource "random_password" "argocd_redis" {
  length  = 32
  special = false
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "random_password" "grafana_db" {
  length  = 32
  special = false
}

# ---------------------------------------------------------------------------
# argocd-redis
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "argocd_redis" {
  name                    = "${local.secrets_path_prefix}/platform-argocd-redis-password"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "argocd_redis" {
  secret_id     = aws_secretsmanager_secret.argocd_redis.id
  secret_string = random_password.argocd_redis.result
}

# ---------------------------------------------------------------------------
# grafana-admin
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "grafana_admin" {
  name                    = "${local.secrets_path_prefix}/platform-grafana-admin-password"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id     = aws_secretsmanager_secret.grafana_admin.id
  secret_string = random_password.grafana_admin.result
}

# ---------------------------------------------------------------------------
# grafana-db
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "grafana_db" {
  name                    = "${local.secrets_path_prefix}/platform-grafana-db-password"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "grafana_db" {
  secret_id     = aws_secretsmanager_secret.grafana_db.id
  secret_string = random_password.grafana_db.result
}

# ---------------------------------------------------------------------------
# Optional — config repo tokens, OpenAI API key, OpenCost service key. Only
# created when the matching variable is non-empty (preserves the Azure
# conditional-secret pattern from keyvault.tf).
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "config_repo_token" {
  count                   = var.config_repo_token != "" ? 1 : 0
  name                    = "${local.secrets_path_prefix}/platform-config-repo-token"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "config_repo_token" {
  count         = var.config_repo_token != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.config_repo_token[0].id
  secret_string = var.config_repo_token
}

resource "aws_secretsmanager_secret" "client_gitops_repo_token" {
  count                   = var.client_gitops_repo_token != "" ? 1 : 0
  name                    = "${local.secrets_path_prefix}/platform-client-gitops-repo-token"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "client_gitops_repo_token" {
  count         = var.client_gitops_repo_token != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.client_gitops_repo_token[0].id
  secret_string = var.client_gitops_repo_token
}

resource "aws_secretsmanager_secret" "openai_api_key" {
  count                   = var.openai_api_key != "" ? 1 : 0
  name                    = "${local.secrets_path_prefix}/platform-openai-api-key"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  count         = var.openai_api_key != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.openai_api_key[0].id
  secret_string = var.openai_api_key
}

# ---------------------------------------------------------------------------
# Resource policies — defense-in-depth on top of IAM identity policies.
#
# Only the Terraform principal (for apply/destroy) and the external-secrets
# IRSA role (for read) are granted access. Resource is scoped to the path
# itself (Resource = "*" inside a resource policy refers to the attached
# secret only, which is already path-scoped by construction).
#
# Intentionally NO "Deny everyone else" statement: AWS IAM is deny-by-default,
# and adding a blanket Deny blocks legitimate service principals (Secrets
# Manager rotation, CloudTrail, Config recorder) that are not in the
# principal list. The IAM identity policy on external-secrets
# (iam.tf:external_secrets_secrets_manager_arns) already enforces the
# per-deployment scope from the caller side.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "platform_secret_policy" {
  count = var.secretsmanager_resource_policy_enabled ? 1 : 0

  statement {
    sid    = "AllowTerraformPrincipal"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.arn]
    }

    actions   = ["secretsmanager:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowExternalSecretsIRSA"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [module.external_secrets_irsa.iam_role_arn]
    }

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["*"]
  }
}

resource "aws_secretsmanager_secret_policy" "argocd_redis" {
  count               = var.secretsmanager_resource_policy_enabled ? 1 : 0
  secret_arn          = aws_secretsmanager_secret.argocd_redis.arn
  policy              = data.aws_iam_policy_document.platform_secret_policy[0].json
  block_public_policy = true
}

resource "aws_secretsmanager_secret_policy" "grafana_admin" {
  count               = var.secretsmanager_resource_policy_enabled ? 1 : 0
  secret_arn          = aws_secretsmanager_secret.grafana_admin.arn
  policy              = data.aws_iam_policy_document.platform_secret_policy[0].json
  block_public_policy = true
}

resource "aws_secretsmanager_secret_policy" "grafana_db" {
  count               = var.secretsmanager_resource_policy_enabled ? 1 : 0
  secret_arn          = aws_secretsmanager_secret.grafana_db.arn
  policy              = data.aws_iam_policy_document.platform_secret_policy[0].json
  block_public_policy = true
}
