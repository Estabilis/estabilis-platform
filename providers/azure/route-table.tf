# ---------------------------------------------------------------------------
# Route Table — required for AKS with outboundType userDefinedRouting
# NAT Gateway intercepts 0.0.0.0/0 before reaching internet.
# Toggle follows nat_gateway_enabled.
# ---------------------------------------------------------------------------

resource "azurerm_route_table" "aks_nodes" {
  count               = var.nat_gateway_enabled ? 1 : 0
  name                = "rt-${var.name_prefix}-aks-nodes"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_route" "default_nat" {
  count               = var.nat_gateway_enabled ? 1 : 0
  name                = "default-nat-gateway"
  resource_group_name = azurerm_resource_group.platform.name
  route_table_name    = azurerm_route_table.aks_nodes[0].name
  address_prefix      = "0.0.0.0/0"
  next_hop_type       = "Internet"
}

resource "azurerm_subnet_route_table_association" "aks_nodes" {
  count          = var.nat_gateway_enabled ? 1 : 0
  subnet_id      = azurerm_subnet.aks_nodes.id
  route_table_id = azurerm_route_table.aks_nodes[0].id
}
