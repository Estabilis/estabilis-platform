# ---------------------------------------------------------------------------
# github-app-credentials module — inputs
#
# Cloud-agnostic module that creates the Kubernetes Secret ArgoCD reads for
# authentication against a GitHub organization via GitHub App installation
# tokens. The secret carries the credential-template label
# (argocd.argoproj.io/secret-type: repo-creds) with the org URL as `url`,
# so ArgoCD matches it as credentials for any repository under that org.
#
# The module touches ONLY the Kubernetes cluster — no cloud-specific
# resources. Each provider (providers/aws/, providers/azure/, ...) is
# expected to additionally mirror the private key into its own cloud
# secret store for rotation / audit / recovery (see the caller in
# providers/aws/github-app.tf as reference).
# ---------------------------------------------------------------------------

variable "github_app_id" {
  description = "GitHub App ID (numeric). Found at the top of the App's Developer Settings page after creation."
  type        = string

  validation {
    condition     = length(var.github_app_id) > 0
    error_message = "github_app_id is required."
  }
}

variable "github_app_installation_id" {
  description = "GitHub App Installation ID (numeric). Found in the URL of the installation page after installing the App on an organization: https://github.com/organizations/<org>/settings/installations/<ID>."
  type        = string

  validation {
    condition     = length(var.github_app_installation_id) > 0
    error_message = "github_app_installation_id is required."
  }
}

variable "github_app_private_key" {
  description = "PEM-encoded private key downloaded from the GitHub App 'Private keys' section. Must include the standard PEM header/footer markers. Sensitive."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("BEGIN.*PRIVATE KEY", var.github_app_private_key))
    error_message = "github_app_private_key must be a PEM-encoded key."
  }
}

variable "github_org_url" {
  description = "Organization URL used as the `url` field in the ArgoCD repo-creds Secret. ArgoCD matches repository URLs by prefix — any repo under this org inherits the credential. Example: 'https://github.com/Cortex-Innovation'."
  type        = string

  validation {
    condition     = can(regex("^https://github\\.com/[^/]+/?$", var.github_org_url))
    error_message = "github_org_url must be in the form https://github.com/<org> (no trailing path)."
  }
}

variable "namespace" {
  description = "Kubernetes namespace where the Secret is created. ArgoCD reads credential templates from its own namespace, so this typically matches the ArgoCD install namespace."
  type        = string
  default     = "argocd"
}

variable "secret_name" {
  description = "Name of the Kubernetes Secret. When empty, derived as 'github-app-<lowercased-org-slug>' from github_org_url."
  type        = string
  default     = ""
}
