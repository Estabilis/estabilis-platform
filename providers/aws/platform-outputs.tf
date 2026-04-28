# ---------------------------------------------------------------------------
# GitOps Bridge — write Terraform outputs to Kubernetes for ArgoCD consumption
# ---------------------------------------------------------------------------
# Creates a ConfigMap (non-sensitive) and Secret (sensitive) in the argocd
# namespace with all values needed by the platform-root Application.
#
# Structure mirrors providers/azure/platform-outputs.tf, with Azure-specific
# fields swapped for AWS equivalents:
#   - tenant_id / subscription_id → account_id / region
#   - resource_group → (none; AWS has flat account)
#   - storage_account_name → s3 bucket names
#   - key_vault_name → secretsPathPrefix (Secrets Manager)
#   - Workload Identity client_id → IRSA role_arn
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
    #
    # Legacy `platformVersion` key retained for backcompat — many child
    # Application templates still read `.Values.platformVersion` directly
    # (not via a helper that prefers `platformRevision`). Writing the
    # same effective ref to both keys keeps the templates functional
    # while downstream charts migrate to the *Revision keys. Without
    # this, bumping only `platform_revision` in tfvars leaves the child
    # Applications stuck at the old `platform_version` default, which
    # silently fails to load newer $values files (e.g. loki-values-aws.yaml
    # added in v0.19.0 only exists at >= v0.19.0 refs).
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
    "global.provider"         = "aws"
    "global.domain"           = var.domain
    "global.environment"      = var.environment
    "global.letsencryptEmail" = var.letsencrypt_email

    # DNS provider — selects external-dns values file and cert-manager ClusterIssuer
    "global.dnsProvider"      = var.dns_provider
    "global.cloudflareZoneId" = var.cloudflare_zone_id

    # AWS resources
    "global.clusterName"     = local.cluster_name
    "global.region"          = var.region
    "global.accountId"       = data.aws_caller_identity.current.account_id
    "global.vpcId"           = local.vpc_id
    "global.oidcIssuerUrl"   = local.cluster_oidc_issuer_url
    "global.oidcProviderArn" = local.cluster_oidc_provider_arn

    # S3 buckets
    "global.observabilityBucketName" = aws_s3_bucket.observability.id
    "global.cnpgBackupBucketName"    = aws_s3_bucket.cnpg_backup.id
    "global.veleroBackupBucketName"  = aws_s3_bucket.velero.id

    # Backup & Observability
    "global.veleroBackupSchedule"       = var.velero_backup_schedule
    "global.veleroBackupRetentionHours" = tostring(var.velero_backup_retention_hours)
    "global.cnpgBackupRetentionDays"    = tostring(var.cnpg_backup_retention_days)
    "global.cnpgBackupSchedule"         = var.cnpg_backup_schedule

    # Ingress / TLS
    "global.ingressController" = var.ingress_controller
    "global.traefikInternal"   = tostring(var.traefik_internal_enabled)
    "global.acmCertificateArn" = var.acm_enabled ? aws_acm_certificate.wildcard[0].arn : ""

    # ADR 0014 — App exposures as JSON-encoded map(object), filtered to
    # only enabled profiles.
    "global.lokiExposures"     = jsonencode({ for k, v in local.loki_exposures_resolved : k => v if v.enabled })
    "global.mimirExposures"    = jsonencode({ for k, v in local.mimir_exposures_resolved : k => v if v.enabled })
    "global.grafanaExposures"  = jsonencode({ for k, v in local.grafana_exposures_resolved : k => v if v.enabled })
    "global.argocdExposures"   = jsonencode({ for k, v in local.argocd_exposures_resolved : k => v if v.enabled })
    "global.hubbleUiExposures" = jsonencode({ for k, v in local.hubble_ui_exposures_resolved : k => v if v.enabled })
    "global.vaultExposures"    = jsonencode({ for k, v in local.vault_exposures_resolved : k => v if v.enabled })

    # Autoscaler + Karpenter wiring
    "global.autoscaler"               = var.autoscaler
    "global.karpenterQueueName"       = contains(["karpenter", "hybrid"], var.autoscaler) ? module.karpenter[0].queue_name : ""
    "global.karpenterNodeRoleName"    = contains(["karpenter", "hybrid"], var.autoscaler) ? module.karpenter[0].node_iam_role_name : ""
    "global.karpenterControllerRole"  = contains(["karpenter", "hybrid"], var.autoscaler) ? module.karpenter[0].iam_role_arn : ""
    "global.karpenterDiscoveryTagKey" = var.karpenter_discovery_tag_key

    # ECR — registry URL is account+region scoped and exists whenever ECR is
    # enabled (for pull-through cache, platform repos, or workload repos).
    "global.ecrRegistry" = var.ecr_enabled ? "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com" : ""

    # Cost
    "global.curReportName" = var.cost_export_enabled ? local.cur_report_name : ""
    "global.curBucketName" = var.cost_export_enabled ? aws_s3_bucket.cur[0].id : ""

    # Hub Secrets Manager prefix (for workload-operator to publish hub-registrar-token)
    "hubSecretsPathPrefix" = var.shared_hub_secrets_enabled ? local.shared_hub_secrets_prefix_effective : ""

    # GitHub App — non-sensitive identifiers. The App ID and Installation
    # ID are public identifiers that ArgoCD needs to build installation
    # tokens (paired with the private key from the Secret). The private
    # key stays in AWS Secrets Manager and is never exposed in the
    # ConfigMap.
    "global.githubAppID"             = var.github_app_id
    "global.githubAppInstallationID" = var.github_app_installation_id
    "global.githubOrgUrl"            = var.github_org_url
  }
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
    "global.accountId" = data.aws_caller_identity.current.account_id
    "global.region"    = var.region

    # Secrets Manager path prefix — ESO ClusterSecretStore scopes to this.
    "global.secretsPathPrefix" = local.secrets_path_prefix

    # IRSA role ARNs — consumed by ArgoCD Application parameters to annotate
    # each ServiceAccount with eks.amazonaws.com/role-arn.
    "identity.certManager.roleArn"      = var.dns_provider == "route53" ? module.cert_manager_irsa[0].arn : ""
    "identity.externalDns.roleArn"      = var.dns_provider == "route53" ? module.external_dns_irsa[0].arn : ""
    "identity.externalSecrets.roleArn"  = module.external_secrets_irsa.arn
    "identity.loki.roleArn"             = aws_iam_role.loki.arn
    "identity.mimir.roleArn"            = aws_iam_role.mimir.arn
    "identity.cnpg.roleArn"             = aws_iam_role.cnpg.arn
    "identity.velero.roleArn"           = module.velero_irsa.arn
    "identity.albController.roleArn"    = var.ingress_controller == "alb" ? module.alb_controller_irsa[0].arn : ""
    "identity.workloadOperator.roleArn" = var.shared_hub_secrets_enabled ? aws_iam_role.workload_operator[0].arn : ""
    "identity.opencost.roleArn"         = var.cost_export_enabled ? aws_iam_role.opencost[0].arn : ""

    # Cloudflare API token — only populated when dns_provider = "cloudflare".
    "global.cloudflareApiToken" = var.dns_provider == "cloudflare" ? var.cloudflare_api_token : ""

    # Vault (v0.27.0+) — populated only when vault_enabled=true.
    # vault.exposuresJson moved to ConfigMap as global.vaultExposures (ADR 0014
    # convention; non-sensitive). The Secret keeps the identity + KMS key id
    # which ARE sensitive.
    "identity.vault.roleArn" = var.vault_enabled ? module.vault_irsa[0].arn : ""
    "vault.kmsKeyId"         = var.vault_enabled ? aws_kms_key.vault[0].key_id : ""
    "vault.kmsRegion"        = var.vault_enabled ? var.region : ""
    "vault.backupBucketName" = var.vault_enabled ? aws_s3_bucket.vault_backup[0].id : ""
  }
}

