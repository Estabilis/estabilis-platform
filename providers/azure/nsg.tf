# ---------------------------------------------------------------------------
# Network Security Group — defense in depth for AKS node subnet
# Toggle via: nsg_enabled = false
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "aks_nodes" {
  count               = var.nsg_enabled ? 1 : 0
  name                = "nsg-${var.name_prefix}-aks-nodes"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "aks_nodes" {
  count                     = var.nsg_enabled ? 1 : 0
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks_nodes[0].id
}
