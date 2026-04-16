# ---------------------------------------------------------------------------
# Azure DevOps Service Connection for ACR push (ADR 0015) — opt-in.
#
# When `azdo_push_automation_enabled = true`, Terraform owns end-to-end:
#   1. AAD Application + Service Principal (no secret)
#   2. AcrPush role assignment on the ACR
#   3. Service Connection in Azure DevOps (WIF Manual mode)
#   4. Federated Identity Credential linking ADO SC ↔ AAD SP
#
# Pipelines reference the Service Connection by name:
#   ${local.base_name}-acr-push    (e.g., transfero-platform-hml-eastus2-acr-push)
#
# Auth: provider authenticates via the active az cli session (AZURE_CONFIG_DIR).
# No PAT is needed. Validated empirically against
# dev.azure.com/estabilis/Transfero on 2026-04-16 (5 resources created,
# destroyed clean).
# ---------------------------------------------------------------------------

data "azuredevops_project" "acr_push" {
  count = var.acr_enabled && var.azdo_push_automation_enabled ? 1 : 0
  name  = var.azdo_project
}

resource "azuread_application" "acr_push_azdo" {
  count        = var.acr_enabled && var.azdo_push_automation_enabled ? 1 : 0
  display_name = "${local.base_name}-acr-push"
  tags         = ["estabilis-platform", "acr-push", local.base_name]
}

resource "azuread_service_principal" "acr_push_azdo" {
  count     = var.acr_enabled && var.azdo_push_automation_enabled ? 1 : 0
  client_id = azuread_application.acr_push_azdo[0].client_id
  tags      = ["estabilis-platform", "acr-push"]
}

resource "azurerm_role_assignment" "acr_push_azdo_sp" {
  count                = var.acr_enabled && var.azdo_push_automation_enabled ? 1 : 0
  scope                = azurerm_container_registry.platform[0].id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.acr_push_azdo[0].object_id
}

resource "azuredevops_serviceendpoint_azurerm" "acr_push" {
  count                                  = var.acr_enabled && var.azdo_push_automation_enabled ? 1 : 0
  project_id                             = data.azuredevops_project.acr_push[0].id
  service_endpoint_name                  = "${local.base_name}-acr-push"
  description                            = "ACR push for ${local.base_name} — managed by Terraform (ADR 0015)"
  service_endpoint_authentication_scheme = "WorkloadIdentityFederation"

  credentials {
    serviceprincipalid = azuread_service_principal.acr_push_azdo[0].client_id
  }

  azurerm_spn_tenantid      = var.tenant_id
  azurerm_subscription_id   = var.subscription_id
  azurerm_subscription_name = data.azurerm_subscription.current.display_name
}

resource "azuread_application_federated_identity_credential" "acr_push_azdo" {
  count          = var.acr_enabled && var.azdo_push_automation_enabled ? 1 : 0
  application_id = azuread_application.acr_push_azdo[0].id
  display_name   = "azdo-${local.base_name}-acr-push"
  issuer         = azuredevops_serviceendpoint_azurerm.acr_push[0].workload_identity_federation_issuer
  subject        = azuredevops_serviceendpoint_azurerm.acr_push[0].workload_identity_federation_subject
  audiences      = ["api://AzureADTokenExchange"]
}
