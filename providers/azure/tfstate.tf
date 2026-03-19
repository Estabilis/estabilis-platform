# ---------------------------------------------------------------------------
# Terraform State Backend — Bootstrap resources
# Created first with local state, then state is migrated here.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.name_prefix}-tfstate"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                            = "st${var.name_prefix}tfstate${random_string.storage_suffix.result}"
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = var.storage_replication_type
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = var.storage_soft_delete_retention_days
    }
    container_delete_retention_policy {
      days = var.storage_soft_delete_retention_days
    }
  }
  tags = var.tags
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
