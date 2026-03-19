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
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true # required by OpenCost cloud-integration
  allow_nested_items_to_be_public = false

  # Start open so Cost Management can access during export creation.
  # azurerm_storage_account_network_rules locks down after export exists.
  # ignore_changes prevents Terraform from reverting Deny back to Allow.
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 14
    }
    container_delete_retention_policy {
      days = 14
    }
  }

  lifecycle {
    ignore_changes = [network_rules]
  }

  tags = var.tags
}

# Firewall rules applied AFTER the cost export is created.
# Per Microsoft docs, Cost Management creates a system-assigned managed
# identity with StorageBlobDataContributor during export creation. This
# identity then works behind the firewall via trusted Azure services bypass.
# See: https://learn.microsoft.com/azure/cost-management-billing/costs/tutorial-improved-exports
resource "azurerm_storage_account_network_rules" "cost_exports" {
  storage_account_id = azurerm_storage_account.cost_exports.id
  default_action     = "Deny"
  bypass             = ["AzureServices"]

  depends_on = [azurerm_subscription_cost_management_export.daily]
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
# Terraform SP needs Owner on the storage account so that Cost Management
# can create a system-assigned managed identity with StorageBlobDataContributor.
# See: https://learn.microsoft.com/azure/cost-management-billing/costs/tutorial-improved-exports
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "terraform_cost_exports_owner" {
  scope                = azurerm_storage_account.cost_exports.id
  role_definition_name = "Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Daily Cost Export — ActualCost, MonthToDate
# ---------------------------------------------------------------------------

resource "azurerm_subscription_cost_management_export" "daily" {
  name                         = "opencost-daily-${var.name_prefix}"
  subscription_id              = data.azurerm_subscription.current.id
  recurrence_type              = "Daily"
  recurrence_period_start_date = "${formatdate("YYYY-MM-DD", plantimestamp())}T00:00:00Z"
  recurrence_period_end_date   = "${formatdate("YYYY", plantimestamp()) + 10}-${formatdate("MM-DD", plantimestamp())}T00:00:00Z"

  export_data_storage_location {
    container_id     = azurerm_storage_container.cost_exports.id
    root_folder_path = "/cost-exports"
  }

  export_data_options {
    type       = "ActualCost"
    time_frame = "MonthToDate"
  }

  lifecycle {
    ignore_changes = [recurrence_period_start_date, recurrence_period_end_date]
  }

  depends_on = [
    azurerm_resource_provider_registration.cost_management_exports,
    azurerm_role_assignment.terraform_cost_exports_owner,
  ]
}
