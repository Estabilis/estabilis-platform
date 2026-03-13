# ---------------------------------------------------------------------------
# Workload Identities – Managed Identities + Federated Credentials
# ---------------------------------------------------------------------------

locals {
  aks_oidc_issuer_url = azurerm_kubernetes_cluster.platform.oidc_issuer_url
}

# ========================== external-dns ==================================

resource "azurerm_user_assigned_identity" "external_dns" {
  name                = "mi-${var.name_prefix}-external-dns"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "external_dns" {
  name      = "fic-${var.name_prefix}-external-dns"
  parent_id = azurerm_user_assigned_identity.external_dns.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:external-dns:external-dns"
}

# DNS Zone — created here for the platform domain
resource "azurerm_dns_zone" "platform" {
  name                = var.domain
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_role_assignment" "external_dns_dns_contributor" {
  scope                = azurerm_dns_zone.platform.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
}

# ========================== external-secrets ==============================

resource "azurerm_user_assigned_identity" "external_secrets" {
  name                = "mi-${var.name_prefix}-external-secrets"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "external_secrets" {
  name      = "fic-${var.name_prefix}-external-secrets"
  parent_id = azurerm_user_assigned_identity.external_secrets.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:external-secrets:external-secrets"
}

resource "azurerm_role_assignment" "external_secrets_kv_reader" {
  scope                = azurerm_key_vault.platform.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
}

# ========================== loki ==========================================

resource "azurerm_user_assigned_identity" "loki" {
  name                = "mi-${var.name_prefix}-loki"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "loki" {
  name      = "fic-${var.name_prefix}-loki"
  parent_id = azurerm_user_assigned_identity.loki.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:grafana:grafana-loki"
}

resource "azurerm_role_assignment" "loki_storage_contributor" {
  scope                = azurerm_storage_account.observability.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.loki.principal_id
}

# ========================== mimir =========================================

resource "azurerm_user_assigned_identity" "mimir" {
  name                = "mi-${var.name_prefix}-mimir"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "mimir" {
  name      = "fic-${var.name_prefix}-mimir"
  parent_id = azurerm_user_assigned_identity.mimir.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:grafana:grafana-mimir"
}

resource "azurerm_role_assignment" "mimir_storage_contributor" {
  scope                = azurerm_storage_account.observability.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.mimir.principal_id
}

# ========================== cloudnativepg ==================================

resource "azurerm_user_assigned_identity" "cnpg" {
  name                = "mi-${var.name_prefix}-cnpg"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "cnpg" {
  name      = "fic-${var.name_prefix}-cnpg"
  parent_id = azurerm_user_assigned_identity.cnpg.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:cnpg-system:platform-postgres"
}

resource "azurerm_role_assignment" "cnpg_storage_contributor" {
  scope                = azurerm_storage_account.observability.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.cnpg.principal_id
}

# ========================== cert-manager ==================================

resource "azurerm_user_assigned_identity" "cert_manager" {
  name                = "mi-${var.name_prefix}-cert-manager"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  name      = "fic-${var.name_prefix}-cert-manager"
  parent_id = azurerm_user_assigned_identity.cert_manager.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:cert-manager:cert-manager"
}

resource "azurerm_role_assignment" "cert_manager_dns_contributor" {
  scope                = azurerm_dns_zone.platform.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager.principal_id
}

# ========================== velero ========================================

resource "azurerm_user_assigned_identity" "velero" {
  name                = "mi-${var.name_prefix}-velero"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "velero" {
  name      = "fic-${var.name_prefix}-velero"
  parent_id = azurerm_user_assigned_identity.velero.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = local.aks_oidc_issuer_url
  subject   = "system:serviceaccount:velero:velero-server"
}

resource "azurerm_role_assignment" "velero_storage_contributor" {
  scope                = azurerm_storage_account.observability.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}

resource "azurerm_role_assignment" "velero_rg_reader" {
  scope                = azurerm_resource_group.platform.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}

# ========================== opencost ========================================
# OpenCost requires a Service Principal (not Workload Identity) because it
# uses the legacy Azure ADAL SDK which does not support federated credentials.

data "azurerm_subscription" "current" {
  subscription_id = var.subscription_id
}

locals {
  # Map Azure quotaId prefix to RateCard offer ID
  azure_offer_id_map = {
    "PayAsYouGo"          = "MS-AZR-0003P"
    "EnterpriseAgreement" = "MS-AZR-0017P"
    "MSDNDev"             = "MS-AZR-0062P"
    "MSDN"                = "MS-AZR-0063P"
    "FreeTrial"           = "MS-AZR-0044P"
    "BizSpark"            = "MS-AZR-0064P"
    "Sponsorship"         = "MS-AZR-0036P"
    "CSP"                 = "MS-AZR-0145P"
    "Internal"            = "MS-AZR-0015P"
  }

  # Extract prefix before underscore (e.g., "PayAsYouGo_2014-09-01" -> "PayAsYouGo")
  quota_id_prefix = split("_", data.azurerm_subscription.current.quota_id)[0]

  # Resolve offer ID from quota or fall back to Pay-As-You-Go
  azure_offer_id = lookup(local.azure_offer_id_map, local.quota_id_prefix, "MS-AZR-0003P")
}

resource "azuread_application" "opencost" {
  display_name = "sp-${var.name_prefix}-opencost"
}

resource "azuread_service_principal" "opencost" {
  client_id = azuread_application.opencost.client_id
}

resource "azuread_service_principal_password" "opencost" {
  service_principal_id = azuread_service_principal.opencost.id
  end_date             = timeadd(plantimestamp(), "8760h") # 1 year
}

resource "azurerm_role_definition" "opencost" {
  name        = "OpenCost Reader - ${var.name_prefix}"
  scope       = "/subscriptions/${var.subscription_id}"
  description = "Minimal read-only role for OpenCost Azure RateCard pricing integration"

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/vmSizes/read",
      "Microsoft.Resources/subscriptions/locations/read",
      "Microsoft.Resources/providers/read",
      "Microsoft.ContainerService/containerServices/read",
      "Microsoft.Commerce/RateCard/read",
    ]
    not_actions = []
  }

  assignable_scopes = ["/subscriptions/${var.subscription_id}"]
}

resource "azurerm_role_assignment" "opencost_custom_reader" {
  scope              = "/subscriptions/${var.subscription_id}"
  role_definition_id = azurerm_role_definition.opencost.role_definition_resource_id
  principal_id       = azuread_service_principal.opencost.object_id
}
