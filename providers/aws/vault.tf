# =============================================================================
# HashiCorp Vault — AWS infrastructure (auto-unseal + Raft snapshot backup)
# =============================================================================
# Toggle: var.vault_enabled. When false, NO resources are created — clean
# teardown via `terraform apply` with vault_enabled=false destroys
# everything provisioned here (no prevent_destroy, no purge protection
# blockers).
#
# Components provisioned (when enabled):
#   - Dedicated KMS key for auto-unseal (NOT the cluster envelope key —
#     scope isolation; rotating one does not trigger re-encryption of the
#     other). 7-day deletion window keeps teardown clean.
#   - S3 bucket for Raft snapshot backups (versioned, KMS-encrypted via
#     s3_data, lifecycle expires snapshots after var.vault_backup_retention_days,
#     force_destroy = true so terraform destroy works even with content).
#   - IRSA role for the vault ServiceAccount with least-privilege policy:
#       kms:Encrypt / Decrypt / DescribeKey on the unseal key
#       s3:PutObject / GetObject on the backup bucket
#       s3:ListBucket on the backup bucket
#
# Outputs feed into the platform-infrastructure-sensitive Secret consumed
# by the Vault Application's helm.parameters (see
# bootstrap/platform-root/templates/vault.yaml).
#
# Bootstrap (auth methods, policies, KV mount) is intentionally NOT here —
# operator runs `vault operator init` manually after the chart deploys, then
# follows downstream-specific bootstrap procedures. See ADR / runbook (TBD).
# =============================================================================

# --- KMS key for auto-unseal ---

resource "aws_kms_key" "vault" {
  count = var.vault_enabled ? 1 : 0

  description             = "Vault auto-unseal key for ${local.cluster_name}"
  enable_key_rotation     = true
  deletion_window_in_days = var.vault_kms_deletion_window_days

}

resource "aws_kms_alias" "vault" {
  count = var.vault_enabled ? 1 : 0

  name          = "alias/${local.cluster_name}-vault-unseal"
  target_key_id = aws_kms_key.vault[0].key_id
}

# --- S3 bucket for Raft snapshot backups ---

resource "aws_s3_bucket" "vault_backup" {
  count = var.vault_enabled ? 1 : 0

  bucket        = "${local.cluster_name}-vault-backup"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "vault_backup" {
  count = var.vault_enabled ? 1 : 0

  bucket = aws_s3_bucket.vault_backup[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_backup" {
  count = var.vault_enabled ? 1 : 0

  bucket = aws_s3_bucket.vault_backup[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "vault_backup" {
  count = var.vault_enabled ? 1 : 0

  bucket = aws_s3_bucket.vault_backup[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "vault_backup" {
  count = var.vault_enabled ? 1 : 0

  bucket = aws_s3_bucket.vault_backup[0].id

  rule {
    id     = "expire-old-snapshots"
    status = "Enabled"

    filter {}

    expiration {
      days = var.vault_backup_retention_days
    }
  }
}

# --- IRSA for Vault ---
# Grants the vault ServiceAccount access to KMS (auto-unseal) and S3
# (snapshot backup destination, even though the CronJob is deferred to a
# follow-up — provisioning the role now means the eventual backup CronJob
# needs no IAM change).

module "vault_irsa" {
  count = var.vault_enabled ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"

  role_name = "${local.cluster_name}-vault"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["vault:vault"]
    }
  }
}

resource "aws_iam_role_policy" "vault" {
  count = var.vault_enabled ? 1 : 0

  name = "${local.cluster_name}-vault"
  role = module.vault_irsa[0].iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VaultAutoUnseal"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
        ]
        Resource = aws_kms_key.vault[0].arn
      },
      {
        Sid    = "VaultBackupReadWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
        ]
        Resource = "${aws_s3_bucket.vault_backup[0].arn}/*"
      },
      {
        Sid      = "VaultBackupListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.vault_backup[0].arn
      },
    ]
  })
}
