# ---------------------------------------------------------------------------
# Log Analytics Workspace + AKS Diagnostic Settings
# Toggle via: diagnostics_enabled = false
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "platform" {
  count               = var.diagnostics_enabled ? 1 : 0
  name                = "law-${var.name_prefix}-platform"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${var.name_prefix}-aks"
  target_resource_id         = azurerm_kubernetes_cluster.platform.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  enabled_log {
    category = "guard"
  }

}
