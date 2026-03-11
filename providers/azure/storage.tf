# ---------------------------------------------------------------------------
# Storage Account – Observability (Loki & Mimir)
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "observability" {
  name                     = "st${var.name_prefix}obs${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.platform.name
  location                 = azurerm_resource_group.platform.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  public_network_access_enabled = false

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.aks_nodes.id, azurerm_subnet.aks_pods.id]
  }

  tags = var.tags
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

resource "azurerm_storage_container" "mimir_alertmanager" {
  name                  = "mimir-alertmanager"
  storage_account_id    = azurerm_storage_account.observability.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "mimir_ruler" {
  name                  = "mimir-ruler"
  storage_account_id    = azurerm_storage_account.observability.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Backup containers — CloudNativePG and Velero
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "cnpg_backup" {
  name                  = "cnpg-backup"
  storage_account_id    = azurerm_storage_account.observability.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "velero_backup" {
  name                  = "velero-backup"
  storage_account_id    = azurerm_storage_account.observability.id
  container_access_type = "private"
}
