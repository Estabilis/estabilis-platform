# ---------------------------------------------------------------------------
# Log Analytics Workspace + Diagnostic Settings
# Toggle via: diagnostics_enabled = false
# External LAW: set external_log_analytics_workspace_id to send logs to both
# ---------------------------------------------------------------------------

locals {
  external_law_enabled = var.external_log_analytics_workspace_id != ""
}

resource "azurerm_log_analytics_workspace" "platform" {
  count               = var.diagnostics_enabled ? 1 : 0
  name                = "law-${local.base_name}-platform"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# AKS
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-aks"
  target_resource_id         = azurerm_kubernetes_cluster.platform.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log { category = "kube-audit-admin" }
  enabled_log { category = "kube-controller-manager" }
  enabled_log { category = "kube-scheduler" }
  enabled_log { category = "cluster-autoscaler" }
  enabled_log { category = "guard" }
}

resource "azurerm_monitor_diagnostic_setting" "aks_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-aks-external"
  target_resource_id         = azurerm_kubernetes_cluster.platform.id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  enabled_log { category = "kube-audit-admin" }
  enabled_log { category = "kube-controller-manager" }
  enabled_log { category = "kube-scheduler" }
  enabled_log { category = "cluster-autoscaler" }
  enabled_log { category = "guard" }
}

# ---------------------------------------------------------------------------
# Key Vault — Platform
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-kv"
  target_resource_id         = azurerm_key_vault.platform.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log { category = "AuditEvent" }
  enabled_log { category = "AzurePolicyEvaluationDetails" }
  enabled_metric { category = "AllMetrics" }
}

resource "azurerm_monitor_diagnostic_setting" "keyvault_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-kv-external"
  target_resource_id         = azurerm_key_vault.platform.id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  enabled_log { category = "AuditEvent" }
  enabled_log { category = "AzurePolicyEvaluationDetails" }
  enabled_metric { category = "AllMetrics" }
}

# ---------------------------------------------------------------------------
# Key Vault — Hub/Shared
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "keyvault_hub" {
  count                      = var.diagnostics_enabled && var.shared_hub_kv_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-hub-kv"
  target_resource_id         = azurerm_key_vault.hub[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log { category = "AuditEvent" }
  enabled_log { category = "AzurePolicyEvaluationDetails" }
  enabled_metric { category = "AllMetrics" }
}

resource "azurerm_monitor_diagnostic_setting" "keyvault_hub_external" {
  count                      = local.external_law_enabled && var.shared_hub_kv_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-hub-kv-external"
  target_resource_id         = azurerm_key_vault.hub[0].id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  enabled_log { category = "AuditEvent" }
  enabled_log { category = "AzurePolicyEvaluationDetails" }
  enabled_metric { category = "AllMetrics" }
}

# ---------------------------------------------------------------------------
# Storage Account — TFState (blob service)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_tfstate" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-tfstate-blob"
  target_resource_id         = "${azurerm_storage_account.tfstate.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}

resource "azurerm_monitor_diagnostic_setting" "sa_tfstate_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-tfstate-blob-external"
  target_resource_id         = "${azurerm_storage_account.tfstate.id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}

# ---------------------------------------------------------------------------
# Storage Account — Observability (blob service)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_observability" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-obs-blob"
  target_resource_id         = "${azurerm_storage_account.observability.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}

resource "azurerm_monitor_diagnostic_setting" "sa_observability_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-obs-blob-external"
  target_resource_id         = "${azurerm_storage_account.observability.id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}

# ---------------------------------------------------------------------------
# Storage Account — CNPG Backup (blob service)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_cnpg" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-cnpg-blob"
  target_resource_id         = "${azurerm_storage_account.cnpg_backup.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}

resource "azurerm_monitor_diagnostic_setting" "sa_cnpg_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-cnpg-blob-external"
  target_resource_id         = "${azurerm_storage_account.cnpg_backup.id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}

# ---------------------------------------------------------------------------
# Storage Account — Velero Backup (blob service)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_velero" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-velero-blob"
  target_resource_id         = "${azurerm_storage_account.velero_backup.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}

resource "azurerm_monitor_diagnostic_setting" "sa_velero_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-velero-blob-external"
  target_resource_id         = "${azurerm_storage_account.velero_backup.id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}

# ---------------------------------------------------------------------------
# Storage Account — Cost Exports (blob service)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_cost_exports" {
  count                      = var.diagnostics_enabled && var.cost_export_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-costs-blob"
  target_resource_id         = "${azurerm_storage_account.cost_exports[0].id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}

resource "azurerm_monitor_diagnostic_setting" "sa_cost_exports_external" {
  count                      = local.external_law_enabled && var.cost_export_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-costs-blob-external"
  target_resource_id         = "${azurerm_storage_account.cost_exports[0].id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}

# ---------------------------------------------------------------------------
# ACR (Azure Container Registry)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "acr" {
  count                      = var.diagnostics_enabled && var.acr_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-acr"
  target_resource_id         = azurerm_container_registry.platform[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log { category = "ContainerRegistryRepositoryEvents" }
  enabled_log { category = "ContainerRegistryLoginEvents" }
}

resource "azurerm_monitor_diagnostic_setting" "acr_external" {
  count                      = local.external_law_enabled && var.acr_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-acr-external"
  target_resource_id         = azurerm_container_registry.platform[0].id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  enabled_log { category = "ContainerRegistryRepositoryEvents" }
  enabled_log { category = "ContainerRegistryLoginEvents" }
}
