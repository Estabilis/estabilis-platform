# ---------------------------------------------------------------------------
# The handoff from Terraform to ArgoCD
#
# What Terraform knows about the infrastructure, written where the platform can
# read it. See README.md for why this is a module rather than part of a
# provider — the short version is that it talks to the Kubernetes API, which a
# hosted CI runner cannot reach, so it must not sit in the state of anything CI
# needs to plan.
#
# Every input is a value. The caller decides whether they come from a sibling
# module, a terraform_remote_state of the foundation, or literals.
#
# EXTENSIBLE ON PURPOSE. platform_outputs_extra exists because a DigitalOcean
# deployment knows things no provider module can: Vault's seal lives in Google
# Cloud KMS, since DigitalOcean has no KMS at all, and that key belongs to the
# deployment.
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "argocd" {

  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "estabilis-platform"
    }
  }
}

resource "kubernetes_config_map_v1" "platform_infrastructure" {

  metadata {
    name      = "platform-infrastructure"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "estabilis-platform"
    }
  }

  data = merge(
    {
      # Where the platform's own charts and values come from.
      platformRepoUrl  = var.platform_repo_url
      platformVersion  = var.platform_version
      platformRevision = var.platform_revision

      configRepoUrl      = var.config_repo_url
      configRepoVersion  = var.config_repo_version
      configRepoRevision = var.config_repo_revision

      clientGitopsRepoUrl      = var.client_gitops_repo_url
      clientGitopsRepoVersion  = var.client_gitops_repo_version
      clientGitopsRepoRevision = var.client_gitops_repo_revision

      # How a cluster finds its own directory in the GitOps repository.
      deploymentId = var.deployment_id

      "global.provider"    = "digitalocean"
      "global.environment" = var.environment
      "global.region"      = var.region
      "global.clusterName" = var.cluster_name
      "global.vpcUuid"     = var.vpc_uuid

      # Reported by the API rather than echoed from the variable: with
      # kubernetes_version_prefix the deployment tracks a series and the exact
      # patch is DigitalOcean's choice, not ours.
      "global.kubernetesVersion" = var.kubernetes_version

      # DNS and TLS. There is no DigitalOcean equivalent of Route 53 or Azure
      # DNS in this design — external-dns and cert-manager talk to Cloudflare,
      # whose credential arrives through the module below.
      "global.domain"           = var.domain
      "global.dnsProvider"      = var.dns_provider
      "global.cloudflareZoneId" = var.cloudflare_zone_id
      "global.letsencryptEmail" = var.letsencrypt_email

      "global.ingressController" = var.ingress_controller
      "global.traefikInternal"   = tostring(var.traefik_internal)
      "global.argocdUrl"         = var.argocd_url != "" ? var.argocd_url : "https://argocd.${var.domain}"

      # A ConfigMap holds strings, so these are JSON. Disabled entries are
      # dropped rather than shipped as `enabled: false`: the platform reads this
      # to decide what to expose, and a list containing things it must not
      # expose is one typo away from exposing them.
      "global.argocdExposures"   = jsonencode({ for k, v in var.argocd_exposures : k => v if v.enabled })
      "global.grafanaExposures"  = jsonencode({ for k, v in var.grafana_exposures : k => v if v.enabled })
      "global.lokiExposures"     = jsonencode({ for k, v in var.loki_exposures : k => v if v.enabled })
      "global.mimirExposures"    = jsonencode({ for k, v in var.mimir_exposures : k => v if v.enabled })
      "global.vaultExposures"    = jsonencode({ for k, v in var.vault_exposures : k => v if v.enabled })
      "global.hubbleUiExposures" = jsonencode({ for k, v in var.hubble_ui_exposures : k => v if v.enabled })

      # Object storage. Spaces is S3-compatible, so the components address it
      # by endpoint and bucket exactly as they would S3 — what differs is that
      # there is no instance identity here, so each bucket's key travels in the
      # Secret below rather than being assumed from a role.
      "global.spacesEndpoint"          = "https://${var.spaces_region}.digitaloceanspaces.com"
      "global.spacesRegion"            = var.spaces_region
      "global.observabilityBucketName" = var.observability_bucket_name
      "global.veleroBackupBucketName"  = var.velero_bucket_name
      "global.cnpgBackupBucketName"    = var.cnpg_bucket_name
      "global.vaultBackupBucketName"   = var.vault_backup_bucket_name

      "global.veleroBackupSchedule"       = var.velero_backup_schedule
      "global.veleroBackupRetentionHours" = tostring(var.velero_backup_retention_hours)
      "global.cnpgBackupSchedule"         = var.cnpg_backup_schedule
      "global.cnpgBackupRetentionDays"    = tostring(var.cnpg_backup_retention_days)

      # Empty unless a registry is managed here. Not the account's registry:
      # naming one this module did not create would tell the platform to pull
      # from something nobody here controls.
      "global.registryEndpoint" = var.registry_endpoint

      "global.slackAlertingEnabled" = tostring(var.slack_alerting_enabled)
      "global.openaiApiKeyEnabled"  = tostring(var.openai_api_key_enabled)
    },
    var.platform_outputs_extra,
  )

  lifecycle {
    # These five are REQUIRED on the AWS provider, where every deployment writes
    # the handoff. Copying that here would have broken every existing
    # DigitalOcean deployment on upgrade: the toggle defaults to off, so nobody
    # had reason to set them, and a required variable fails the plan before it
    # can explain itself.
    #
    # Empty defaults plus this check keeps both properties — a deployment that
    # has not adopted the handoff is untouched, and one that turns it on without
    # the values is told which are missing rather than writing a ConfigMap that
    # sends ArgoCD nowhere.
    precondition {
      condition = length(compact([
        var.platform_repo_url,
        var.config_repo_url,
        var.client_gitops_repo_url,
        var.domain,
        var.letsencrypt_email,
      ])) == 5
      error_message = "This module needs platform_repo_url, config_repo_url, client_gitops_repo_url, domain and letsencrypt_email. Empty ones produce a ConfigMap that points ArgoCD at nothing, which fails later and further away than here."
    }
  }
}

