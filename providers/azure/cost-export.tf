# ---------------------------------------------------------------------------
# Cost Management Export – Azure billing data for OpenCost Cloud Costs
# ---------------------------------------------------------------------------

# The Cost Management Export API requires this resource provider to be
# registered on the subscription before exports can be created.
resource "azurerm_resource_provider_registration" "cost_management_exports" {
  name = "Microsoft.CostManagementExports"
}

resource "azurerm_storage_account" "cost_exports" {
  name                            = "st${var.name_prefix}costs${random_string.storage_suffix.result}"
  resource_group_name             = azurerm_resource_group.platform.name
  location                        = azurerm_resource_group.platform.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true # required by OpenCost cloud-integration
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  tags = var.tags
}

resource "azurerm_storage_container" "cost_exports" {
  name                  = "cost-exports"
  storage_account_id    = azurerm_storage_account.cost_exports.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Private Endpoint — blob access from AKS via VNet
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "cost_exports_blob" {
  name                = "pe-${var.name_prefix}-costs-blob"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  subnet_id           = azurerm_subnet.aks_nodes.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name_prefix}-costs-blob"
    private_connection_resource_id = azurerm_storage_account.cost_exports.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

# ---------------------------------------------------------------------------
# Daily Cost Export — ActualCost, MonthToDate
# ---------------------------------------------------------------------------

resource "azurerm_subscription_cost_management_export" "daily" {
  name                         = "opencost-daily-${var.name_prefix}"
  subscription_id              = data.azurerm_subscription.current.id
  recurrence_type              = "Daily"
  recurrence_period_start_date = "2024-01-01T00:00:00Z"
  recurrence_period_end_date   = "2099-12-31T00:00:00Z"

  export_data_storage_location {
    container_id     = azurerm_storage_container.cost_exports.id
    root_folder_path = "/cost-exports"
  }

  export_data_options {
    type       = "ActualCost"
    time_frame = "MonthToDate"
  }

  depends_on = [azurerm_resource_provider_registration.cost_management_exports]
}
