# ---------------------------------------------------------------------------
# Workload Identities – Managed Identities + Federated Credentials
# ---------------------------------------------------------------------------

locals {
  aks_oidc_issuer_url = azurerm_kubernetes_cluster.platform.oidc_issuer_url
}

# ========================== external-dns ==================================

resource "azurerm_user_assigned_identity" "external_dns" {
  name                = "mi-${var.name_prefix}-external-dns"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "external_dns" {
  name      = "fic-${var.name_prefix}-external-dns"
  parent_id = azurerm_user_assigned_identity.external_dns.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:external-dns:external-dns"
}

# DNS Zone — created here for the platform domain
resource "azurerm_dns_zone" "platform" {
  name                = var.domain
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_role_assignment" "external_dns_dns_contributor" {
  scope                = azurerm_dns_zone.platform.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
}

# ========================== external-secrets ==============================

resource "azurerm_user_assigned_identity" "external_secrets" {
  name                = "mi-${var.name_prefix}-external-secrets"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "external_secrets" {
  name      = "fic-${var.name_prefix}-external-secrets"
  parent_id = azurerm_user_assigned_identity.external_secrets.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:external-secrets:external-secrets"
}

resource "azurerm_role_assignment" "external_secrets_kv_reader" {
  scope                = azurerm_key_vault.platform.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
}

# ========================== loki ==========================================

resource "azurerm_user_assigned_identity" "loki" {
  name                = "mi-${var.name_prefix}-loki"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "loki" {
  name      = "fic-${var.name_prefix}-loki"
  parent_id = azurerm_user_assigned_identity.loki.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:grafana:loki"
}

resource "azurerm_role_assignment" "loki_storage_contributor" {
  scope                = azurerm_storage_account.observability.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.loki.principal_id
}

# ========================== mimir =========================================

resource "azurerm_user_assigned_identity" "mimir" {
  name                = "mi-${var.name_prefix}-mimir"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "mimir" {
  name      = "fic-${var.name_prefix}-mimir"
  parent_id = azurerm_user_assigned_identity.mimir.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:grafana:mimir"
}

resource "azurerm_role_assignment" "mimir_storage_contributor" {
  scope                = azurerm_storage_account.observability.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.mimir.principal_id
}
