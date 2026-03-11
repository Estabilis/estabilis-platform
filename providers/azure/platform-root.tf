# ---------------------------------------------------------------------------
# Platform Root – ArgoCD Application (App-of-Apps bootstrap)
# ---------------------------------------------------------------------------

resource "kubectl_manifest" "argocd_project_platform" {
  depends_on = [helm_release.argocd]

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "platform"
      namespace = "argocd"
    }
    spec = {
      description = "Estabilis Platform core components"
      sourceRepos = [
        var.platform_repo_url,
        "https://argoproj.github.io/argo-helm",
        "https://charts.jetstack.io",
        "https://kyverno.github.io/kyverno",
        "https://charts.external-secrets.io",
        "https://kubernetes-sigs.github.io/external-dns",
        "https://grafana.github.io/helm-charts",
      ]
      destinations = [
        { server = "https://kubernetes.default.svc", namespace = "argocd" },
        { server = "https://kubernetes.default.svc", namespace = "cert-manager" },
        { server = "https://kubernetes.default.svc", namespace = "kyverno" },
        { server = "https://kubernetes.default.svc", namespace = "external-secrets" },
        { server = "https://kubernetes.default.svc", namespace = "external-dns" },
        { server = "https://kubernetes.default.svc", namespace = "grafana" },
        { server = "https://kubernetes.default.svc", namespace = "kube-system" },
      ]
      clusterResourceWhitelist = [
        { group = "*", kind = "Namespace" },
        { group = "*", kind = "ClusterRole" },
        { group = "*", kind = "ClusterRoleBinding" },
        { group = "kyverno.io", kind = "ClusterPolicy" },
        { group = "apiextensions.k8s.io", kind = "CustomResourceDefinition" },
        { group = "admissionregistration.k8s.io", kind = "*" },
        { group = "cert-manager.io", kind = "ClusterIssuer" },
        { group = "external-secrets.io", kind = "ClusterSecretStore" },
      ]
    }
  })
}

resource "kubectl_manifest" "platform_root" {
  depends_on = [helm_release.argocd, kubectl_manifest.argocd_project_platform]

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "platform-root"
      namespace = "argocd"
    }
    spec = {
      project = "platform"
      source = {
        repoURL        = var.platform_repo_url
        targetRevision = var.platform_version
        path           = "bootstrap/platform-root"
        helm = {
          parameters = [
            {
              name  = "global.domain"
              value = var.domain
            },
            {
              name  = "global.environment"
              value = var.environment
            },
            {
              name  = "global.provider"
              value = "azure"
            },
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
              name  = "platformRepoUrl"
              value = var.platform_repo_url
            },
            {
              name  = "platformVersion"
              value = var.platform_version
            },
          ]
        }
      }
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
