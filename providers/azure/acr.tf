# ---------------------------------------------------------------------------
# Azure Container Registry — private images + proxy cache
# Toggle via: acr_enabled = true
# ---------------------------------------------------------------------------

locals {
  acr_is_premium = var.acr_sku == "Premium"

  # ACR name: acr<name_prefix><acr_purpose><env_code><suffix?>. acr_purpose=""
  # + suffix enabled preserves the legacy name. acr_purpose="platform" +
  # suffix disabled => deterministic acrtransferoplatformstg.
  acr_name = "acr${var.name_prefix}${var.acr_purpose}${local.env_code}${var.acr_random_suffix_enabled ? random_string.storage_suffix.result : ""}"
}

resource "azurerm_container_registry" "platform" {
  count                = var.acr_enabled ? 1 : 0
  name                 = local.acr_name
  resource_group_name  = azurerm_resource_group.platform.name
  location             = azurerm_resource_group.platform.location
  sku                  = var.acr_sku
  admin_enabled        = false
  trust_policy_enabled = local.acr_is_premium && var.acr_content_trust_enabled

  lifecycle {
    precondition {
      condition     = can(regex("^[a-zA-Z0-9]{5,50}$", local.acr_name))
      error_message = "ACR name '${local.acr_name}' (${length(local.acr_name)} chars) must be 5-50 alphanumeric chars. Adjust name_prefix / acr_purpose, or enable acr_random_suffix_enabled."
    }
  }

  # Retention for untagged manifests — Premium SKU only (0 = disabled)
  retention_policy_in_days = local.acr_is_premium && var.acr_retention_days > 0 ? var.acr_retention_days : null

  # Network rules — Premium SKU only (disabled when using private endpoint).
  # Omitted entirely when not applicable so Azure keeps its default Allow
  # without causing perpetual drift (Azure API always returns a default
  # network_rule_set even when Terraform tries to clear it with []).
  dynamic "network_rule_set" {
    for_each = local.acr_is_premium && var.firewall_enabled && var.acr_firewall_enabled && !var.acr_private_endpoint_enabled ? [1] : []
    content {
      default_action = "Deny"
      ip_rule        = [for ip in local.firewall_acr_ips : { action = "Allow", ip_range = ip }]
    }
  }

  # Disable public access when private endpoint is enabled
  public_network_access_enabled = local.acr_is_premium && var.acr_private_endpoint_enabled ? false : true

  # Geo-replication — Premium SKU only
  dynamic "georeplications" {
    for_each = local.acr_is_premium ? var.acr_georeplications : []
    content {
      location = georeplications.value
      tags     = local.tags
    }
  }

  tags = local.tags
}

# AKS kubelet identity needs AcrPull to pull images without credentials
resource "azurerm_role_assignment" "aks_acr_pull" {
  count                = var.acr_enabled && var.acr_aks_attach_enabled ? 1 : 0
  scope                = azurerm_container_registry.platform[0].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.platform.kubelet_identity[0].object_id
}

# ---------------------------------------------------------------------------
# AcrPush — for existing principals (users, groups, service principals)
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_push" {
  count                = var.acr_enabled ? length(var.acr_push_principal_ids) : 0
  scope                = azurerm_container_registry.platform[0].id
  role_definition_name = "AcrPush"
  principal_id         = var.acr_push_principal_ids[count.index]
}

# ---------------------------------------------------------------------------
# CI/CD managed identity — dedicated identity for pipeline push
# The client adds a federated credential for their CI/CD provider
# (GitHub Actions, GitLab CI, etc.) pointing to this identity's client_id.
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "acr_ci" {
  count               = var.acr_enabled && var.acr_ci_identity_enabled ? 1 : 0
  name                = "mi-${local.base_name}-acr-ci"
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_ci_push" {
  count                = var.acr_enabled && var.acr_ci_identity_enabled ? 1 : 0
  scope                = azurerm_container_registry.platform[0].id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.acr_ci[0].principal_id
}

# ---------------------------------------------------------------------------
# Cache rules — proxy for public registries (no auth required)
# Toggle via: acr_cache_enabled = false
# ---------------------------------------------------------------------------

resource "azurerm_container_registry_cache_rule" "ghcr" {
  count                 = var.acr_enabled && var.acr_cache_enabled ? 1 : 0
  name                  = "ghcrio"
  container_registry_id = azurerm_container_registry.platform[0].id
  source_repo           = "ghcr.io/*"
  target_repo           = "ghcr/*"
}

resource "azurerm_container_registry_cache_rule" "quay" {
  count                 = var.acr_enabled && var.acr_cache_enabled ? 1 : 0
  name                  = "quayio"
  container_registry_id = azurerm_container_registry.platform[0].id
  source_repo           = "quay.io/*"
  target_repo           = "quay/*"
}

resource "azurerm_container_registry_cache_rule" "k8s_registry" {
  count                 = var.acr_enabled && var.acr_cache_enabled ? 1 : 0
  name                  = "k8sregistry"
  container_registry_id = azurerm_container_registry.platform[0].id
  source_repo           = "registry.k8s.io/*"
  target_repo           = "k8s/*"
}

