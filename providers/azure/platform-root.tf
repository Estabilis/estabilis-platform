# ---------------------------------------------------------------------------
# Platform Root – ArgoCD Application (App-of-Apps bootstrap)
# ---------------------------------------------------------------------------
# Uses the "default" project (always exists in ArgoCD) for bootstrap.
# The "platform" AppProject is created by the Helm chart template
# (argocd-project.yaml, sync wave -1) before any Application needs it.
#
# Multi-source: upstream repo (platform chart + values) + client downstream
# repo (overrides). Client can inject customApps, customPolicies, etc.

resource "kubectl_manifest" "platform_root" {
  depends_on       = [helm_release.argocd]
  wait_for_rollout = false

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "platform-root"
      namespace = "argocd"
      annotations = {
        "estabilis.io/deployed-by" = "terraform"
      }
    }
    spec = {
      project = "default"
      sources = concat(
        [
          {
            repoURL        = var.platform_repo_url
            targetRevision = var.platform_version
            path           = "bootstrap/platform-root"
            helm = {
              valueFiles = concat(
                ["$values/bootstrap/platform-root/values.yaml"],
                (var.config_repo_url != "" && var.config_repo_version != "") ? ["$overrides/overrides/platform-root/values.yaml"] : [],
              )
              ignoreMissingValueFiles = true
              parameters = [
                # --- Platform ---
                {
                  name  = "platformRepoUrl"
                  value = var.platform_repo_url
                },
                {
                  name  = "platformVersion"
                  value = var.platform_version
                },

                # --- Client config (from tfvars) ---
                {
                  name  = "global.provider"
                  value = "azure"
                },
                {
                  name  = "global.domain"
                  value = var.domain
                },
                {
                  name  = "global.effectiveDomain"
                  value = local.effective_domain
                },
                {
                  name  = "global.hostPattern"
                  value = var.host_pattern
                },
                {
                  name  = "global.environment"
                  value = var.environment
                },
                {
                  name  = "global.letsencryptEmail"
                  value = var.letsencrypt_email
                },
                {
                  name  = "configRepoUrl"
                  value = var.config_repo_url
                },
                {
                  name  = "configRepoVersion"
                  value = var.config_repo_version
                },

                # --- Backup/Observability config (from tfvars) ---
                {
                  name  = "global.veleroBackupSchedule"
                  value = var.velero_backup_schedule
                },
                {
                  name  = "global.veleroBackupRetentionHours"
                  value = tostring(var.velero_backup_retention_hours)
                },
                {
                  name  = "global.lokiExternalIngressEnabled"
                  value = tostring(var.loki_external_ingress_enabled)
                },
                {
                  name  = "global.lokiAllowedCidrs"
                  value = var.loki_allowed_cidrs
                },
                {
                  name  = "global.cnpgBackupRetentionDays"
                  value = tostring(var.cnpg_backup_retention_days)
                },
                {
                  name  = "global.cnpgBackupSchedule"
                  value = var.cnpg_backup_schedule
                },

                # --- Azure resource outputs ---
                {
                  name  = "global.clusterName"
                  value = azurerm_kubernetes_cluster.platform.name
                },
                {
                  name  = "global.resourceGroup"
                  value = azurerm_resource_group.platform.name
                },
                {
                  name  = "global.tenantId"
                  value = var.tenant_id
                },
                {
                  name  = "global.subscriptionId"
                  value = var.subscription_id
                },
                {
                  name  = "global.azureOfferId"
                  value = local.azure_offer_id
                },
                {
                  name  = "global.storageAccountName"
                  value = azurerm_storage_account.observability.name
                },
                {
                  name  = "global.keyVaultName"
                  value = azurerm_key_vault.platform.name
                },
                {
                  name  = "global.keyVaultUri"
                  value = azurerm_key_vault.platform.vault_uri
                },
                {
                  name  = "global.cnpgStorageAccountName"
                  value = azurerm_storage_account.cnpg_backup.name
                },
                {
                  name  = "global.cnpgBackupContainerName"
                  value = azurerm_storage_container.cnpg_backup.name
                },
                {
                  name  = "global.veleroStorageAccountName"
                  value = azurerm_storage_account.velero_backup.name
                },
                {
                  name  = "global.veleroBackupContainerName"
                  value = azurerm_storage_container.velero_backup.name
                },

                # --- Workload Identity client IDs ---
                {
                  name  = "identity.externalDns.clientId"
                  value = azurerm_user_assigned_identity.external_dns.client_id
                },
                {
                  name  = "identity.externalSecrets.clientId"
                  value = azurerm_user_assigned_identity.external_secrets.client_id
                },
                {
                  name  = "identity.loki.clientId"
                  value = azurerm_user_assigned_identity.loki.client_id
                },
                {
                  name  = "identity.mimir.clientId"
                  value = azurerm_user_assigned_identity.mimir.client_id
                },
                {
                  name  = "identity.cnpg.clientId"
                  value = azurerm_user_assigned_identity.cnpg.client_id
                },
                {
                  name  = "identity.certManager.clientId"
                  value = azurerm_user_assigned_identity.cert_manager.client_id
                },
                {
                  name  = "identity.velero.clientId"
                  value = azurerm_user_assigned_identity.velero.client_id
                },
              ]
            }
          },
          {
            repoURL        = var.platform_repo_url
            targetRevision = var.platform_version
            ref            = "values"
          },
        ],
        (var.config_repo_url != "" && var.config_repo_version != "") ? [
          {
            repoURL        = var.config_repo_url
            targetRevision = var.config_repo_version
            ref            = "overrides"
          },
        ] : [],
      )
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  })
}
