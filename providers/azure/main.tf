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

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "platform" {
  name     = "rg-${local.base_name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Effective domain — computed from host_pattern + environment + domain
# ---------------------------------------------------------------------------
# subdomain: dev.acme.com (prod uses bare domain: acme.com)
# prefix/suffix: acme.com (environment is in the hostname, not the domain)

locals {
  is_prod_env      = contains(["prod", "prd", "production"], var.environment)
  effective_domain = var.host_pattern == "subdomain" && !local.is_prod_env ? "${var.environment}.${var.domain}" : var.domain

  # CAF naming — {type}-{prefix}-platform-{env}-{region}
  env_code = {
    dev  = "dev"
    uat  = "uat"
    hml  = "hml"
    stg  = "stg"
    prd  = "prd"
    prod = "prd"
  }[var.environment]

  base_name = "${var.name_prefix}-platform-${local.env_code}-${var.location}"

  # CAF tags — automatic + optional (empty values filtered out)
  caf_tags = {
    for k, v in {
      # Functional
      app        = coalesce(var.tag_app, var.name_prefix)
      env        = local.env_code
      region     = var.location
      tier       = var.tag_tier
      managed-by = "terraform"
      # Classification
      criticality     = var.tag_criticality
      confidentiality = var.tag_confidentiality
      sla             = var.tag_sla
      # Accounting
      costcenter = var.tag_costcenter
      department = var.tag_department
      budget     = var.tag_budget
      # Purpose
      businessprocess = var.tag_businessprocess
      businessimpact  = var.tag_businessimpact
      revenueimpact   = var.tag_revenueimpact
      # Ownership
      opsteam      = var.tag_opsteam
      businessunit = var.tag_businessunit
    } : k => v if v != ""
  }

  tags = merge(local.caf_tags, var.extra_tags)
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

  # Centralized storage firewall rules — auto-detected + global + per-resource
  nat_gateway_ip = var.nat_gateway_enabled ? "${azurerm_public_ip.nat_gateway[0].ip_address}/32" : ""

  storage_firewall_base_ips = distinct(concat(
    [local.operator_ip],
    var.nat_gateway_enabled ? [local.nat_gateway_ip] : [],
  ))

  # Storage accounts require IPs without /32 (max /30 or bare IP)
  storage_firewall_base_ips_bare = [for ip in local.storage_firewall_base_ips : replace(ip, "/32", "")]

  # Per-resource firewall IPs (base + extras)
  storage_firewall_tfstate_ips = distinct(concat(local.storage_firewall_base_ips_bare, [for ip in var.storage_tfstate_extra_allowed_ips : replace(ip, "/32", "")]))
  storage_firewall_cnpg_ips    = distinct(concat(local.storage_firewall_base_ips_bare, [for ip in var.storage_cnpg_extra_allowed_ips : replace(ip, "/32", "")]))
  storage_firewall_velero_ips  = distinct(concat(local.storage_firewall_base_ips_bare, [for ip in var.storage_velero_extra_allowed_ips : replace(ip, "/32", "")]))
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
