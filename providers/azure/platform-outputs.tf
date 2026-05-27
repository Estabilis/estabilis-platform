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

resource "kubernetes_namespace_v1" "argocd" {
  count = var.platform_outputs_enabled ? 1 : 0

  metadata {
    name = "argocd"
  }

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

moved {
  from = kubernetes_namespace.argocd
  to   = kubernetes_namespace_v1.argocd
}

# ---------------------------------------------------------------------------
# ConfigMap — non-sensitive platform infrastructure values
# ---------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "platform_infrastructure" {
  count = var.platform_outputs_enabled ? 1 : 0

  metadata {
    name      = "platform-infrastructure"
    namespace = kubernetes_namespace_v1.argocd[0].metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "estabilis-platform"
    }
  }

  data = {
    # Platform versions + revisions (ADR 0020)
    "platformRepoUrl"          = var.platform_repo_url
    "platformVersion"          = local.platform_revision_effective
    "platformRevision"         = local.platform_revision_effective
    "configRepoUrl"            = var.config_repo_url
    "configRepoVersion"        = var.config_repo_version
    "configRepoRevision"       = local.config_repo_revision_effective
    "clientGitopsRepoUrl"      = var.client_gitops_repo_url
    "clientGitopsRepoVersion"  = var.client_gitops_repo_version
    "clientGitopsRepoRevision" = local.client_gitops_revision_effective
    "deploymentId"             = var.deployment_id

    # Global
    "global.provider"         = "azure"
    "global.domain"           = var.domain
    "global.environment"      = var.environment
    "global.letsencryptEmail" = var.letsencrypt_email

    # DNS provider — selects external-dns values file and cert-manager ClusterIssuer
    "global.dnsProvider"      = var.dns_provider
    "global.cloudflareZoneId" = var.cloudflare_zone_id

    # Azure resources
    "global.clusterName"               = azurerm_kubernetes_cluster.platform.name
    "global.region"                    = var.location
    "global.oidcIssuerUrl"             = azurerm_kubernetes_cluster.platform.oidc_issuer_url
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
    # ADR 0014 — App exposures as a JSON-encoded map(object). Filtered to
    # only enabled profiles to keep the ConfigMap small. Platform-root
    # decodes with fromJson and iterates over the result. Uses the
    # *_resolved locals so empty host fields are substituted with the
    # auto-derived hostname (see _app_host in main.tf).
    "global.lokiExposures"    = jsonencode({ for k, v in local.loki_exposures_resolved : k => v if v.enabled })
    "global.mimirExposures"   = jsonencode({ for k, v in local.mimir_exposures_resolved : k => v if v.enabled })
    "global.grafanaExposures" = jsonencode({ for k, v in local.grafana_exposures_resolved : k => v if v.enabled })
    "global.argocdExposures"  = jsonencode({ for k, v in local.argocd_exposures_resolved : k => v if v.enabled })

    # Per-cluster ArgoCD UI URL — flat string consumed by the
    # grafana-dashboards chart to substitute __ARGOCD_URL__ placeholders
    # in the argocd-application dashboard JSON (data links on the table
    # panels). Defaults to the external profile's resolved host when
    # enabled; empty otherwise.
    "global.argocdUrl"         = try(local.argocd_exposures_resolved.external.enabled ? "https://${local.argocd_exposures_resolved.external.host}" : "", "")
    "global.hubbleUiExposures" = jsonencode({ for k, v in local.hubble_ui_exposures_resolved : k => v if v.enabled })
    "global.vaultExposures"    = jsonencode({ for k, v in local.vault_exposures_resolved : k => v if v.enabled })

    # Gate for hubble-ui-ingress rendering (Hubble UI only exists in ACNS)
    "global.networkDataplane" = var.network_dataplane

    # ACR
    "global.acrLoginServer"       = var.acr_enabled ? azurerm_container_registry.platform[0].login_server : ""
    "global.sharedAcrLoginServer" = var.shared_acr_login_server

    # Optional integrations — boolean flags only (never the secret value).
    # platform-secrets chart uses these to gate ExternalSecrets that
    # point at Key Vault entries only created when the operator
    # populates the source variable. Without the gate the chart renders
    # an ExternalSecret expecting a Secret that never exists, producing
    # continuous "Secret does not exist" reconcile errors.
    "global.openaiApiKeyEnabled" = tostring(var.openai_api_key != "")

    # Mimir Alertmanager Slack pipeline
    "global.slackAlertingEnabled" = tostring(var.slack_alerting_enabled)

    # Ingress controller — derived from toggle state (Azure has no
    # freeform ingress_controller var; AWS does).
    "global.ingressController" = var.traefik_enabled ? "traefik" : (var.traefik_internal_enabled ? "traefik-internal" : "none")
    "global.traefikInternal"   = tostring(var.traefik_internal_enabled)

    # Cost
    "global.azureOfferId" = local.azure_offer_id

    # Hub Key Vault (for workload-operator to publish hub-registrar-token)
    "hubKeyVaultName"  = var.shared_hub_kv_enabled ? azurerm_key_vault.hub[0].name : ""
    "hubResourceGroup" = var.shared_hub_kv_enabled ? azurerm_resource_group.shared[0].name : ""
  }
}

