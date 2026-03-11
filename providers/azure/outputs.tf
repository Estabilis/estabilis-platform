# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the platform resource group."
  value       = azurerm_resource_group.platform.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.platform.name
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation."
  value       = azurerm_kubernetes_cluster.platform.oidc_issuer_url
}

output "keyvault_name" {
  description = "Name of the Key Vault."
  value       = azurerm_key_vault.platform.name
}

output "keyvault_uri" {
  description = "URI of the Key Vault."
  value       = azurerm_key_vault.platform.vault_uri
}

output "storage_account_name" {
  description = "Name of the observability storage account."
  value       = azurerm_storage_account.observability.name
}

output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed."
  value       = helm_release.argocd.namespace
}

output "tfstate_storage_account_name" {
  description = "Storage account name for Terraform state backend (use in backend.tf)"
  value       = azurerm_storage_account.tfstate.name
}

output "dns_zone_name_servers" {
  description = "Name servers for the DNS zone — configure these at your domain registrar"
  value       = azurerm_dns_zone.platform.name_servers
}

output "cert_manager_client_id" {
  description = "Client ID of the cert-manager managed identity."
  value       = azurerm_user_assigned_identity.cert_manager.client_id
}
