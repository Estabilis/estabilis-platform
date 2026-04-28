# ---------------------------------------------------------------------------
# cloudflare-credentials module — main
#
# Creates a Kubernetes Secret carrying a Cloudflare API token + the zone
# ID it scopes to. Consumed (today via helm.parameter passthrough,
# eventually via direct secretRef) by:
#   - external-dns (CF_API_TOKEN env var → DNS record CRUD)
#   - cert-manager DNS-01 ClusterIssuer (apiTokenSecretRef → cert issuance)
#
# The Cloudflare zone itself is NOT managed by this module — it must
# already exist (created at the registrar / Cloudflare Dashboard
# manually). The token's permissions must include Zone:DNS:Edit and
# Zone:Zone:Read on the target zone.
#
# Reference: https://developers.cloudflare.com/fundamentals/api/get-started/create-token/
# ---------------------------------------------------------------------------

locals {
  effective_name = var.secret_name != "" ? var.secret_name : "cloudflare-credentials"
}

resource "kubernetes_secret_v1" "cloudflare_credentials" {
  metadata {
    name      = local.effective_name
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "estabilis-platform"
      "estabilis.io/component"       = "cloudflare-credentials"
    }
  }

  type = "Opaque"

  # Stable data fields. Charts that consume this Secret read:
  #   - api-token: full token string (no `Bearer ` prefix)
  #   - zone-id  : 32-char Cloudflare zone identifier
  #   - domain   : zone name (e.g. estabilis-cortex.com) for label/log use
  data = {
    api-token = var.cloudflare_api_token
    zone-id   = var.cloudflare_zone_id
    domain    = var.domain
  }
}
