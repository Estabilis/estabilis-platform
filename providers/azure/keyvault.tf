# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------

resource "azurerm_key_vault" "platform" {
  name                       = "kv-${var.name_prefix}-plat"
  location                   = azurerm_resource_group.platform.location
  resource_group_name        = azurerm_resource_group.platform.name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = true

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [azurerm_subnet.aks_nodes.id, azurerm_subnet.aks_pods.id]
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Terraform needs KV access to create secrets during apply.
# The operator running terraform must have this role OR be added via
# access policy. We use the current client's object_id.
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "terraform_kv_officer" {
  scope                = azurerm_key_vault.platform.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Platform secrets — generated once, stored in Key Vault
# These are consumed by ExternalSecrets → K8s Secrets → apps
# ---------------------------------------------------------------------------

resource "random_password" "grafana_db" {
  length  = 32
  special = false
}

resource "random_password" "argocd_db" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "grafana_db_password" {
  name         = "platform-grafana-db-password"
  value        = random_password.grafana_db.result
  key_vault_id = azurerm_key_vault.platform.id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "argocd_db_password" {
  name         = "platform-argocd-db-password"
  value        = random_password.argocd_db.result
  key_vault_id = azurerm_key_vault.platform.id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}