# ---------------------------------------------------------------------------
# ArgoCD Cluster Secret — hub cluster (GitOps Bridge, ADR 0010)
# ---------------------------------------------------------------------------
# Distinct from ArgoCD's auto-managed `in-cluster` Secret. Registers the hub
# as a separate cluster entry whose annotations carry Terraform-known values
# that ApplicationSet-based addon templates consume via the `clusters`
# generator. Bridge annotation registry maintained in ADR 0010.

resource "kubernetes_secret_v1" "hub_cluster" {
  count = var.platform_outputs_enabled ? 1 : 0

  metadata {
    name      = "hub-cluster"
    namespace = kubernetes_namespace_v1.argocd[0].metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "estabilis.io/managed-by"        = "platform"
      "estabilis.io/component"         = "cluster-registration"
      "estabilis.io/cluster-type"      = "hub"
      "app.kubernetes.io/managed-by"   = "terraform"
    }
    annotations = {
      "estabilis.io/bridge.account-id" = data.aws_caller_identity.current.account_id
      "estabilis.io/bridge.region"     = var.region

      # ADR 0023 Etapa B — cluster-level metadata consumed by client
      # gitops ApplicationSets via the `clusters` generator. Eliminates
      # hardcoded cluster/domain/ingress-group values in per-cluster
      # gitops repos. New annotations:
      #
      #   cluster-name        — used to compose app FQDNs
      #                         {fullname}.{cluster-name}.{domain}
      #   domain              — DNS zone root
      #   ingress-group-name  — alb.ingress.kubernetes.io/group.name
      #                         default for ALL apps in this cluster, so
      #                         a single shared ALB serves the whole
      #                         cluster (cost optimization). Per-app
      #                         override remains via values.yaml when
      #                         isolation is required.
      "estabilis.io/bridge.cluster-name"       = "${var.name_prefix}-${var.deployment_id}"
      "estabilis.io/bridge.domain"             = var.domain
      "estabilis.io/bridge.ingress-group-name" = "${var.name_prefix}-${var.environment}-shared-apps"

      "estabilis.io/bridge.hub-secrets-path-prefix"    = var.shared_hub_secrets_enabled ? local.shared_hub_secrets_prefix_effective : ""
      "estabilis.io/bridge.workload-operator-role-arn" = var.shared_hub_secrets_enabled ? aws_iam_role.workload_operator[0].arn : ""

      # ExternalSecret path resolution — consumed by client ApplicationSets
      # to inject helm parameters `externalSecrets.tier` and
      # `externalSecrets.pathTemplate` into the common-app chart (>= v0.2.0).
      # Path computation lives in locals.tf (see bridge_tier +
      # bridge_secret_path_template) so Provider switching (Vault → AKV /
      # AWS SM) is a one-line change in the upstream module.
      "estabilis.io/bridge.tier"                 = local.bridge_tier
      "estabilis.io/bridge.secret-path-template" = local.bridge_secret_path_template
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
