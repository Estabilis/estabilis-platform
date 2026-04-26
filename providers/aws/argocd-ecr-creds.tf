# ---------------------------------------------------------------------------
# ArgoCD ↔ ECR auth bridge
#
# Wires `argocd-repo-server` to pull OCI helm charts from the
# platform-provisioned ECR. Without this, ArgoCD Applications referencing
# `oci://<account>.dkr.ecr.<region>.amazonaws.com/<prefix>/<chart>` fail
# at sync with `basic credential not found` (see issue #202 for the full
# postmortem).
#
# Pattern — ESO native ECRAuthorizationToken generator:
#
#   1. external-secrets IRSA gets ECR auth + pull permissions
#      (this file's `aws_iam_policy.external_secrets_ecr`).
#   2. ECRAuthorizationToken generator in `argocd` ns mints docker
#      credentials by calling `ecr:GetAuthorizationToken` via ESO's
#      IRSA-bound ServiceAccount (this file's
#      `kubernetes_manifest.ecr_auth_token`).
#   3. ExternalSecret in `argocd` ns writes the credentials to a
#      Secret labelled `argocd.argoproj.io/secret-type=repository`
#      with refreshInterval=10h (under ECR's 12h token TTL); ArgoCD
#      reads it and uses for any Helm OCI source matching the URL
#      prefix (this file's `kubernetes_manifest.argocd_ecr_repo`).
#
# Lifecycle: provisioned only when `var.ecr_enabled = true`. Disabling
# ECR tears all three resources down cleanly.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# IAM — extend external-secrets IRSA with ECR permissions
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "external_secrets_ecr" {
  count = var.ecr_enabled ? 1 : 0

  name        = "${local.cluster_name}-external-secrets-ecr"
  description = "Allows external-secrets-operator to mint ECR auth tokens via the ECRAuthorizationToken generator (used by argocd-repo-server to pull OCI helm charts) and the resulting tokens to pull artifacts."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:GetDownloadUrlForLayer",
          "ecr:ListImages",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets_ecr" {
  count = var.ecr_enabled ? 1 : 0

  role       = module.external_secrets_irsa.iam_role_name
  policy_arn = aws_iam_policy.external_secrets_ecr[0].arn
}

# ---------------------------------------------------------------------------
# K8s — ECRAuthorizationToken generator + ExternalSecret target
#
# Both depend on the ESO CRDs being installed in the cluster. ESO is
# deployed by ArgoCD (platform-root chart) on first reconcile after the
# cluster comes up. This module does NOT block on ESO install — if the
# manifests apply before CRDs exist, terraform reports an error and the
# operator re-runs `terraform apply` after ESO settles. Idempotent.
#
# Future: migrate these manifests to a chart in
# estabilis-platform-gitops/components/argocd-ecr-creds/ rendered by
# platform-root, eliminating the cross-domain TF→CRD ordering. Tracked
# in #202.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "ecr_auth_token" {
  count = var.ecr_enabled ? 1 : 0

  manifest = {
    apiVersion = "generators.external-secrets.io/v1alpha1"
    kind       = "ECRAuthorizationToken"
    metadata = {
      name      = "ecr-auth"
      namespace = "argocd"
    }
    spec = {
      region = var.region
      auth = {
        jwt = {
          serviceAccountRef = {
            name      = "external-secrets"
            namespace = "external-secrets"
          }
        }
      }
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.external_secrets_ecr,
    kubernetes_namespace.argocd,
  ]
}

resource "kubernetes_manifest" "argocd_ecr_repo" {
  count = var.ecr_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "argocd-ecr-repo"
      namespace = "argocd"
    }
    spec = {
      # Refresh comfortably under the 12h ECR token TTL.
      refreshInterval = "10h"

      target = {
        name           = "argocd-ecr-repo"
        creationPolicy = "Owner"
        template = {
          metadata = {
            labels = {
              "argocd.argoproj.io/secret-type" = "repository"
              "estabilis.io/managed-by"        = "platform"
              "estabilis.io/component"         = "argocd-ecr-creds"
            }
          }
          # ArgoCD repo Secret schema for Helm OCI:
          #   type=helm, enableOCI=true, url, username, password
          # url uses the registry root so any chart pulled from this
          # registry matches by prefix. Cortex example:
          #   093996075120.dkr.ecr.us-east-1.amazonaws.com
          data = {
            type      = "helm"
            enableOCI = "true"
            url       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
            username  = "{{ .username }}"
            password  = "{{ .password }}"
          }
        }
      }

      dataFrom = [
        {
          sourceRef = {
            generatorRef = {
              apiVersion = "generators.external-secrets.io/v1alpha1"
              kind       = "ECRAuthorizationToken"
              name       = "ecr-auth"
            }
          }
        },
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.ecr_auth_token,
  ]
}
