output "namespace" {
  description = "Namespace the handoff was written into."
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "config_map_name" {
  description = "ConfigMap the platform reads its infrastructure from."
  value       = kubernetes_config_map_v1.platform_infrastructure.metadata[0].name
}
