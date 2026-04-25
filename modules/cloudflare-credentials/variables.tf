# ---------------------------------------------------------------------------
# cloudflare-credentials module — inputs
#
# Cloud-agnostic module that creates the Kubernetes Secret consumed by
# external-dns and cert-manager when `dns_provider = "cloudflare"`.
#
# The module touches ONLY the Kubernetes cluster — no cloud-specific
# resources. Each provider (providers/aws/, providers/azure/, ...) is
# expected to additionally mirror the API token into its own cloud
# secret store for rotation / audit / recovery (see the caller in
# providers/aws/cloudflare.tf as reference, mirroring the github-app-
# credentials pattern).
# ---------------------------------------------------------------------------

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID — 32-char hex string from the Cloudflare Dashboard 'API' tab on the zone overview page. The token's permissions must include the zone."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_zone_id))
    error_message = "cloudflare_zone_id must be a 32-character lowercase hex Cloudflare Zone ID."
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token (NOT API key). Create with permissions Zone:DNS:Edit + Zone:Zone:Read scoped to the target zone. Sensitive."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.cloudflare_api_token) >= 20
    error_message = "cloudflare_api_token must look like a Cloudflare API token (>= 20 chars)."
  }
}

variable "domain" {
  description = "Zone domain name (e.g. 'estabilis-cortex.com'). Stored in the Secret's `domain` data field — used by chart consumers that emit log/metric labels and as a sanity-check against the zone-id."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.domain))
    error_message = "domain must be a lowercase DNS-style string."
  }
}

variable "namespace" {
  description = "Kubernetes namespace where the Secret is created. Defaults to 'external-dns' — the chart that today uses CF_API_TOKEN as an env var. cert-manager and other consumers can read across namespaces via a ClusterSecretStore wrapper if needed."
  type        = string
  default     = "external-dns"
}

variable "secret_name" {
  description = "Name of the Kubernetes Secret. When empty, defaults to 'cloudflare-credentials'."
  type        = string
  default     = ""
}
