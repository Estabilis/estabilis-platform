# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------

# v0.62.0 (workload parity): keyvault_enabled toggle. Default true preserves
# the historical always-on behavior. When false, NO platform KV is created
# and downstream secret-writing resources are skipped — the operator must
# supply the platform secrets (argocd_redis, grafana_admin/db, opencost
# integration, repo tokens) via another mechanism.
resource "azurerm_key_vault" "platform" {
  count                         = var.keyvault_enabled ? 1 : 0
  name                          = "kv-${var.name_prefix}-${local.env_code}-${random_string.storage_suffix.result}"
  location                      = azurerm_resource_group.platform.location
  resource_group_name           = azurerm_resource_group.platform.name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  soft_delete_retention_days    = var.keyvault_soft_delete_days
  purge_protection_enabled      = var.keyvault_purge_protection
  public_network_access_enabled = var.keyvault_private_endpoint_enabled ? false : true

  dynamic "network_acls" {
    for_each = !var.keyvault_private_endpoint_enabled && var.firewall_enabled ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = "AzureServices"
      ip_rules                   = local.firewall_keyvault_ips
      virtual_network_subnet_ids = concat(local.firewall_base_subnet_ids, [azurerm_subnet.aks_pods.id])
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Terraform needs KV access to create secrets during apply.
# The operator running terraform must have this role OR be added via
# access policy. We use the current client's object_id.
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "terraform_kv_officer" {
  count                = var.keyvault_enabled ? 1 : 0
  scope                = azurerm_key_vault.platform[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Platform secrets — generated once, stored in Key Vault
# These are consumed by ExternalSecrets → K8s Secrets → apps
# ---------------------------------------------------------------------------

resource "random_password" "argocd_redis" {
  length  = 32
  special = false
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "random_password" "grafana_db" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "argocd_redis_password" {
  count        = var.keyvault_enabled ? 1 : 0
  name         = "platform-argocd-redis-password"
  value        = random_password.argocd_redis.result
  key_vault_id = azurerm_key_vault.platform[0].id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "grafana_admin_password" {
  count        = var.keyvault_enabled ? 1 : 0
  name         = "platform-grafana-admin-password"
  value        = random_password.grafana_admin.result
  key_vault_id = azurerm_key_vault.platform[0].id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "grafana_db_password" {
  count        = var.keyvault_enabled ? 1 : 0
  name         = "platform-grafana-db-password"
  value        = random_password.grafana_db.result
  key_vault_id = azurerm_key_vault.platform[0].id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "opencost_cloud_integration" {
  count = var.keyvault_enabled && var.cost_export_enabled ? 1 : 0
  name  = "platform-opencost-cloud-integration"
  value = jsonencode({
    azure = {
      storage = [{
        subscriptionID = var.subscription_id
        account        = azurerm_storage_account.cost_exports[0].name
        container      = azurerm_storage_container.cost_exports[0].name
        path           = "cost-exports"
        cloud          = "public"
        authorizer = {
          accessKey      = azurerm_storage_account.cost_exports[0].primary_access_key
          account        = azurerm_storage_account.cost_exports[0].name
          authorizerType = "AzureAccessKey"
        }
      }]
    }
  })
  key_vault_id = azurerm_key_vault.platform[0].id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "opencost_service_key" {
  count = var.keyvault_enabled && var.cost_export_enabled ? 1 : 0
  name  = "platform-opencost-service-key"
  value = jsonencode({
    subscriptionId = var.subscription_id
    serviceKey = {
      appId    = azuread_application.opencost[0].client_id
      password = azuread_service_principal_password.opencost[0].value
      tenant   = var.tenant_id
    }
  })
  key_vault_id = azurerm_key_vault.platform[0].id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "config_repo_token" {
  count        = var.keyvault_enabled && var.config_repo_token != "" ? 1 : 0
  name         = "platform-config-repo-token"
  value        = var.config_repo_token
  key_vault_id = azurerm_key_vault.platform[0].id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "client_gitops_repo_token" {
  count        = var.keyvault_enabled && var.client_gitops_repo_token != "" ? 1 : 0
  name         = "platform-client-gitops-repo-token"
  value        = var.client_gitops_repo_token
  key_vault_id = azurerm_key_vault.platform[0].id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "openai_api_key" {
  count        = var.keyvault_enabled && var.openai_api_key != "" ? 1 : 0
  name         = "platform-openai-api-key"
  value        = var.openai_api_key
  key_vault_id = azurerm_key_vault.platform[0].id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

# ---------------------------------------------------------------------------
# Private Endpoint — Key Vault (platform) via VNet
# PDZ vaultcore is shared with the hub KV in shared.tf
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "vaultcore" {
  count               = var.keyvault_private_endpoint_enabled && local.create_local_vaultcore_pdz ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "vaultcore" {
  count                 = var.keyvault_private_endpoint_enabled && local.create_local_vaultcore_pdz ? 1 : 0
  name                  = "vnetlink-${local.base_name}-vaultcore"
  resource_group_name   = azurerm_resource_group.platform.name
  private_dns_zone_name = azurerm_private_dns_zone.vaultcore[0].name
  virtual_network_id    = azurerm_virtual_network.platform.id
}

resource "azurerm_private_endpoint" "keyvault_platform" {
  count               = var.keyvault_enabled && var.keyvault_private_endpoint_enabled ? 1 : 0
  name                = "pe-${local.base_name}-kv-vault"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  subnet_id           = azurerm_subnet.aks_nodes.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.base_name}-kv-vault"
    private_connection_resource_id = azurerm_key_vault.platform[0].id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.vaultcore_pdz_id]
  }
}
