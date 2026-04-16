# ---------------------------------------------------------------------------
# GitOps Bridge — write Terraform outputs to Kubernetes for ArgoCD consumption
# ---------------------------------------------------------------------------
# Creates a ConfigMap (non-sensitive) and Secret (sensitive) in the argocd
# namespace with all values needed by the platform-root Application.
#
# This eliminates the dependency on the estabilis CLI for parameter resolution
# and enables CI/CD pipelines to bootstrap the platform without the CLI.
#
# Toggle: var.platform_outputs_enabled (default: true)
# Issue: https://github.com/Estabilis/estabilis-platform/issues/57
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "argocd" {
  count = var.platform_outputs_enabled ? 1 : 0

  metadata {
    name = "argocd"
  }

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

# ---------------------------------------------------------------------------
# ConfigMap — non-sensitive platform infrastructure values
# ---------------------------------------------------------------------------

resource "kubernetes_config_map" "platform_infrastructure" {
  count = var.platform_outputs_enabled ? 1 : 0

  metadata {
    name      = "platform-infrastructure"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "estabilis-platform"
    }
  }

  data = {
    # Platform versions
    "platformRepoUrl"   = var.platform_repo_url
    "platformVersion"   = var.platform_version
    "configRepoUrl"     = var.config_repo_url
    "configRepoVersion" = var.config_repo_version

    # Client GitOps (structural — version lives in overrides YAML)
    "clientGitopsRepoUrl" = var.client_gitops_repo_url
    "deploymentId"        = var.deployment_id

    # Global
    "global.provider"         = "azure"
    "global.domain"           = var.domain
    "global.effectiveDomain"  = local.effective_domain
    "global.hostPattern"      = var.host_pattern
    "global.environment"      = var.environment
    "global.letsencryptEmail" = var.letsencrypt_email

    # Azure resources
    "global.clusterName"               = azurerm_kubernetes_cluster.platform.name
    "global.resourceGroup"             = azurerm_resource_group.platform.name
    "global.storageAccountName"        = azurerm_storage_account.observability.name
    "global.cnpgStorageAccountName"    = azurerm_storage_account.cnpg_backup.name
    "global.cnpgBackupContainerName"   = "cnpg-backup"
    "global.veleroStorageAccountName"  = azurerm_storage_account.velero_backup.name
    "global.veleroBackupContainerName" = "velero-backup"

    # Backup & Observability
    "global.veleroBackupSchedule"       = var.velero_backup_schedule
    "global.veleroBackupRetentionHours" = tostring(var.velero_backup_retention_hours)
    "global.cnpgBackupRetentionDays"    = tostring(var.cnpg_backup_retention_days)
    "global.cnpgBackupSchedule"         = var.cnpg_backup_schedule
    "global.lokiExternalIngressEnabled" = tostring(var.loki_external_ingress_enabled)
    "global.lokiAllowedCidrs"           = var.loki_allowed_cidrs

    # Grafana external ingress (per-app IP allowlist via Traefik Middleware)
    "global.grafanaExternalIngressEnabled" = tostring(var.grafana_external_ingress_enabled)
    "global.grafanaAllowedCidrs"           = var.grafana_allowed_cidrs

    # ACR
    "global.acrLoginServer" = var.acr_enabled ? azurerm_container_registry.platform[0].login_server : ""

    # Cost
    "global.azureOfferId" = local.azure_offer_id

    # Hub Key Vault (for workload-operator to publish hub-registrar-token)
    "hubKeyVaultName"  = var.shared_hub_kv_enabled ? azurerm_key_vault.hub[0].name : ""
    "hubResourceGroup" = var.shared_hub_kv_enabled ? azurerm_resource_group.shared[0].name : ""
  }
}

# ---------------------------------------------------------------------------
# Secret — sensitive platform infrastructure values
# ---------------------------------------------------------------------------

resource "kubernetes_secret" "platform_infrastructure" {
  count = var.platform_outputs_enabled ? 1 : 0

  metadata {
    name      = "platform-infrastructure-sensitive"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "estabilis-platform"
    }
  }

  data = {
    # Identity
    "global.tenantId"       = var.tenant_id
    "global.subscriptionId" = var.subscription_id

    # Key Vault
    "global.keyVaultName" = azurerm_key_vault.platform.name
    "global.keyVaultUri"  = azurerm_key_vault.platform.vault_uri

    # Workload Identity client IDs
    "identity.certManager.clientId"     = azurerm_user_assigned_identity.cert_manager.client_id
    "identity.externalDns.clientId"     = azurerm_user_assigned_identity.external_dns.client_id
    "identity.externalSecrets.clientId" = azurerm_user_assigned_identity.external_secrets.client_id
    "identity.loki.clientId"            = azurerm_user_assigned_identity.loki.client_id
    "identity.mimir.clientId"           = azurerm_user_assigned_identity.mimir.client_id
    "identity.cnpg.clientId"            = azurerm_user_assigned_identity.cnpg.client_id
    "identity.velero.clientId"          = azurerm_user_assigned_identity.velero.client_id

    # Workload-operator (publishes hub-registrar-token to hub Key Vault)
    "identity.workloadOperator.clientId" = var.shared_hub_kv_enabled ? azurerm_user_assigned_identity.workload_operator[0].client_id : ""
  }
}

# ---------------------------------------------------------------------------
# ArgoCD Cluster Secret — hub cluster (GitOps Bridge, ADR 0010)
# ---------------------------------------------------------------------------
# Distinct from ArgoCD's auto-managed `in-cluster` Secret. Registers the hub
# as a separate cluster entry whose annotations carry Terraform-known values
# that ApplicationSet-based addon templates consume via the `clusters`
# generator. Annotations live in the reserved `estabilis.io/bridge.<name>`
# namespace (registry maintained in ADR 0010 §Decision).
#
# Why a second cluster entry instead of annotating `in-cluster`: the auto
# `in-cluster` Secret is synthesized by ArgoCD and would be overwritten on
# upgrade. ArgoCD's docs recommend a dedicated Secret for this purpose and
# treats both as distinct clusters pointing at the same server (selector
# disambiguates).

resource "kubernetes_secret" "hub_cluster" {
  count = var.platform_outputs_enabled ? 1 : 0

  metadata {
    name      = "hub-cluster"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      # ADR 0003 S4 vocabulary
      "estabilis.io/managed-by"      = "platform"
      "estabilis.io/component"       = "cluster-registration"
      "estabilis.io/cluster-type"    = "hub"
      "app.kubernetes.io/managed-by" = "terraform"
    }
    annotations = {
      # ADR 0010 v1 bridge registry
      "estabilis.io/bridge.tenant-id"                   = var.tenant_id
      "estabilis.io/bridge.subscription-id"             = var.subscription_id
      "estabilis.io/bridge.hub-key-vault-name"          = var.shared_hub_kv_enabled ? azurerm_key_vault.hub[0].name : ""
      "estabilis.io/bridge.hub-resource-group"          = var.shared_hub_kv_enabled ? azurerm_resource_group.shared[0].name : ""
      "estabilis.io/bridge.workload-operator-client-id" = var.shared_hub_kv_enabled ? azurerm_user_assigned_identity.workload_operator[0].client_id : ""
    }
  }

  data = {
    name   = "hub"
    server = "https://kubernetes.default.svc"
    config = jsonencode({
      tlsClientConfig = { insecure = false }
    })
  }
}
