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
