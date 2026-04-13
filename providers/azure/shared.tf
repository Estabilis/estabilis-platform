# ---------------------------------------------------------------------------
# Shared Resource Group + Key Vault — hub connection values for workloads
# ---------------------------------------------------------------------------
# This file creates infrastructure that persists across platform teardowns.
# Workload clusters consume hub connection values from this Key Vault via
# Terraform data sources, eliminating manual tfvars copying.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "shared" {
  count    = var.shared_hub_kv_enabled ? 1 : 0
  name     = "rg-${var.name_prefix}-platform-hub-${var.location}"
  location = var.location
  tags     = local.tags

  lifecycle {
    prevent_destroy = false
  }
}

# ---------------------------------------------------------------------------
# Key Vault — stores hub connection values consumed by workload clusters
# ---------------------------------------------------------------------------

resource "azurerm_key_vault" "hub" {
  count = var.shared_hub_kv_enabled ? 1 : 0
  # Compact naming (no dashes between components) to stay within Azure's
  # 24-char Key Vault name limit. The dashed form "kv-{prefix}-hub-{env}-{suffix}"
  # exceeds 24 chars for most prefixes. Matches the storage account naming
  # convention used elsewhere in the codebase (st{prefix}{env}obs{suffix}).
  name                       = "kv${var.name_prefix}hub${local.env_code}${random_string.storage_suffix.result}"
  resource_group_name        = azurerm_resource_group.shared[0].name
  location                   = azurerm_resource_group.shared[0].location
  sku_name                   = "standard"
  tenant_id                  = var.tenant_id
  rbac_authorization_enabled = true
  purge_protection_enabled   = var.keyvault_purge_protection
  soft_delete_retention_days = var.keyvault_soft_delete_days

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

  lifecycle {
    prevent_destroy = false
  }
}

# ---------------------------------------------------------------------------
# RBAC — allow the Terraform operator to write secrets
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "hub_kv_officer" {
  count                = var.shared_hub_kv_enabled ? 1 : 0
  scope                = azurerm_key_vault.hub[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Secrets — hub connection values for workload clusters
# ---------------------------------------------------------------------------

resource "azurerm_key_vault_secret" "hub_api_server_url" {
  count        = var.shared_hub_kv_enabled ? 1 : 0
  name         = "hub-api-server-url"
  value        = azurerm_kubernetes_cluster.platform.kube_config[0].host
  key_vault_id = azurerm_key_vault.hub[0].id

  depends_on = [azurerm_role_assignment.hub_kv_officer]
}

resource "azurerm_key_vault_secret" "hub_ca_certificate" {
  count        = var.shared_hub_kv_enabled ? 1 : 0
  name         = "hub-ca-certificate"
  value        = azurerm_kubernetes_cluster.platform.kube_config[0].cluster_ca_certificate
  key_vault_id = azurerm_key_vault.hub[0].id

  depends_on = [azurerm_role_assignment.hub_kv_officer]
}

resource "azurerm_key_vault_secret" "hub_egress_ip" {
  count        = var.shared_hub_kv_enabled ? 1 : 0
  name         = "hub-egress-ip"
  value        = var.nat_gateway_enabled ? azurerm_public_ip.nat_gateway[0].ip_address : ""
  key_vault_id = azurerm_key_vault.hub[0].id

  depends_on = [azurerm_role_assignment.hub_kv_officer]
}

# NOTE: The 4th hub secret (hub-registrar-token) is written by the
# estabilis CLI during `estabilis upstart`, after the workload-operator
# chart is synced and the ServiceAccount token exists in Kubernetes.
# See: estabilis-platform-tools issue #69.