# ---------------------------------------------------------------------------
# The sensitive half
#
# AWS puts IRSA role ARNs here and Azure puts client ids: on both, the identity
# is the secret's substitute and nothing confidential travels. DigitalOcean has
# no workload identity, so the credentials themselves do — one scoped Spaces key
# per bucket, each able to reach exactly its own.
#
# That is the honest cost of the platform: a component that reads its bucket
# holds a key that opens that bucket. Scoping is the only mitigation available,
# and it is why every bucket here comes with its own key rather than sharing
# one.
# ---------------------------------------------------------------------------

resource "kubernetes_secret_v1" "platform_infrastructure" {

  metadata {
    name      = "platform-infrastructure-sensitive"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "estabilis-platform"
    }
  }

  data = merge(
    {
      # Cloudflare, when it is the DNS provider. A KEY HERE, not a Secret of its
      # own — which is what the Azure provider does and what this file used to
      # get wrong.
      #
      # The alternative is modules/cloudflare-credentials, which writes a Secret
      # into the namespace of whatever will read it. That cannot work in a
      # handoff: this runs BEFORE the platform, so external-dns's namespace does
      # not exist yet, and the apply fails with `namespaces "external-dns" not
      # found`. The AWS provider works around it by forcing the namespace to
      # argocd, which leaves a stray Secret in a namespace that is not its own.
      #
      # Putting it here needs no workaround. The namespace was created two
      # resources ago, and external-dns-config distributes it once ArgoCD has
      # made the namespace that consumes it.
      "global.cloudflareApiToken" = var.dns_provider == "cloudflare" ? var.cloudflare_api_token : ""

      "storage.observability.accessKeyId"     = var.observability_access_key_id
      "storage.observability.secretAccessKey" = var.observability_secret_access_key
      "storage.velero.accessKeyId"            = var.velero_access_key_id
      "storage.velero.secretAccessKey"        = var.velero_secret_access_key
      "storage.cnpg.accessKeyId"              = var.cnpg_access_key_id
      "storage.cnpg.secretAccessKey"          = var.cnpg_secret_access_key
      "storage.vaultBackup.accessKeyId"       = var.vault_backup_access_key_id
      "storage.vaultBackup.secretAccessKey"   = var.vault_backup_secret_access_key
    },
    var.platform_outputs_extra_sensitive,
  )
}

# ---------------------------------------------------------------------------
# The cluster ArgoCD manages, described to ArgoCD itself.
#
# `in-cluster` would do for a single cluster, but naming it explicitly is what
# lets an ApplicationSet target it by label later without every Application
# hard-coding a URL.
# ---------------------------------------------------------------------------

resource "kubernetes_secret_v1" "hub_cluster" {
  count = var.hub_cluster_secret_enabled ? 1 : 0

  metadata {
    name      = "hub-cluster"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "estabilis.io/cluster-type"      = "hub"
      "app.kubernetes.io/managed-by"   = "terraform"
    }
  }

  data = {
    name   = var.cluster_name
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }
}

# ---------------------------------------------------------------------------
# The GitHub App, as an ArgoCD repository credential
#
# This one IS a Secret of its own, and legitimately: ArgoCD reads repository
# credentials by label from its own namespace, which exists by the time this
# runs. The Cloudflare token has no such consumer at handoff time, which is why
# it travels in the Secret above instead.
# ---------------------------------------------------------------------------

module "github_app_credentials" {
  source = "../../modules/github-app-credentials"
  count  = var.github_app_credentials_enabled ? 1 : 0

  github_app_id              = var.github_app_id
  github_app_installation_id = var.github_app_installation_id
  github_app_private_key     = var.github_app_private_key
  github_org_url             = var.github_org_url
  namespace                  = kubernetes_namespace_v1.argocd.metadata[0].name
}
