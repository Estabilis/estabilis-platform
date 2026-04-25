# ---------------------------------------------------------------------------
# Cloudflare credentials — AWS-side wiring.
#
# Mirrors the github-app-credentials shape (Estabilis/estabilis-platform v0.18.0):
#
#  1. modules/cloudflare-credentials/ creates the in-cluster Kubernetes
#     Secret consumed by external-dns (CF_API_TOKEN env) and cert-manager
#     DNS-01 ClusterIssuer (apiTokenSecretRef). Cloud-agnostic — the same
#     module is called from providers/azure/ via providers/azure/cloudflare.tf.
#
#  2. AWS Secrets Manager stores the API token as source-of-truth for
#     audit + rotation. When platform-secrets chart is in place,
#     ExternalSecrets Operator can reconcile the Kubernetes Secret from
#     the SM entry — rotating the token in SM propagates without a
#     Terraform apply.
#
# Both parts are gated on `dns_provider == "cloudflare"`. Other DNS
# modes (route53 / none) leave both unset.
#
# The Cloudflare zone itself is NOT managed here — it must already exist
# (created at the registrar / Cloudflare Dashboard). The cortex domain
# `estabilis-cortex.com` already lives in Cloudflare account
# 9b8e... — same zone the legacy cortex-eks-prod cluster uses.
# ---------------------------------------------------------------------------

module "cloudflare_credentials" {
  count  = var.dns_provider == "cloudflare" && var.platform_outputs_enabled ? 1 : 0
  source = "../../modules/cloudflare-credentials"

  cloudflare_zone_id   = var.cloudflare_zone_id
  cloudflare_api_token = var.cloudflare_api_token
  domain               = var.domain

  # Placed in `argocd` (managed by Terraform here) instead of
  # `external-dns` (managed by ArgoCD Application). Avoids the
  # chicken-and-egg of TF creating a Secret in a namespace the
  # cluster doesn't yet have. Cross-namespace consumption is fine
  # for the post-bootstrap path: ExternalSecrets Operator wraps this
  # K8s Secret as a ClusterSecretStore source, or charts read with
  # `secretKeyRef.namespace` set explicitly. For the legacy-style
  # path (helm.parameter), the existing platform-outputs.tf
  # passthrough remains the consumer — this Secret is the
  # source-of-truth artifact for the migration to come.
  namespace = "argocd"

  depends_on = [
    kubernetes_namespace.argocd,
  ]
}

# ---------------------------------------------------------------------------
# AWS Secrets Manager mirror — source of truth for ExternalSecrets
# reconciliation post-bootstrap.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "cloudflare_api_token" {
  count                   = var.dns_provider == "cloudflare" ? 1 : 0
  name                    = "${local.secrets_path_prefix}/platform-cloudflare-api-token"
  kms_key_id              = aws_kms_key.platform_secrets.arn
  recovery_window_in_days = var.secretsmanager_recovery_days
}

resource "aws_secretsmanager_secret_version" "cloudflare_api_token" {
  count         = var.dns_provider == "cloudflare" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.cloudflare_api_token[0].id
  secret_string = var.cloudflare_api_token
}

resource "aws_secretsmanager_secret_policy" "cloudflare_api_token" {
  count               = var.dns_provider == "cloudflare" && var.secretsmanager_resource_policy_enabled ? 1 : 0
  secret_arn          = aws_secretsmanager_secret.cloudflare_api_token[0].arn
  policy              = data.aws_iam_policy_document.platform_secret_policy[0].json
  block_public_policy = true
}
