# ---------------------------------------------------------------------------
# Network Security Group — defense in depth for AKS node subnet
# Toggle via: nsg_enabled = false
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "aks_nodes" {
  count               = var.nsg_enabled ? 1 : 0
  name                = "nsg-${local.base_name}"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "aks_nodes" {
  count                     = var.nsg_enabled ? 1 : 0
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks_nodes[0].id
}

# ---------------------------------------------------------------------------
# Ingress rules — HTTP(S) from authorized networks
#
# When the subnet carries a custom NSG (rather than an AKS-managed one), the
# AKS cloud provider does NOT auto-inject rules for Services of type
# LoadBalancer: those rules are only created in NSGs living inside the
# MC_<rg>_<cluster>_<region> shadow RG managed by AKS. Without these explicit
# rules, public traffic to the Traefik LB's frontend IP is dropped by the
# default DenyAllInBound (priority 65500), even though the LB's frontend IP
# and the backend pool are correctly wired — the drop happens between the
# LB DNAT and the VMSS NIC.
#
# source_address_prefixes reuses var.authorized_ip_ranges (also used as the
# AKS API server allowlist). Pass ["0.0.0.0/0"] for fully public endpoints.
# ---------------------------------------------------------------------------

locals {
  # Public = 0.0.0.0/0 when no allowlist is provided (operator owns the risk).
  # source_address_prefix (singular, string) takes "*" as all; source_address_prefixes
  # (plural, list) takes CIDRs. Use one or the other, not both.
  ingress_source_prefixes = length(var.ingress_allowed_ip_ranges) > 0 ? var.ingress_allowed_ip_ranges : null
  ingress_source_prefix   = length(var.ingress_allowed_ip_ranges) > 0 ? null : "*"
}

resource "azurerm_network_security_rule" "allow_https_ingress" {
  count                       = var.nsg_enabled && var.traefik_enabled ? 1 : 0
  name                        = "AllowHTTPSIngress"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = local.ingress_source_prefix
  source_address_prefixes     = local.ingress_source_prefixes
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.platform.name
  network_security_group_name = azurerm_network_security_group.aks_nodes[0].name
}

resource "azurerm_network_security_rule" "allow_http_ingress" {
  count                       = var.nsg_enabled && var.traefik_enabled ? 1 : 0
  name                        = "AllowHTTPIngress"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = local.ingress_source_prefix
  source_address_prefixes     = local.ingress_source_prefixes
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.platform.name
  network_security_group_name = azurerm_network_security_group.aks_nodes[0].name
}
