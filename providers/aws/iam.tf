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
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.5"

  # v6 default flipped use_name_prefix to true; CAF names overflow IAM's
  # 38-char name_prefix cap. See ebs_csi_irsa in eks.tf.
  use_name_prefix                       = false
  name                                  = "${local.cluster_name}-external-secrets"
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = ["arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:estabilis/${var.deployment_id}/*"]
  external_secrets_kms_key_arns         = [aws_kms_key.platform_secrets.arn]

  # IAM policy name. Submodule hardcodes `External_Secrets` when null →
  # collides across clusters in the same AWS account. See CONTRIBUTING.md
  # "IRSA module convention".
  policy_name = var.iam_policy_name_use_cluster_prefix ? "${local.cluster_name}-External_Secrets" : null

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

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.5"

  use_name_prefix               = false
  name                          = "${local.cluster_name}-external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = local.route53_zone_arns_or_wildcard

  # See CONTRIBUTING.md "IRSA module convention".
  policy_name = var.iam_policy_name_use_cluster_prefix ? "${local.cluster_name}-External_DNS" : null

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

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.5"

  use_name_prefix               = false
  name                          = "${local.cluster_name}-cert-manager"
  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = local.route53_zone_arns_or_wildcard

  # See CONTRIBUTING.md "IRSA module convention".
  policy_name = var.iam_policy_name_use_cluster_prefix ? "${local.cluster_name}-Cert_Manager" : null

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["cert-manager:cert-manager"]
    }
  }
}

# ========================== velero ========================================

module "velero_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.5"

  use_name_prefix       = false
  name                  = "${local.cluster_name}-velero"
  attach_velero_policy  = true
  velero_s3_bucket_arns = [aws_s3_bucket.velero.arn]

  # See CONTRIBUTING.md "IRSA module convention".
  policy_name = var.iam_policy_name_use_cluster_prefix ? "${local.cluster_name}-Velero" : null

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["velero:velero-server"]
    }
  }
}

# The upstream `attach_velero_policy = true` template assumes the bucket
# uses SSE-S3 (AES256) and DOES NOT include KMS permissions. Our S3 buckets
# are encrypted with SSE-KMS via the customer-managed `s3_data` key
# (see s3.tf), so Velero's `s3:PutObject` calls trigger
# `kms:GenerateDataKey` from S3 against the caller identity. Without this
# inline policy, every backup fails with `AccessDenied` on KMS — which is
# exactly the failure mode observed in cortex prd before this fix
# (6 days of `velero_backup_failure_total` firing, all errors=14).
# Permissions are scoped to the single key by ARN; no `kms:*` or wildcard.
resource "aws_iam_role_policy" "velero_kms" {
  name = "velero-kms"
  role = module.velero_irsa.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKMSForVeleroBucketEncryption"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = aws_kms_key.s3_data.arn
      },
    ]
  })
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
    # Bucket-wide access: the loki chart (6.54) does not support a global
    # object-key prefix, so objects land at bucket root. Loki + mimir share
    # the observability bucket and each has full access. Narrowing to a
    # per-component prefix would require provisioning separate buckets
    # (tracked as a follow-up if isolation becomes a hard requirement).
    resources = [
      aws_s3_bucket.observability.arn,
      "${aws_s3_bucket.observability.arn}/*",
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
    # See comment on loki_s3 — bucket-wide access, shared with loki.
    resources = [
      aws_s3_bucket.observability.arn,
      "${aws_s3_bucket.observability.arn}/*",
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

# ========================== tempo =========================================
# Tempo's S3 backend uses the thanos-io/objstore client, which picks up
# IRSA credentials via the AWS SDK default chain (AWS_ROLE_ARN +
# AWS_WEB_IDENTITY_TOKEN_FILE injected by the EKS pod-identity webhook
# when the SA carries the role-arn annotation). No static keys needed.

data "aws_iam_policy_document" "tempo_trust" {
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
      values   = ["system:serviceaccount:grafana:grafana-tempo"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "tempo_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    # See comment on loki_s3 — bucket-wide access, shared with loki + mimir.
    # Each component lands at its own top-level prefix (loki: fake/, mimir:
    # blocks/+ruler/+alertmanager/, tempo: single-tenant/).
    resources = [
      aws_s3_bucket.observability.arn,
      "${aws_s3_bucket.observability.arn}/*",
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

resource "aws_iam_role" "tempo" {
  name               = "${local.cluster_name}-tempo"
  assume_role_policy = data.aws_iam_policy_document.tempo_trust.json
}

resource "aws_iam_role_policy" "tempo_s3" {
  name   = "${local.cluster_name}-tempo-s3"
  role   = aws_iam_role.tempo.id
  policy = data.aws_iam_policy_document.tempo_s3.json
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
