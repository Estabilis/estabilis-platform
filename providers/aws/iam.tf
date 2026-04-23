# ---------------------------------------------------------------------------
# IRSA (IAM Roles for Service Accounts) — 1:1 mirror of the Azure
# Workload Identity layout in providers/azure/workload-identity.tf.
#
# Each role:
#   - Uses the EKS OIDC provider (module.eks.oidc_provider_arn)
#   - Trusts a specific ServiceAccount in a specific namespace
#   - Has a least-privilege policy scoped to the exact resources needed
#
# Upstream module reference: terraform-aws-modules/iam/aws v5.60
# (iam-role-for-service-accounts-eks submodule provides built-in policies
# for cert-manager, external-dns, external-secrets, velero, alb-controller).
# ---------------------------------------------------------------------------

# ========================== external-secrets ==============================

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"

  role_name                             = "${local.cluster_name}-external-secrets"
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = ["arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:estabilis/${var.deployment_id}/*"]
  external_secrets_kms_key_arns         = [aws_kms_key.platform_secrets.arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}

# ========================== external-dns ==================================

module "external_dns_irsa" {
  count = var.dns_provider == "route53" ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"

  role_name                     = "${local.cluster_name}-external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = local.route53_zone_arns_or_wildcard

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-dns:external-dns"]
    }
  }
}

# ========================== cert-manager ==================================
# Only when dns_provider = 'route53' (DNS-01 solver needs Route53 permissions).
# When dns_provider = 'cloudflare', cert-manager uses a static API token and
# does not need IRSA.

module "cert_manager_irsa" {
  count = var.dns_provider == "route53" ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"

  role_name                     = "${local.cluster_name}-cert-manager"
  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = local.route53_zone_arns_or_wildcard

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["cert-manager:cert-manager"]
    }
  }
}

# ========================== velero ========================================

module "velero_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"

  role_name             = "${local.cluster_name}-velero"
  attach_velero_policy  = true
  velero_s3_bucket_arns = [aws_s3_bucket.velero.arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["velero:velero-server"]
    }
  }
}

# ========================== loki ==========================================
# No upstream helper for Loki S3 access — bespoke role with the minimum
# policy needed to read/write Loki chunks + index.

data "aws_iam_policy_document" "loki_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:grafana:grafana-loki"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "loki_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      aws_s3_bucket.observability.arn,
      "${aws_s3_bucket.observability.arn}/loki/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.s3_data.arn]
  }
}

resource "aws_iam_role" "loki" {
  name               = "${local.cluster_name}-loki"
  assume_role_policy = data.aws_iam_policy_document.loki_trust.json
}

resource "aws_iam_role_policy" "loki_s3" {
  name   = "${local.cluster_name}-loki-s3"
  role   = aws_iam_role.loki.id
  policy = data.aws_iam_policy_document.loki_s3.json
}

# ========================== mimir =========================================

data "aws_iam_policy_document" "mimir_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:grafana:grafana-mimir"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "mimir_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      aws_s3_bucket.observability.arn,
      "${aws_s3_bucket.observability.arn}/mimir/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.s3_data.arn]
  }
}

resource "aws_iam_role" "mimir" {
  name               = "${local.cluster_name}-mimir"
  assume_role_policy = data.aws_iam_policy_document.mimir_trust.json
}

resource "aws_iam_role_policy" "mimir_s3" {
  name   = "${local.cluster_name}-mimir-s3"
  role   = aws_iam_role.mimir.id
  policy = data.aws_iam_policy_document.mimir_s3.json
}

# ========================== cnpg (CloudNativePG) ==========================
# Even though database infra is out of scope for Phase 1, CNPG runs inside
# the cluster and backs up to S3. The IRSA role is provisioned so the
# operator pod can write WAL + base backups without additional steps later.

data "aws_iam_policy_document" "cnpg_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:cnpg-system:platform-postgres"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cnpg_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      aws_s3_bucket.cnpg_backup.arn,
      "${aws_s3_bucket.cnpg_backup.arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.s3_data.arn]
  }
}

resource "aws_iam_role" "cnpg" {
  name               = "${local.cluster_name}-cnpg"
  assume_role_policy = data.aws_iam_policy_document.cnpg_trust.json
}

resource "aws_iam_role_policy" "cnpg_s3" {
  name   = "${local.cluster_name}-cnpg-s3"
  role   = aws_iam_role.cnpg.id
  policy = data.aws_iam_policy_document.cnpg_s3.json
}

# ========================== workload-operator =============================
# Estabilis workload operator syncs hub-registrar-token from the platform
# cluster to a shared Secrets Manager path consumed by workload clusters.
# Only created when shared_hub_secrets_enabled = true.

data "aws_iam_policy_document" "workload_operator_trust" {
  count = var.shared_hub_secrets_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:estabilis-system:estabilis-workload-operator"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "workload_operator_secrets" {
  count = var.shared_hub_secrets_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:TagResource",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${local.shared_hub_secrets_prefix_effective}/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.platform_secrets.arn]
  }
}

resource "aws_iam_role" "workload_operator" {
  count              = var.shared_hub_secrets_enabled ? 1 : 0
  name               = "${local.cluster_name}-workload-operator"
  assume_role_policy = data.aws_iam_policy_document.workload_operator_trust[0].json
}

resource "aws_iam_role_policy" "workload_operator_secrets" {
  count  = var.shared_hub_secrets_enabled ? 1 : 0
  name   = "${local.cluster_name}-workload-operator"
  role   = aws_iam_role.workload_operator[0].id
  policy = data.aws_iam_policy_document.workload_operator_secrets[0].json
}
