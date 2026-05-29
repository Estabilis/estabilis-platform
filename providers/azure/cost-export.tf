# ---------------------------------------------------------------------------
# Cost Management Export – Azure billing data for OpenCost Cloud Costs
# Toggle via: cost_export_enabled = false
# ---------------------------------------------------------------------------

# The Cost Management Export API requires Microsoft.CostManagementExports
# to be registered. This is handled by `estabilis register-providers`
# (run once per subscription) and verified by `estabilis apply`.

resource "azurerm_storage_account" "cost_exports" {
  count                           = var.cost_export_enabled ? 1 : 0
  name                            = "st${var.name_prefix}${local.env_code}cst${random_string.storage_suffix.result}"
  resource_group_name             = azurerm_resource_group.platform.name
  location                        = azurerm_resource_group.platform.location
  account_tier                    = "Standard"
  account_replication_type        = coalesce(var.storage_replication_type_cost_exports, var.storage_replication_type)
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true # required by OpenCost cloud-integration
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = local.cost_exports_pe_enabled ? false : true

  # Start open so Cost Management can access during export creation.
  # azurerm_storage_account_network_rules locks down after export exists.
  # ignore_changes prevents Terraform from reverting Deny back to Allow.
  # Skipped when PE-only — Cost Management uses trusted services bypass.
  dynamic "network_rules" {
    for_each = local.cost_exports_pe_enabled ? [] : [1]
    content {
      default_action = "Allow"
      bypass         = ["AzureServices"]
    }
  }

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

  lifecycle {
    ignore_changes = [network_rules]
  }

  tags = local.tags
}

# Firewall rules applied AFTER the cost export is created.
# Per Microsoft docs, Cost Management creates a system-assigned managed
# identity with StorageBlobDataContributor during export creation. This
# identity then works behind the firewall via trusted Azure services bypass.
# See: https://learn.microsoft.com/azure/cost-management-billing/costs/tutorial-improved-exports
# Skipped when PE-only — public_network_access_enabled=false handles isolation.
resource "azurerm_storage_account_network_rules" "cost_exports" {
  count              = var.cost_export_enabled && !local.cost_exports_pe_enabled ? 1 : 0
  storage_account_id = azurerm_storage_account.cost_exports[0].id
  default_action     = "Deny"
  bypass             = ["AzureServices"]

  depends_on = [azurerm_subscription_cost_management_export.daily]
}

resource "azurerm_storage_container" "cost_exports" {
  count                 = var.cost_export_enabled ? 1 : 0
  name                  = "cost-exports"
  storage_account_id    = azurerm_storage_account.cost_exports[0].id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Private Endpoint — blob access from AKS via VNet
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "cost_exports_blob" {
  count               = var.cost_export_enabled && local.cost_exports_pe_enabled ? 1 : 0
  name                = "pe-${local.base_name}-costs-blob"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  subnet_id           = azurerm_subnet.aks_nodes.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.base_name}-costs-blob"
    private_connection_resource_id = azurerm_storage_account.cost_exports[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.blob_pdz_id]
  }
}

# ---------------------------------------------------------------------------
# Terraform SP needs Owner on the storage account so that Cost Management
# can create a system-assigned managed identity with StorageBlobDataContributor.
# See: https://learn.microsoft.com/azure/cost-management-billing/costs/tutorial-improved-exports
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "terraform_cost_exports_owner" {
  count                = var.cost_export_enabled ? 1 : 0
  scope                = azurerm_storage_account.cost_exports[0].id
  role_definition_name = "Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Daily Cost Export — ActualCost, MonthToDate
# ---------------------------------------------------------------------------

resource "azurerm_subscription_cost_management_export" "daily" {
  count                        = var.cost_export_enabled ? 1 : 0
  name                         = "opencost-daily-${local.base_name}"
  subscription_id              = data.azurerm_subscription.current.id
  recurrence_type              = "Daily"
  recurrence_period_start_date = "${formatdate("YYYY-MM-DD", plantimestamp())}T00:00:00Z"
  # 87600h = 10 years. `timeadd` produces a zero-padded ISO-8601
  # timestamp; `formatdate` then reshapes it as RFC3339. Avoids the
  # "year + 10" string-arithmetic pattern which at `terraform validate`
  # time evaluates `plantimestamp()` to `0001-01-01T00:00:00Z` and
  # produces "11-01-01T00:00:00Z" (year `11`, rejected by provider).
  recurrence_period_end_date = "${formatdate("YYYY-MM-DD", timeadd(plantimestamp(), "87600h"))}T00:00:00Z"

  export_data_storage_location {
    container_id     = azurerm_storage_container.cost_exports[0].id
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
    azurerm_role_assignment.terraform_cost_exports_owner,
  ]
}
