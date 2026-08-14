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
# Mimir Alertmanager Slack webhooks — one secret per channel (tier 1/2/3).
# Consumed by the mimir-alertmanager-config chart's ExternalSecret (which
# pulls into K8s Secret `alertmanager-slack-webhooks` in the grafana ns).
# Gated by slack_alerting_enabled + per-URL non-empty (matching openai
# pattern: empty value = no SM resource = chart's ExternalSecret also
# skipped via slack.enabled gate, so no SecretSyncError noise).
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "alertmanager_slack_critical" {
  count                   = var.slack_alerting_enabled && var.slack_webhook_alertmanager_critical != "" ? 1 : 0
  name                    = "${local.secrets_path_prefix}/platform-alertmanager-slack-critical"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "alertmanager_slack_critical" {
  count         = var.slack_alerting_enabled && var.slack_webhook_alertmanager_critical != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.alertmanager_slack_critical[0].id
  secret_string = var.slack_webhook_alertmanager_critical
}

resource "aws_secretsmanager_secret" "alertmanager_slack_warnings" {
  count                   = var.slack_alerting_enabled && var.slack_webhook_alertmanager_warnings != "" ? 1 : 0
  name                    = "${local.secrets_path_prefix}/platform-alertmanager-slack-warnings"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "alertmanager_slack_warnings" {
  count         = var.slack_alerting_enabled && var.slack_webhook_alertmanager_warnings != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.alertmanager_slack_warnings[0].id
  secret_string = var.slack_webhook_alertmanager_warnings
}

resource "aws_secretsmanager_secret" "alertmanager_slack_info" {
  count                   = var.slack_alerting_enabled && var.slack_webhook_alertmanager_info != "" ? 1 : 0
  name                    = "${local.secrets_path_prefix}/platform-alertmanager-slack-info"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "alertmanager_slack_info" {
  count         = var.slack_alerting_enabled && var.slack_webhook_alertmanager_info != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.alertmanager_slack_info[0].id
  secret_string = var.slack_webhook_alertmanager_info
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

locals {
  # Who may manage these secrets through the resource policy.
  #
  # Previously this was `data.aws_caller_identity.current.arn` — the SESSION
  # arn of whoever ran apply. That is not a stable value: the session name is
  # part of the arn, so the policy recorded one session of one role rather than
  # a principal. It looked stable only because a single operator applying from
  # SSO reuses the same session name.
  #
  # It stops looking stable the moment anything else runs Terraform against the
  # same state. A CI role's session name typically embeds the run id, so every
  # run produced a diff on every one of these policies, and an apply from CI
  # would have written a session arn that ceases to exist when the job ends —
  # leaving the statement pointing at nobody.
  #
  # Default now resolves the caller to its ROLE arn, which is stable across
  # sessions. Set `secrets_manager_admin_principals` to stop deriving it at all:
  # then the policy states who is meant to manage these secrets, the value is
  # reviewable in a diff, and a plan means the same thing regardless of which
  # runner produced it. That last property is what makes CI usable here.
  secrets_manager_admin_principals = length(var.secrets_manager_admin_principals) > 0 ? var.secrets_manager_admin_principals : [data.aws_iam_session_context.current.issuer_arn]
}

data "aws_iam_policy_document" "platform_secret_policy" {
  count = var.secretsmanager_resource_policy_enabled ? 1 : 0

  statement {
    sid    = "AllowTerraformPrincipal"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = local.secrets_manager_admin_principals
    }

    actions   = ["secretsmanager:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowExternalSecretsIRSA"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [module.external_secrets_irsa.arn]
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

resource "aws_secretsmanager_secret_policy" "alertmanager_slack_critical" {
  count               = var.slack_alerting_enabled && var.slack_webhook_alertmanager_critical != "" && var.secretsmanager_resource_policy_enabled ? 1 : 0
  secret_arn          = aws_secretsmanager_secret.alertmanager_slack_critical[0].arn
  policy              = data.aws_iam_policy_document.platform_secret_policy[0].json
  block_public_policy = true
}

resource "aws_secretsmanager_secret_policy" "alertmanager_slack_warnings" {
  count               = var.slack_alerting_enabled && var.slack_webhook_alertmanager_warnings != "" && var.secretsmanager_resource_policy_enabled ? 1 : 0
  secret_arn          = aws_secretsmanager_secret.alertmanager_slack_warnings[0].arn
  policy              = data.aws_iam_policy_document.platform_secret_policy[0].json
  block_public_policy = true
}

resource "aws_secretsmanager_secret_policy" "alertmanager_slack_info" {
  count               = var.slack_alerting_enabled && var.slack_webhook_alertmanager_info != "" && var.secretsmanager_resource_policy_enabled ? 1 : 0
  secret_arn          = aws_secretsmanager_secret.alertmanager_slack_info[0].arn
  policy              = data.aws_iam_policy_document.platform_secret_policy[0].json
  block_public_policy = true
}
