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

  # Private config repo credentials — injected via configs.repositories
  dynamic "set_sensitive" {
    for_each = var.config_repo_token != "" ? [1] : []
    content {
      name  = "configs.repositories.config-repo.url"
      value = var.config_repo_url
    }
  }

  dynamic "set_sensitive" {
    for_each = var.config_repo_token != "" ? [1] : []
    content {
      name  = "configs.repositories.config-repo.username"
      value = "x-access-token"
    }
  }

  dynamic "set_sensitive" {
    for_each = var.config_repo_token != "" ? [1] : []
    content {
      name  = "configs.repositories.config-repo.password"
      value = var.config_repo_token
    }
  }

  lifecycle {
    ignore_changes = [set, set_sensitive, version]
  }
}
