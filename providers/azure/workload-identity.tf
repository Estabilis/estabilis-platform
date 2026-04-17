# ---------------------------------------------------------------------------
# Workload Identities – Managed Identities + Federated Credentials
# ---------------------------------------------------------------------------

locals {
  aks_oidc_issuer_url = azurerm_kubernetes_cluster.platform.oidc_issuer_url
}

# ========================== external-dns ==================================
# Azure DNS resources are only provisioned when dns_provider = "azure".
# When dns_provider = "cloudflare", external-dns authenticates to the
# Cloudflare API with a static token (no Workload Identity, no DNS zone,
# no role assignment) and the zone is managed outside Terraform.

resource "azurerm_user_assigned_identity" "external_dns" {
  count               = var.dns_provider == "azure" ? 1 : 0
  name                = "mi-${local.base_name}-external-dns"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "external_dns" {
  count                     = var.dns_provider == "azure" ? 1 : 0
  name                      = "fic-${local.base_name}-external-dns"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_dns[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:external-dns:external-dns"
}

# DNS Zone — uses domain (the zone root, e.g. estabilis.io)
resource "azurerm_dns_zone" "platform" {
  count               = var.dns_provider == "azure" ? 1 : 0
  name                = var.domain
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "external_dns_dns_contributor" {
  count                = var.dns_provider == "azure" ? 1 : 0
  scope                = azurerm_dns_zone.platform[0].id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns[0].principal_id
}

# ========================== external-secrets ==============================

resource "azurerm_user_assigned_identity" "external_secrets" {
  name                = "mi-${local.base_name}-external-secrets"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "external_secrets" {
  name                      = "fic-${local.base_name}-external-secrets"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_secrets.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:external-secrets:external-secrets"
}

resource "azurerm_role_assignment" "external_secrets_kv_reader" {
  scope                = azurerm_key_vault.platform.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
}

# ========================== loki ==========================================

resource "azurerm_user_assigned_identity" "loki" {
  name                = "mi-${local.base_name}-loki"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "loki" {
  name                      = "fic-${local.base_name}-loki"
  user_assigned_identity_id = azurerm_user_assigned_identity.loki.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:grafana:grafana-loki"
}

resource "azurerm_role_assignment" "loki_storage_contributor" {
  scope                = azurerm_storage_account.observability.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.loki.principal_id
}

# ========================== mimir =========================================

resource "azurerm_user_assigned_identity" "mimir" {
  name                = "mi-${local.base_name}-mimir"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "mimir" {
  name                      = "fic-${local.base_name}-mimir"
  user_assigned_identity_id = azurerm_user_assigned_identity.mimir.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:grafana:grafana-mimir"
}

resource "azurerm_role_assignment" "mimir_storage_contributor" {
  scope                = azurerm_storage_account.observability.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.mimir.principal_id
}

# ========================== cloudnativepg ==================================

resource "azurerm_user_assigned_identity" "cnpg" {
  name                = "mi-${local.base_name}-cnpg"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "cnpg" {
  name                      = "fic-${local.base_name}-cnpg"
  user_assigned_identity_id = azurerm_user_assigned_identity.cnpg.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:cnpg-system:platform-postgres"
}

resource "azurerm_role_assignment" "cnpg_storage_contributor" {
  scope                = azurerm_storage_container.cnpg_backup.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.cnpg.principal_id
}

# ========================== cert-manager ==================================

resource "azurerm_user_assigned_identity" "cert_manager" {
  name                = "mi-${local.base_name}-cert-manager"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  name                      = "fic-${local.base_name}-cert-manager"
  user_assigned_identity_id = azurerm_user_assigned_identity.cert_manager.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:cert-manager:cert-manager"
}

resource "azurerm_role_assignment" "cert_manager_dns_contributor" {
  count                = var.dns_provider == "azure" ? 1 : 0
  scope                = azurerm_dns_zone.platform[0].id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager.principal_id
}

# ========================== velero ========================================

resource "azurerm_user_assigned_identity" "velero" {
  name                = "mi-${local.base_name}-velero"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "velero" {
  name                      = "fic-${local.base_name}-velero"
  user_assigned_identity_id = azurerm_user_assigned_identity.velero.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:velero:velero-server"
}

resource "azurerm_role_assignment" "velero_storage_contributor" {
  scope                = azurerm_storage_account.velero_backup.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}

resource "azurerm_role_assignment" "velero_rg_reader" {
  scope                = azurerm_resource_group.platform.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}

resource "azurerm_role_assignment" "velero_disk_snapshot" {
  scope                = azurerm_resource_group.platform.id
  role_definition_name = "Disk Snapshot Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}

# ========================== opencost ========================================
# OpenCost requires a Service Principal (not Workload Identity) because it
# uses the legacy Azure ADAL SDK which does not support federated credentials.
# Toggle via: cost_export_enabled = false

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
  count        = var.cost_export_enabled ? 1 : 0
  display_name = "sp-${local.base_name}-opencost"
}

resource "azuread_service_principal" "opencost" {
  count     = var.cost_export_enabled ? 1 : 0
  client_id = azuread_application.opencost[0].client_id
}

resource "time_rotating" "opencost_password" {
  count         = var.cost_export_enabled ? 1 : 0
  rotation_days = 330
}

resource "azuread_service_principal_password" "opencost" {
  count                = var.cost_export_enabled ? 1 : 0
  service_principal_id = azuread_service_principal.opencost[0].id
  rotate_when_changed = {
    rotation = time_rotating.opencost_password[0].id
  }
}

resource "azurerm_role_definition" "opencost" {
  count       = var.cost_export_enabled ? 1 : 0
  name        = "OpenCost Reader - ${local.base_name}"
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
  count              = var.cost_export_enabled ? 1 : 0
  scope              = "/subscriptions/${var.subscription_id}"
  role_definition_id = azurerm_role_definition.opencost[0].role_definition_resource_id
  principal_id       = azuread_service_principal.opencost[0].object_id
}

# ========================== workload-operator (hub token sync) ============
# Managed identity for the estabilis-workload-operator pod. Used to sync
# the hub-registrar-token from the cluster to the hub Key Vault.
# Only created when shared_hub_kv_enabled = true (operator can publish to hub KV).

resource "azurerm_user_assigned_identity" "workload_operator" {
  count               = var.shared_hub_kv_enabled ? 1 : 0
  name                = "mi-${local.base_name}-workload-operator"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "workload_operator" {
  count                     = var.shared_hub_kv_enabled ? 1 : 0
  name                      = "fic-${local.base_name}-workload-operator"
  user_assigned_identity_id = azurerm_user_assigned_identity.workload_operator[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:estabilis-system:estabilis-workload-operator"
}

resource "azurerm_role_assignment" "workload_operator_hub_kv" {
  count                = var.shared_hub_kv_enabled ? 1 : 0
  scope                = azurerm_key_vault.hub[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.workload_operator[0].principal_id
}
