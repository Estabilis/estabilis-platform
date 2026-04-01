# ---------------------------------------------------------------------------
# Virtual Network
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "platform" {
  name                = "vnet-${local.base_name}"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  address_space       = [var.vnet_address_space]
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "aks_nodes" {
  name                 = "snet-${local.base_name}-nodes"
  resource_group_name  = azurerm_resource_group.platform.name
  virtual_network_name = azurerm_virtual_network.platform.name
  address_prefixes     = [var.subnet_nodes_prefix]
  service_endpoints    = ["Microsoft.KeyVault", "Microsoft.Storage"]
}

# ---------------------------------------------------------------------------
# RBAC — AKS identity needs Network Contributor on the node subnet to
# create/manage Load Balancers and associate them with the subnet.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = azurerm_subnet.aks_nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.platform.identity[0].principal_id
}

resource "azurerm_subnet" "aks_pods" {
  name                 = "snet-${local.base_name}-pods"
  resource_group_name  = azurerm_resource_group.platform.name
  virtual_network_name = azurerm_virtual_network.platform.name
  address_prefixes     = [var.subnet_pods_prefix]
  service_endpoints    = ["Microsoft.KeyVault", "Microsoft.Storage"]
}
