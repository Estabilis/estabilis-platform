# ---------------------------------------------------------------------------
# Resource Locks — prevent accidental deletion of critical storage accounts
# Toggle via: storage_protect_critical = true
# Must be removed (set to false) before teardown/destroy.
# ---------------------------------------------------------------------------

resource "azurerm_management_lock" "tfstate" {
  count      = var.storage_protect_critical ? 1 : 0
  name       = "lock-${local.base_name}-tfstate"
  scope      = azurerm_storage_account.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Protects Terraform state. Remove via storage_protect_critical=false before destroy."
}

resource "azurerm_management_lock" "cnpg_backup" {
  count      = var.storage_protect_critical ? 1 : 0
  name       = "lock-${local.base_name}-cnpg-backup"
  scope      = azurerm_storage_account.cnpg_backup.id
  lock_level = "CanNotDelete"
  notes      = "Protects PostgreSQL backups. Remove via storage_protect_critical=false before destroy."
}

resource "azurerm_management_lock" "velero_backup" {
  count      = var.storage_protect_critical ? 1 : 0
  name       = "lock-${local.base_name}-velero-backup"
  scope      = azurerm_storage_account.velero_backup.id
  lock_level = "CanNotDelete"
  notes      = "Protects Velero cluster backups. Remove via storage_protect_critical=false before destroy."
}
