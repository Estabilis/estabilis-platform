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
  name                          = "kv${var.name_prefix}hub${local.env_code}${random_string.storage_suffix.result}"
  resource_group_name           = azurerm_resource_group.shared[0].name
  location                      = azurerm_resource_group.shared[0].location
  sku_name                      = "standard"
  tenant_id                     = var.tenant_id
  rbac_authorization_enabled    = true
  purge_protection_enabled      = var.keyvault_purge_protection
  soft_delete_retention_days    = var.keyvault_soft_delete_days
  public_network_access_enabled = var.keyvault_private_endpoint_enabled ? false : true

  dynamic "network_acls" {
    for_each = !var.keyvault_private_endpoint_enabled && var.firewall_enabled ? [1] : []
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

# Hub AKS resource name (e.g. aks-transfero-platform-stg-eastus2). Workload
# clusters read this to derive the hub observability endpoints — the ingress
# hosts are {app}.{hub-cluster-name}.{domain-or-internal-domain} (e.g.
# mimir.aks-transfero-platform-stg-eastus2.azure.estabilis-transfero.dev). This
# is the AKS RESOURCE name, NOT the deployment-id-style cluster-name published on
# the hub Cluster Secret — the DNS A records use the resource name.
resource "azurerm_key_vault_secret" "hub_cluster_name" {
  count        = var.shared_hub_kv_enabled ? 1 : 0
  name         = "hub-cluster-name"
  value        = azurerm_kubernetes_cluster.platform.name
  key_vault_id = azurerm_key_vault.hub[0].id

  depends_on = [azurerm_role_assignment.hub_kv_officer]
}

# hub-egress-ip is ONLY meaningful for allowlist-topology workload clusters
# (public API server). We never write an empty value: the secret is created
# only when a real egress IP exists — either the hub NAT Gateway public IP, or
# an explicit override for NVA/FortiGate egress. In the private/peered topology
# both are unset, the secret is absent, and workload clusters register with
# apiServerAccess.mode=private (they never read it).
locals {
  hub_egress_ip_effective = (
    var.hub_egress_ip_override != "" ? var.hub_egress_ip_override :
    (var.nat_gateway_enabled ? azurerm_public_ip.nat_gateway[0].ip_address : "")
  )
}

resource "azurerm_key_vault_secret" "hub_egress_ip" {
  count        = var.shared_hub_kv_enabled && local.hub_egress_ip_effective != "" ? 1 : 0
  name         = "hub-egress-ip"
  value        = local.hub_egress_ip_effective
  key_vault_id = azurerm_key_vault.hub[0].id

  depends_on = [azurerm_role_assignment.hub_kv_officer]
}

# NOTE: The hub-registrar-token secret is published at RUNTIME by the
# estabilis-workload-operator via Azure Workload Identity (its hubTokenSync
# handler), NOT by any CLI. It is delivered through the GitOps Bridge: the
# operator chart is synced as a platformAddon with `bridge: true` +
# `hubTokenSync.enabled: true`, and the operator's UAMI/FIC + Key Vault Secrets
# Officer role on this vault (workload-identity.tf) let it write the secret.
# See ADR 0010 (GitOps Bridge) and workload-identity.tf.

# ---------------------------------------------------------------------------
# Private Endpoint — Key Vault (hub) via VNet
# Shares the PDZ vaultcore declared in keyvault.tf
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "keyvault_hub" {
  count               = var.shared_hub_kv_enabled && var.keyvault_private_endpoint_enabled ? 1 : 0
  name                = "pe-${local.base_name}-hub-vault"
  location            = azurerm_resource_group.shared[0].location
  resource_group_name = azurerm_resource_group.shared[0].name
  subnet_id           = azurerm_subnet.aks_nodes.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.base_name}-hub-vault"
    private_connection_resource_id = azurerm_key_vault.hub[0].id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.vaultcore_pdz_id]
  }
}
