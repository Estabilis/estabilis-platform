# ---------------------------------------------------------------------------
# ArgoCD – Seed Helm Release
# ---------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  wait    = true
  timeout = 600

  # Run server in insecure mode (TLS termination at ingress)
  set {
    name  = "server.insecure"
    value = "true"
  }

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  set {
    name  = "configs.rbac.policy\\.default"
    value = "role:readonly"
  }

  set {
    name  = "configs.rbac.scopes"
    value = "[groups]"
  }

  lifecycle {
    ignore_changes = [set, version]
  }
}
