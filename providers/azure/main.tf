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

# ADR 0015 — Azure DevOps Service Connection automation for ACR push.
# Authenticates via az cli (no PAT required) when AZURE_CONFIG_DIR points to a
# session that has access to the target ADO organization. Provider block is
# always declared; resources are gated by var.azdo_push_automation_enabled
# so it is a no-op when the feature is off.
provider "azuredevops" {
  org_service_url = var.azdo_organization_url
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.platform.kube_admin_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.platform.kube_admin_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.platform.kube_admin_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.platform.kube_admin_config[0].cluster_ca_certificate)
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
# Host derivation — {app}.{cluster_name}.{domain}
# ---------------------------------------------------------------------------

locals {
  # Host derivation: {app}.{cluster_name}.{domain}
  # The cluster name carries environment + region, so no separate env prefix.
  # Explicit host values in exposure tfvars always win over auto-derivation.
  _app_host = {
    for app in ["grafana", "argocd", "loki", "mimir", "hubble", "vault"] : app =>
    "${app}.${azurerm_kubernetes_cluster.platform.name}.${var.domain}"
  }

  # Resolved exposures — applies the auto-derived host when the user left
  # it empty in tfvars. Explicit values always win. Downstream outputs
  # (platform-outputs.tf, outputs.tf) consume these, not var.*_exposures.
  grafana_exposures_resolved = {
    for k, v in var.grafana_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.grafana
    })
  }
  loki_exposures_resolved = {
    for k, v in var.loki_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.loki
    })
  }
  mimir_exposures_resolved = {
    for k, v in var.mimir_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.mimir
    })
  }
  argocd_exposures_resolved = {
    for k, v in var.argocd_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.argocd
    })
  }
  hubble_ui_exposures_resolved = {
    for k, v in var.hubble_ui_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.hubble
    })
  }
  vault_exposures_resolved = {
    for k, v in var.vault_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : local._app_host.vault
    })
  }

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
  nat_gateway_ip = var.nat_gateway_enabled ? "${azurerm_public_ip.nat_gateway[0].ip_address}/32" : null
  authorized_ips = distinct(concat(var.authorized_ip_ranges, [local.operator_ip]))

  # Centralized firewall rules — auto-detected + global + per-resource
  firewall_base_ips = distinct(concat(
    [local.operator_ip],
    var.nat_gateway_enabled ? [local.nat_gateway_ip] : [],
    var.firewall_allowed_ips,
  ))

  firewall_base_subnet_ids = distinct(concat(
    [azurerm_subnet.aks_nodes.id],
    var.firewall_allowed_subnet_ids,
  ))

  # Storage accounts require IPs without /32 (max /30 or bare IP)
  firewall_base_ips_bare = [for ip in local.firewall_base_ips : replace(ip, "/32", "")]

  # Per-resource firewall IPs (base + extras)
  firewall_keyvault_ips = distinct(concat(local.firewall_base_ips, var.keyvault_extra_allowed_ips))
  firewall_acr_ips      = distinct(concat(local.firewall_base_ips, var.acr_extra_allowed_ips))
  firewall_tfstate_ips  = distinct(concat(local.firewall_base_ips_bare, [for ip in var.storage_tfstate_extra_allowed_ips : replace(ip, "/32", "")]))
  firewall_cnpg_ips     = distinct(concat(local.firewall_base_ips_bare, [for ip in var.storage_cnpg_extra_allowed_ips : replace(ip, "/32", "")]))
  firewall_velero_ips   = distinct(concat(local.firewall_base_ips_bare, [for ip in var.storage_velero_extra_allowed_ips : replace(ip, "/32", "")]))
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
