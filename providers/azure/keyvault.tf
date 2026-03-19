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
  purge_protection_enabled   = var.keyvault_purge_protection

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    ip_rules                   = var.authorized_ip_ranges
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

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "random_password" "grafana_db" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "grafana_admin_password" {
  name         = "platform-grafana-admin-password"
  value        = random_password.grafana_admin.result
  key_vault_id = azurerm_key_vault.platform.id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "grafana_db_password" {
  name         = "platform-grafana-db-password"
  value        = random_password.grafana_db.result
  key_vault_id = azurerm_key_vault.platform.id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "opencost_cloud_integration" {
  name = "platform-opencost-cloud-integration"
  value = jsonencode({
    azure = {
      storage = [{
        subscriptionID = var.subscription_id
        account        = azurerm_storage_account.cost_exports.name
        container      = azurerm_storage_container.cost_exports.name
        path           = "cost-exports"
        cloud          = "public"
        authorizer = {
          accessKey      = azurerm_storage_account.cost_exports.primary_access_key
          account        = azurerm_storage_account.cost_exports.name
          authorizerType = "AzureAccessKey"
        }
      }]
    }
  })
  key_vault_id = azurerm_key_vault.platform.id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "opencost_service_key" {
  name = "platform-opencost-service-key"
  value = jsonencode({
    subscriptionId = var.subscription_id
    serviceKey = {
      appId    = azuread_application.opencost.client_id
      password = azuread_service_principal_password.opencost.value
      tenant   = var.tenant_id
    }
  })
  key_vault_id = azurerm_key_vault.platform.id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "config_repo_token" {
  count        = var.config_repo_token != "" ? 1 : 0
  name         = "platform-config-repo-token"
  value        = var.config_repo_token
  key_vault_id = azurerm_key_vault.platform.id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}
