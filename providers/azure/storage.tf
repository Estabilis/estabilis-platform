# ---------------------------------------------------------------------------
# Storage Account – Observability (Loki & Mimir)
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "observability" {
  name                            = "st${var.name_prefix}${local.env_code}obs${random_string.storage_suffix.result}"
  resource_group_name             = azurerm_resource_group.platform.name
  location                        = azurerm_resource_group.platform.location
  account_tier                    = "Standard"
  account_replication_type        = coalesce(var.storage_replication_type_observability, var.storage_replication_type)
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
      ip_rules                   = local.firewall_base_ips_bare
      virtual_network_subnet_ids = local.firewall_base_subnet_ids
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Private Endpoint — observability blob access via VNet
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "observability_blob" {
  count               = var.storage_private_endpoint_enabled ? 1 : 0
  name                = "pe-${local.base_name}-obs-blob"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  subnet_id           = azurerm_subnet.aks_nodes.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.base_name}-obs-blob"
    private_connection_resource_id = azurerm_storage_account.observability.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.blob_pdz_id]
  }
}

resource "azurerm_private_dns_zone" "blob" {
  count               = local.create_local_blob_pdz ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = local.create_local_blob_pdz ? 1 : 0
  name                  = "vnetlink-${local.base_name}-blob"
  resource_group_name   = azurerm_resource_group.platform.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.platform.id
}

# ---------------------------------------------------------------------------
# Blob Containers
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "loki" {
  name                  = "loki-chunks"
  storage_account_id    = azurerm_storage_account.observability.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "mimir" {
  name                  = "mimir"
  storage_account_id    = azurerm_storage_account.observability.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "mimir_blocks" {
  name                  = "mimir-blocks"
  storage_account_id    = azurerm_storage_account.observability.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Storage Account – CNPG Backup (PostgreSQL WAL archiving + scheduled backups)
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "cnpg_backup" {
  name                            = "st${var.name_prefix}${local.env_code}cnpg${random_string.storage_suffix.result}"
  resource_group_name             = azurerm_resource_group.platform.name
  location                        = azurerm_resource_group.platform.location
  account_tier                    = "Standard"
  account_replication_type        = coalesce(var.storage_replication_type_cnpg, var.storage_replication_type)
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
      ip_rules                   = local.firewall_cnpg_ips
      virtual_network_subnet_ids = local.firewall_base_subnet_ids
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "cnpg_backup" {
  name                  = "cnpg-backup"
  storage_account_id    = azurerm_storage_account.cnpg_backup.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "cnpg_blob" {
  count               = var.storage_private_endpoint_enabled ? 1 : 0
  name                = "pe-${local.base_name}-cnpg-blob"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  subnet_id           = azurerm_subnet.aks_nodes.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.base_name}-cnpg-blob"
    private_connection_resource_id = azurerm_storage_account.cnpg_backup.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.blob_pdz_id]
  }
}

# ---------------------------------------------------------------------------
# Storage Account – Velero Backup (Kubernetes disaster recovery)
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "velero_backup" {
  name                            = "st${var.name_prefix}${local.env_code}vlr${random_string.storage_suffix.result}"
  resource_group_name             = azurerm_resource_group.platform.name
  location                        = azurerm_resource_group.platform.location
  account_tier                    = "Standard"
  account_replication_type        = coalesce(var.storage_replication_type_velero, var.storage_replication_type)
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
      ip_rules                   = local.firewall_velero_ips
      virtual_network_subnet_ids = local.firewall_base_subnet_ids
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "velero_backup" {
  name                  = "velero-backup"
  storage_account_id    = azurerm_storage_account.velero_backup.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "velero_blob" {
  count               = var.storage_private_endpoint_enabled ? 1 : 0
  name                = "pe-${local.base_name}-velero-blob"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  subnet_id           = azurerm_subnet.aks_nodes.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.base_name}-velero-blob"
    private_connection_resource_id = azurerm_storage_account.velero_backup.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.blob_pdz_id]
  }
}
