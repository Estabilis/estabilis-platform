# ---------------------------------------------------------------------------
# Route Table — required for AKS with outboundType userDefinedRouting
# NAT Gateway handles outbound automatically via subnet association.
# The route table must exist but no explicit default route is needed.
# Toggle follows nat_gateway_enabled.
# ---------------------------------------------------------------------------

resource "azurerm_route_table" "aks_nodes" {
  count               = var.nat_gateway_enabled ? 1 : 0
  name                = "rt-${var.name_prefix}-aks-nodes"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_subnet_route_table_association" "aks_nodes" {
  count          = var.nat_gateway_enabled ? 1 : 0
  subnet_id      = azurerm_subnet.aks_nodes.id
  route_table_id = azurerm_route_table.aks_nodes[0].id
}
