# =============================================================================
# argocd-secret — terraform-owned (foundation v0.28.3 fix)
# =============================================================================
# Postmortem:
#
# The argo-cd chart populates `argocd-secret.data` (server.secretkey,
# admin.password, etc.) via a `redisSecretInit` Job pre-install hook.
# That hook is intentionally disabled in `core/components/argocd/values.yaml`
# because it causes `foregroundDeletion` deadlocks on ArgoCD self-manage
# sync (the App goes Progressing forever when re-applying the hook Job).
#
# Side effect: chart used to render `argocd-secret` with `data: {}`.
# Every reconcile of the `argocd` Application then ServerSideApply-
# overwrote `/data` to empty, wiping `server.secretkey`. argocd-server
# could no longer sign session tokens — Unauthorized watches, UI 401s.
#
# Fix (v0.28.3, paired with `configs.secret.createSecret = false` in
# core/components/argocd/values.yaml): terraform owns the Secret
# end-to-end. The chart no longer creates it, so the SSA wipe vector
# is eliminated at the source. ArgoCD's `argocd` Application also has
# `ignoreDifferences` on Secret/argocd-secret/data as defense in depth.
#
# Rotation: change `random_password.argocd_secretkey.keepers` to
# trigger regeneration. argocd-server picks up the new key on the
# next pod restart.
# =============================================================================

resource "random_password" "argocd_secretkey" {
  length  = 32
  special = false # base64-safe alphanumeric

  keepers = {
    cluster_name = local.cluster_name
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

  # The argocd-server pod (and operators using the UI) may write
  # additional fields here over time (e.g. admin.password, dex.* OIDC
  # secrets, repository creds when the user adds them via UI). Don't
  # fight that — terraform owns server.secretkey only; everything else
  # stays under whichever field manager wrote it.
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
