# ---------------------------------------------------------------------------
# Terraform State Backend — Bootstrap resources
# Created first with local state, then state is migrated here.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${local.base_name}-tfstate"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                            = "st${var.name_prefix}${local.env_code}tfst${random_string.storage_suffix.result}"
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = coalesce(var.storage_replication_type_tfstate, var.storage_replication_type)
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = var.storage_private_endpoint_enabled ? false : true

  dynamic "blob_properties" {
    for_each = var.storage_soft_delete_enabled ? [1] : []
    content {
      delete_retention_policy {
        days = var.storage_soft_delete_retention_days
      }
      container_delete_retention_policy {
        days = var.storage_soft_delete_retention_days
      }
    }
  }

  dynamic "network_rules" {
    for_each = !var.storage_private_endpoint_enabled && var.firewall_enabled ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = ["AzureServices"]
      ip_rules                   = local.firewall_tfstate_ips
      virtual_network_subnet_ids = local.firewall_base_subnet_ids
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# RBAC — grant the deployer (current identity) access to the tfstate blob
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "tfstate_deployer" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Private Endpoint — tfstate blob access via VNet
# Shares the PDZ blob declared in storage.tf
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "tfstate_blob" {
  count               = var.storage_private_endpoint_enabled ? 1 : 0
  name                = "pe-${local.base_name}-tfstate-blob"
  location            = azurerm_resource_group.tfstate.location
  resource_group_name = azurerm_resource_group.tfstate.name
  subnet_id           = azurerm_subnet.aks_nodes.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.base_name}-tfstate-blob"
    private_connection_resource_id = azurerm_storage_account.tfstate.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
