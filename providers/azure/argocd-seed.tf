# ---------------------------------------------------------------------------
# ArgoCD – Seed Helm Release
# ---------------------------------------------------------------------------
# Minimal bootstrap installation. After first reconciliation, the ArgoCD
# Application self-managed (bootstrap/platform-root/templates/argocd.yaml)
# takes over all configuration via GitOps.
#
# Only server.insecure is set here (required for seed to work without TLS).
# All other configs (RBAC, polling, replicas) are in:
#   core/components/argocd/values.yaml

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  wait    = true
  timeout = 600

  # Minimal config — only what's needed for bootstrap
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  lifecycle {
    ignore_changes = [set, version]
  }
}

# ---------------------------------------------------------------------------
# Private config repo credentials — created as a separate Secret so ArgoCD
# auto-detects it via the argocd.argoproj.io/secret-type label.
# This avoids the ignore_changes problem with helm_release set_sensitive.
# ---------------------------------------------------------------------------
resource "kubernetes_secret" "argocd_repo_config" {
  count = var.config_repo_token != "" ? 1 : 0

  metadata {
    name      = "repo-config-downstream"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    url      = var.config_repo_url
    username = "x-access-token"
    password = var.config_repo_token
    type     = "git"
  }

  depends_on = [helm_release.argocd]
}