moved {
  from = kubernetes_config_map.platform_infrastructure
  to   = kubernetes_config_map_v1.platform_infrastructure
}

# ---------------------------------------------------------------------------
# Secret — sensitive platform infrastructure values
# ---------------------------------------------------------------------------

resource "kubernetes_secret_v1" "platform_infrastructure" {
  count = var.platform_outputs_enabled ? 1 : 0

  metadata {
    name      = "platform-infrastructure-sensitive"
    namespace = kubernetes_namespace_v1.argocd[0].metadata[0].name
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
    "identity.externalDns.clientId"     = var.dns_provider == "azure" ? azurerm_user_assigned_identity.external_dns[0].client_id : ""
    "identity.externalSecrets.clientId" = azurerm_user_assigned_identity.external_secrets.client_id

    # Cloudflare API token — only populated when dns_provider = "cloudflare".
    # Consumed by the external-dns-config chart and the cloudflare
    # cluster-issuer to authenticate to the Cloudflare API.
    "global.cloudflareApiToken" = var.dns_provider == "cloudflare" ? var.cloudflare_api_token : ""
    "identity.loki.clientId"    = azurerm_user_assigned_identity.loki.client_id
    "identity.mimir.clientId"   = azurerm_user_assigned_identity.mimir.client_id
    "identity.cnpg.clientId"    = azurerm_user_assigned_identity.cnpg.client_id
    "identity.velero.clientId"  = azurerm_user_assigned_identity.velero.client_id

    # Workload-operator (publishes hub-registrar-token to hub Key Vault)
    "identity.workloadOperator.clientId" = var.shared_hub_kv_enabled ? azurerm_user_assigned_identity.workload_operator[0].client_id : ""

    # Vault (v0.27.0+) — populated only when vault_enabled=true.
    # vault.exposuresJson moved to ConfigMap as global.vaultExposures (ADR 0014
    # convention; non-sensitive). The Secret keeps the identity + KV name + key
    # name which ARE sensitive (or pseudo-sensitive — KV name is part of the
    # unseal recovery story).
    "identity.vault.clientId"    = var.vault_enabled ? azurerm_user_assigned_identity.vault[0].client_id : ""
    "vault.keyVaultName"         = var.vault_enabled ? azurerm_key_vault.vault_unseal[0].name : ""
    "vault.unsealKeyName"        = var.vault_enabled ? azurerm_key_vault_key.vault_unseal[0].name : ""
    "vault.backupStorageAccount" = var.vault_enabled ? azurerm_storage_account.vault_backup[0].name : ""
    "vault.backupContainer"      = var.vault_enabled ? azurerm_storage_container.vault_backup[0].name : ""
  }
}

moved {
  from = kubernetes_secret.platform_infrastructure
  to   = kubernetes_secret_v1.platform_infrastructure
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

resource "kubernetes_secret_v1" "hub_cluster" {
  count = var.platform_outputs_enabled ? 1 : 0

  metadata {
    name      = "hub-cluster"
    namespace = kubernetes_namespace_v1.argocd[0].metadata[0].name
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
      "estabilis.io/bridge.tenant-id"       = var.tenant_id
      "estabilis.io/bridge.subscription-id" = var.subscription_id
      "estabilis.io/bridge.region"          = var.location

      # ADR 0023 Etapa B — cluster-level metadata consumed by client
      # gitops ApplicationSets via the `clusters` generator.
      "estabilis.io/bridge.cluster-name"       = "${var.name_prefix}-${var.deployment_id}"
      "estabilis.io/bridge.domain"             = var.domain
      "estabilis.io/bridge.ingress-group-name" = ""

      "estabilis.io/bridge.hub-key-vault-name"          = var.shared_hub_kv_enabled ? azurerm_key_vault.hub[0].name : ""
      "estabilis.io/bridge.hub-resource-group"          = var.shared_hub_kv_enabled ? azurerm_resource_group.shared[0].name : ""
      "estabilis.io/bridge.hub-secrets-path-prefix"     = var.vault_enabled ? local.shared_hub_secrets_prefix_effective : ""
      "estabilis.io/bridge.workload-operator-client-id" = var.shared_hub_kv_enabled ? azurerm_user_assigned_identity.workload_operator[0].client_id : ""

      # ExternalSecret path resolution — consumed by client ApplicationSets
      # to inject helm parameters into the common-app chart (>= v0.2.0).
      "estabilis.io/bridge.tier"                 = local.bridge_tier
      "estabilis.io/bridge.secret-path-template" = local.bridge_secret_path_template

      # Dual-domain — internal FQDN for VNet-scoped access
      "estabilis.io/bridge.internal-domain" = var.internal_domain
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

moved {
  from = kubernetes_secret.hub_cluster
  to   = kubernetes_secret_v1.hub_cluster
}
