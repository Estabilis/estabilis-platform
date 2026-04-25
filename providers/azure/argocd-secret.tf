# =============================================================================
# argocd-secret — terraform-owned (foundation v0.28.3 fix, Azure mirror)
# =============================================================================
# See providers/aws/argocd-secret.tf for the full postmortem + fix
# rationale. Same problem on AKS — the argo-cd chart's empty
# `argocd-secret` would be re-applied on every self-sync, wiping
# server.secretkey.
#
# Fix (v0.28.3, paired with `configs.secret.createSecret = false` in
# core/components/argocd/values.yaml): terraform owns the Secret
# end-to-end.
# =============================================================================

resource "random_password" "argocd_secretkey" {
  length  = 32
  special = false

  keepers = {
    cluster_name = azurerm_kubernetes_cluster.platform.name
  }
}

resource "kubernetes_secret" "argocd_secret" {
  count = var.platform_outputs_enabled ? 1 : 0

  metadata {
    name      = "argocd-secret"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "estabilis-platform"
      "app.kubernetes.io/name"       = "argocd-secret"
    }
  }

  type = "Opaque"

  data = {
    "server.secretkey" = random_password.argocd_secretkey.result
  }

  lifecycle {
    ignore_changes = [
      data["admin.password"],
      data["admin.passwordMtime"],
      data["webhook.github.secret"],
      data["webhook.gitlab.secret"],
      data["webhook.bitbucketserver.secret"],
      data["webhook.bitbucket.uuid"],
      data["webhook.gogs.secret"],
      data["webhook.azuredevops.username"],
      data["webhook.azuredevops.password"],
      data["dex.github.clientSecret"],
      data["dex.gitlab.clientSecret"],
    ]
  }
}
