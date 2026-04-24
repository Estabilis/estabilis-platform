# ---------------------------------------------------------------------------
# github-app-credentials module — main
#
# Creates a Kubernetes Secret with the ArgoCD repo-creds label, carrying
# a GitHub App's installation identifiers + PEM-encoded private key.
# ArgoCD internally exchanges (app_id, installation_id, private_key) for
# installation access tokens (1-hour TTL, auto-renewed on expiry) when
# cloning any repository under the matching org URL.
#
# Reference: https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/#github-app-credential
# ---------------------------------------------------------------------------

locals {
  # Extract the organization slug from the URL (e.g. "Cortex-Innovation"
  # from "https://github.com/Cortex-Innovation") and lowercase it for
  # RFC 1123 compatibility of the Kubernetes Secret name.
  org_slug_raw   = regex("^https://github\\.com/([^/]+)/?$", var.github_org_url)[0]
  org_slug       = lower(replace(local.org_slug_raw, "_", "-"))
  effective_name = var.secret_name != "" ? var.secret_name : "github-app-${local.org_slug}"

  # Normalize URL (strip trailing slash if present) — ArgoCD prefix
  # matching is exact up to the first `/` after the host.
  normalized_url = replace(var.github_org_url, "/+$", "")
}

resource "kubernetes_secret" "repo_creds" {
  metadata {
    name      = local.effective_name
    namespace = var.namespace

    labels = {
      # Credential template — ArgoCD matches repos by URL prefix and
      # applies this credential. Distinct from `secret-type: repository`
      # (which registers a specific repo); `repo-creds` is a template.
      "argocd.argoproj.io/secret-type" = "repo-creds"
      "app.kubernetes.io/managed-by"   = "terraform"
      "app.kubernetes.io/part-of"      = "estabilis-platform"
      "estabilis.io/component"         = "github-app-credentials"
    }
  }

  type = "Opaque"

  # Using data (not string_data) so Terraform plan diffs stay stable
  # across runs — string_data always shows as a change even when the
  # value hasn't moved.
  data = {
    type                    = "git"
    url                     = local.normalized_url
    githubAppID             = var.github_app_id
    githubAppInstallationID = var.github_app_installation_id
    githubAppPrivateKey     = var.github_app_private_key
  }
}
