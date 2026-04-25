# =============================================================================
# HashiCorp Vault — Azure infrastructure (auto-unseal + Raft snapshot backup)
# =============================================================================
# Toggle: var.vault_enabled. When false, NO resources are created — clean
# teardown via `terraform apply` with vault_enabled=false destroys
# everything provisioned here. NO purge protection on the dedicated KV
# (would block teardown); accept that an unseal key can be soft-deleted +
# purged inside the soft-delete retention window.
#
# Components provisioned (when enabled):
#   - Dedicated Key Vault `kv-vault-{cluster}-{suffix}` (separate from the
#     platform KV — scope isolation; no purge protection so the toggle is
#     truly destructive)
#   - RSA-2048 unseal key inside the dedicated KV
#   - Storage Account `stvault{cluster}{suffix}` + container `raft-snapshots`
#     for backup destination (deferred CronJob — bucket provisioned now so
#     future enablement needs no role assignment)
#   - User-assigned Managed Identity for the vault ServiceAccount + federated
#     credential (Workload Identity)
#   - Role assignments: Key Vault Crypto User on the dedicated KV +
#     Storage Blob Data Contributor on the storage account
#
# Outputs feed into the platform-infrastructure-sensitive Secret consumed
# by the Vault Application's helm.parameters (see
# bootstrap/platform-root/templates/vault.yaml).
#
# Bootstrap (auth methods, policies, KV mount) is intentionally NOT here —
# operator runs `vault operator init` manually after the chart deploys.
# =============================================================================

# --- Dedicated Key Vault for unseal key ---

resource "azurerm_key_vault" "vault_unseal" {
  count = var.vault_enabled ? 1 : 0

  name                       = "kv-vault-${var.name_prefix}-${local.env_code}-${random_string.storage_suffix.result}"
  location                   = azurerm_resource_group.platform.location
  resource_group_name        = azurerm_resource_group.platform.name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = var.vault_kv_soft_delete_days

  # NO purge_protection — toggle false must remove all resources cleanly.
  purge_protection_enabled = false

  dynamic "network_acls" {
    for_each = var.firewall_enabled ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = "AzureServices"
      ip_rules                   = local.firewall_keyvault_ips
      virtual_network_subnet_ids = concat(local.firewall_base_subnet_ids, [azurerm_subnet.aks_pods.id])
    }
  }

  tags = local.tags
}

# Operator running terraform needs Crypto Officer to create the key.
resource "azurerm_role_assignment" "terraform_vault_kv_officer" {
  count = var.vault_enabled ? 1 : 0

  scope                = azurerm_key_vault.vault_unseal[0].id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_key" "vault_unseal" {
  count = var.vault_enabled ? 1 : 0

  name         = "vault-unseal"
  key_vault_id = azurerm_key_vault.vault_unseal[0].id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  depends_on = [azurerm_role_assignment.terraform_vault_kv_officer]

  tags = local.tags
}

# --- Storage Account for Raft snapshot backups ---

resource "azurerm_storage_account" "vault_backup" {
  count = var.vault_enabled ? 1 : 0

  name                     = "st${var.name_prefix}${local.env_code}vlt${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.platform.name
  location                 = azurerm_resource_group.platform.location
  account_tier             = "Standard"
  account_replication_type = var.vault_storage_replication_type
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.vault_backup_retention_days
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "vault_backup" {
  count = var.vault_enabled ? 1 : 0

  name                  = "raft-snapshots"
  storage_account_id    = azurerm_storage_account.vault_backup[0].id
  container_access_type = "private"
}

# --- Managed Identity + Federated Credential (Workload Identity) ---

resource "azurerm_user_assigned_identity" "vault" {
  count = var.vault_enabled ? 1 : 0

  name                = "mi-${local.base_name}-vault"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "vault" {
  count = var.vault_enabled ? 1 : 0

  name                      = "fic-${local.base_name}-vault"
  user_assigned_identity_id = azurerm_user_assigned_identity.vault[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:vault:vault"
  resource_group_name       = azurerm_resource_group.platform.name
}

# --- Role assignments ---

resource "azurerm_role_assignment" "vault_kv_crypto_user" {
  count = var.vault_enabled ? 1 : 0

  scope                = azurerm_key_vault.vault_unseal[0].id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.vault[0].principal_id
}

resource "azurerm_role_assignment" "vault_storage_contributor" {
  count = var.vault_enabled ? 1 : 0

  scope                = azurerm_storage_account.vault_backup[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.vault[0].principal_id
}
