# ---------------------------------------------------------------------------
# Log Analytics Workspace + Diagnostic Settings
# Toggle via: diagnostics_enabled = false
# External LAW: set external_log_analytics_workspace_id to fan-out to a
# central observability workspace ALONGSIDE the local LAW (additive, not
# replacement). Each *_external resource gates ONLY on external_law_enabled
# so it works even when diagnostics_enabled = false (external-only mode).
#
# v0.62.0 (workload parity): categories are operator-customizable via
# *_diagnostic_log_categories / *_diagnostic_metric_categories vars
# (see variables.tf). Defaults reproduce the previously-hardcoded category
# lists — zero diff in plan for existing consumers.
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

  dynamic "enabled_log" {
    for_each = toset(var.aks_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.aks_diagnostic_metric_categories_local)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-aks-external"
  target_resource_id         = azurerm_kubernetes_cluster.platform.id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(concat(var.aks_diagnostic_log_categories, var.aks_diagnostic_log_categories_external_extra))
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.aks_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Key Vault — Platform (toggle: keyvault_enabled)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  count                      = var.diagnostics_enabled && var.keyvault_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-kv"
  target_resource_id         = azurerm_key_vault.platform[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  dynamic "enabled_log" {
    for_each = toset(var.keyvault_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.keyvault_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "keyvault_external" {
  count                      = local.external_law_enabled && var.keyvault_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-kv-external"
  target_resource_id         = azurerm_key_vault.platform[0].id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.keyvault_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.keyvault_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Key Vault — Hub/Shared
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "keyvault_hub" {
  count                      = var.diagnostics_enabled && var.shared_hub_kv_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-hub-kv"
  target_resource_id         = azurerm_key_vault.hub[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  dynamic "enabled_log" {
    for_each = toset(var.keyvault_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.keyvault_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "keyvault_hub_external" {
  count                      = local.external_law_enabled && var.shared_hub_kv_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-hub-kv-external"
  target_resource_id         = azurerm_key_vault.hub[0].id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.keyvault_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.keyvault_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Storage Account — TFState (blob service)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_tfstate" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-tfstate-blob"
  target_resource_id         = "${azurerm_storage_account.tfstate.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "sa_tfstate_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-tfstate-blob-external"
  target_resource_id         = "${azurerm_storage_account.tfstate.id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Storage Account — Observability (blob service)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_observability" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-obs-blob"
  target_resource_id         = "${azurerm_storage_account.observability.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "sa_observability_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-obs-blob-external"
  target_resource_id         = "${azurerm_storage_account.observability.id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Storage Account — CNPG Backup (blob service)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_cnpg" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-cnpg-blob"
  target_resource_id         = "${azurerm_storage_account.cnpg_backup.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "sa_cnpg_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-cnpg-blob-external"
  target_resource_id         = "${azurerm_storage_account.cnpg_backup.id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Storage Account — Velero Backup (toggle: velero_enabled)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_velero" {
  count                      = var.diagnostics_enabled && var.velero_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-velero-blob"
  target_resource_id         = "${azurerm_storage_account.velero_backup[0].id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "sa_velero_external" {
  count                      = local.external_law_enabled && var.velero_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-velero-blob-external"
  target_resource_id         = "${azurerm_storage_account.velero_backup[0].id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Storage Account — Cost Exports (toggle: cost_export_enabled)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_cost_exports" {
  count                      = var.diagnostics_enabled && var.cost_export_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-costs-blob"
  target_resource_id         = "${azurerm_storage_account.cost_exports[0].id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "sa_cost_exports_external" {
  count                      = local.external_law_enabled && var.cost_export_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-costs-blob-external"
  target_resource_id         = "${azurerm_storage_account.cost_exports[0].id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# ACR (Azure Container Registry)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "acr" {
  count                      = var.diagnostics_enabled && var.acr_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-acr"
  target_resource_id         = azurerm_container_registry.platform[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  dynamic "enabled_log" {
    for_each = toset(var.acr_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.acr_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "acr_external" {
  count                      = local.external_law_enabled && var.acr_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-acr-external"
  target_resource_id         = azurerm_container_registry.platform[0].id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.acr_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.acr_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}
