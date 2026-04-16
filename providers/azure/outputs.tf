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

output "hub_api_server_url" {
  description = "API server URL of the platform AKS cluster. Used by workload Terraform modules to configure provider kubernetes.hub for WorkloadCluster registration."
  value       = azurerm_kubernetes_cluster.platform.kube_config[0].host
  sensitive   = true
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

output "tfstate_storage_account_name" {
  description = "Storage account name for Terraform state backend (use in backend.tf)"
  value       = azurerm_storage_account.tfstate.name
}

output "cnpg_backup_storage_account_name" {
  description = "Storage account name for CNPG PostgreSQL backups (WAL archiving + base backups). Injected into ArgoCD as global.cnpgStorageAccountName."
  value       = azurerm_storage_account.cnpg_backup.name
}

output "velero_backup_storage_account_name" {
  description = "Storage account name for Velero Kubernetes cluster backups. Injected into ArgoCD as global.veleroStorageAccountName."
  value       = azurerm_storage_account.velero_backup.name
}

output "dns_zone_name" {
  description = "Name of the DNS zone (effective_domain, may include env subdomain)."
  value       = azurerm_dns_zone.platform.name
}

output "dns_zone_name_servers" {
  description = "Name servers for the DNS zone — configure these at your domain registrar"
  value       = azurerm_dns_zone.platform.name_servers
}

output "cert_manager_client_id" {
  description = "Client ID of the cert-manager managed identity."
  value       = azurerm_user_assigned_identity.cert_manager.client_id
}

output "external_dns_client_id" {
  description = "Client ID of the external-dns managed identity."
  value       = azurerm_user_assigned_identity.external_dns.client_id
}

output "external_secrets_client_id" {
  description = "Client ID of the external-secrets managed identity."
  value       = azurerm_user_assigned_identity.external_secrets.client_id
}

output "loki_client_id" {
  description = "Client ID of the Loki managed identity."
  value       = azurerm_user_assigned_identity.loki.client_id
}

output "mimir_client_id" {
  description = "Client ID of the Mimir managed identity."
  value       = azurerm_user_assigned_identity.mimir.client_id
}

output "cnpg_client_id" {
  description = "Client ID of the CNPG managed identity."
  value       = azurerm_user_assigned_identity.cnpg.client_id
}

output "velero_client_id" {
  description = "Client ID of the Velero managed identity."
  value       = azurerm_user_assigned_identity.velero.client_id
}

# --- ACR ---

output "acr_login_server" {
  description = "ACR login server URL (empty if disabled)."
  value       = var.acr_enabled ? azurerm_container_registry.platform[0].login_server : ""
}

output "acr_name" {
  description = "ACR name (empty if disabled)."
  value       = var.acr_enabled ? azurerm_container_registry.platform[0].name : ""
}

output "acr_ci_client_id" {
  description = "Client ID of the CI/CD managed identity for ACR push (empty if disabled)."
  value       = var.acr_enabled && var.acr_ci_identity_enabled ? azurerm_user_assigned_identity.acr_ci[0].client_id : ""
}

# --- Network ---

output "nat_gateway_public_ip" {
  description = "Static outbound IP address (NAT Gateway). Use this for external allowlists."
  value       = var.nat_gateway_enabled ? azurerm_public_ip.nat_gateway[0].ip_address : null
}

# --- Shared Hub Key Vault ---

output "shared_resource_group_name" {
  description = "Name of the shared RG that persists across platform teardowns. Used by workload clusters to locate the hub Key Vault."
  value       = var.shared_hub_kv_enabled ? azurerm_resource_group.shared[0].name : null
}

output "hub_key_vault_name" {
  description = "Name of the Key Vault containing hub connection values for workload clusters."
  value       = var.shared_hub_kv_enabled ? azurerm_key_vault.hub[0].name : null
}

# --- App exposures (ADR 0014) — JSON-encoded for CLI consumption ---

output "grafana_exposures_json" {
  description = "Grafana exposures serialized as JSON. Consumed by the estabilis CLI to set global.grafanaExposures helm parameter on platform-root."
  value       = jsonencode({ for k, v in var.grafana_exposures : k => v if v.enabled })
}

output "loki_exposures_json" {
  description = "Loki exposures serialized as JSON."
  value       = jsonencode({ for k, v in var.loki_exposures : k => v if v.enabled })
}
