# ---------------------------------------------------------------------------
# NAT Gateway — static outbound IP for AKS
# Toggle via: nat_gateway_enabled = false
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "nat_gateway" {
  count               = var.nat_gateway_enabled ? 1 : 0
  name                = "pip-${var.name_prefix}-natgw"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "platform" {
  count                   = var.nat_gateway_enabled ? 1 : 0
  name                    = "natgw-${var.name_prefix}-platform"
  location                = azurerm_resource_group.platform.location
  resource_group_name     = azurerm_resource_group.platform.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "platform" {
  count                = var.nat_gateway_enabled ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.platform[0].id
  public_ip_address_id = azurerm_public_ip.nat_gateway[0].id
}

resource "azurerm_subnet_nat_gateway_association" "aks_nodes" {
  count          = var.nat_gateway_enabled ? 1 : 0
  subnet_id      = azurerm_subnet.aks_nodes.id
  nat_gateway_id = azurerm_nat_gateway.platform[0].id
}
