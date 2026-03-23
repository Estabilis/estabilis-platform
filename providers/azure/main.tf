# ---------------------------------------------------------------------------
# Provider configuration
# ---------------------------------------------------------------------------

provider "azurerm" {
  features {}

  resource_provider_registrations = "none"
  storage_use_azuread             = true
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.platform.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.platform.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.platform.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.platform.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.platform.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.platform.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.platform.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.platform.kube_config[0].cluster_ca_certificate)
}

provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.platform.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.platform.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.platform.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.platform.kube_config[0].cluster_ca_certificate)
  load_config_file       = false
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "platform" {
  name     = "rg-${var.name_prefix}-platform"
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Effective domain — computed from host_pattern + environment + domain
# ---------------------------------------------------------------------------
# subdomain: dev.acme.com (prod uses bare domain: acme.com)
# prefix/suffix: acme.com (environment is in the hostname, not the domain)

locals {
  is_prod_env      = contains(["prod", "prd", "production"], var.environment)
  effective_domain = var.host_pattern == "subdomain" && !local.is_prod_env ? "${var.environment}.${var.domain}" : var.domain
}

# ---------------------------------------------------------------------------
# Operator IP — auto-detected for AKS API + Key Vault firewall access
# ---------------------------------------------------------------------------

data "http" "operator_ip" {
  url = "https://api.ipify.org" # IPv4 only
}

locals {
  operator_ip    = "${chomp(data.http.operator_ip.response_body)}/32"
  authorized_ips = distinct(concat(var.authorized_ip_ranges, [local.operator_ip]))
}

# ---------------------------------------------------------------------------
# Random suffix for globally-unique storage account name
# ---------------------------------------------------------------------------

resource "random_string" "storage_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}
