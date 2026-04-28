output "secret_name" {
  description = "Name of the Kubernetes Secret created by the module."
  value       = kubernetes_secret_v1.cloudflare_credentials.metadata[0].name
}

output "namespace" {
  description = "Namespace where the Secret was created."
  value       = kubernetes_secret_v1.cloudflare_credentials.metadata[0].namespace
}

output "zone_id" {
  description = "Cloudflare Zone ID — passed through for caller convenience (no transformation)."
  value       = var.cloudflare_zone_id
}

output "domain" {
  description = "Zone domain — passed through."
  value       = var.domain
}