resource "azurerm_container_registry_cache_rule" "mcr" {
  count                 = var.acr_enabled && var.acr_cache_enabled ? 1 : 0
  name                  = "mcrmicrosoft"
  container_registry_id = azurerm_container_registry.platform[0].id
  source_repo           = "mcr.microsoft.com/*"
  target_repo           = "mcr/*"
}

# ---------------------------------------------------------------------------
# Docker Hub cache — requires authenticated credentials
# Toggle via: acr_cache_dockerhub_enabled = true
# Requires: acr_dockerhub_username + acr_dockerhub_token
# ---------------------------------------------------------------------------

# Store Docker Hub credentials in Key Vault
resource "azurerm_key_vault_secret" "dockerhub_username" {
  count        = var.acr_enabled && var.acr_cache_dockerhub_enabled ? 1 : 0
  name         = "acr-dockerhub-username"
  value        = var.acr_dockerhub_username
  key_vault_id = azurerm_key_vault.platform.id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "dockerhub_token" {
  count        = var.acr_enabled && var.acr_cache_dockerhub_enabled ? 1 : 0
  name         = "acr-dockerhub-token"
  value        = var.acr_dockerhub_token
  key_vault_id = azurerm_key_vault.platform.id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_container_registry_credential_set" "dockerhub" {
  count                 = var.acr_enabled && var.acr_cache_dockerhub_enabled ? 1 : 0
  name                  = "dockerhub-credentials"
  container_registry_id = azurerm_container_registry.platform[0].id
  login_server          = "docker.io"

  identity {
    type = "SystemAssigned"
  }

  authentication_credentials {
    username_secret_id = azurerm_key_vault_secret.dockerhub_username[0].versionless_id
    password_secret_id = azurerm_key_vault_secret.dockerhub_token[0].versionless_id
  }
}

resource "azurerm_container_registry_cache_rule" "dockerhub" {
  count                 = var.acr_enabled && var.acr_cache_dockerhub_enabled ? 1 : 0
  name                  = "dockerhub"
  container_registry_id = azurerm_container_registry.platform[0].id
  source_repo           = "docker.io/*"
  target_repo           = "dockerhub/*"
  credential_set_id     = azurerm_container_registry_credential_set.dockerhub[0].id
}

# ---------------------------------------------------------------------------
# Private Endpoint — Premium SKU only
# Eliminates public access, ACR reachable only via VNet
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "acr" {
  count               = var.acr_enabled && local.acr_is_premium && var.acr_private_endpoint_enabled && local.create_local_acr_pdz ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = var.acr_enabled && local.acr_is_premium && var.acr_private_endpoint_enabled && local.create_local_acr_pdz ? 1 : 0
  name                  = "acr-dns-link"
  resource_group_name   = azurerm_resource_group.platform.name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = azurerm_virtual_network.platform.id
  tags                  = local.tags
}

resource "azurerm_private_endpoint" "acr" {
  count               = var.acr_enabled && local.acr_is_premium && var.acr_private_endpoint_enabled ? 1 : 0
  name                = "pe-${local.base_name}-acr"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  subnet_id           = azurerm_subnet.aks_nodes.id
  tags                = local.tags

  private_service_connection {
    name                           = "acr-connection"
    private_connection_resource_id = azurerm_container_registry.platform[0].id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr-dns-group"
    private_dns_zone_ids = [local.acr_pdz_id]
  }
}

# ---------------------------------------------------------------------------
# ArgoCD pull token — scope-limited token for OCI chart pull
# Stored in Key Vault, synced to ArgoCD via ExternalSecret
# ---------------------------------------------------------------------------

resource "azurerm_container_registry_scope_map" "argocd_pull" {
  count                   = var.acr_enabled ? 1 : 0
  name                    = "argocd-chart-pull"
  container_registry_name = azurerm_container_registry.platform[0].name
  resource_group_name     = azurerm_resource_group.platform.name
  actions = [
    "repositories/charts/*/content/read",
    "repositories/charts/*/metadata/read",
  ]
}

resource "azurerm_container_registry_token" "argocd_pull" {
  count                   = var.acr_enabled ? 1 : 0
  name                    = "argocd-pull"
  container_registry_name = azurerm_container_registry.platform[0].name
  resource_group_name     = azurerm_resource_group.platform.name
  scope_map_id            = azurerm_container_registry_scope_map.argocd_pull[0].id
}

resource "azurerm_container_registry_token_password" "argocd_pull" {
  count                       = var.acr_enabled ? 1 : 0
  container_registry_token_id = azurerm_container_registry_token.argocd_pull[0].id

  password1 {}
}

resource "azurerm_key_vault_secret" "acr_argocd_token" {
  count        = var.acr_enabled ? 1 : 0
  name         = "platform-acr-argocd-token"
  value        = azurerm_container_registry_token_password.argocd_pull[0].password1[0].value
  key_vault_id = azurerm_key_vault.platform.id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}
