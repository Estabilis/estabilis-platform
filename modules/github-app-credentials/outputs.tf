output "secret_name" {
  description = "Name of the Kubernetes Secret created. Useful for downstream references (e.g. ExternalSecret target when migrating to cloud-store-driven reconciliation)."
  value       = kubernetes_secret_v1.repo_creds.metadata[0].name
}

output "namespace" {
  description = "Namespace where the Secret was created."
  value       = kubernetes_secret_v1.repo_creds.metadata[0].namespace
}

output "org_slug" {
  description = "Lowercased organization slug derived from github_org_url. Useful for composing related resource names in the caller."
  value       = local.org_slug
}
