# ---------------------------------------------------------------------------
# KMS customer-managed keys
#
# Three separate keys for blast-radius isolation:
#   - cluster_secrets: EKS envelope encryption for Kubernetes Secrets
#     (different scope than platform_secrets — compromised K8s API access
#      should not give cleartext access to tfstate or S3 data).
#   - platform_secrets: Secrets Manager entries + DynamoDB lock + tfstate
#     bucket (Terraform-managed secrets at rest).
#   - s3_data: observability, velero, cost-export, flow-logs buckets.
#     High-volume, log-tier data — separated so its rotation does not
#     trigger re-encryption of the (smaller) platform_secrets scope.
#
# Rotation is annual (AWS native). Deletion waits the configured window
# (max 30 days) to allow human override of accidental scheduling.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "cluster_secrets" {
  description             = "EKS envelope encryption for ${local.cluster_name} Kubernetes Secrets"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = var.kms_enable_rotation
}

resource "aws_kms_alias" "cluster_secrets" {
  name          = "alias/${local.cluster_name}-cluster-secrets"
  target_key_id = aws_kms_key.cluster_secrets.key_id
}

resource "aws_kms_key" "platform_secrets" {
  description             = "Platform secrets at rest: Secrets Manager, tfstate S3, DynamoDB lock (${local.cluster_name})"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = var.kms_enable_rotation

  # Allow Secrets Manager, S3, and DynamoDB service principals to use the
  # key when accessed through these services. The caller still needs IAM
  # permissions — this only authorizes the service-principal side of the
  # KMS grant.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowAWSServicesUsage"
        Effect = "Allow"
        Principal = {
          Service = [
            "secretsmanager.amazonaws.com",
            "s3.amazonaws.com",
            "dynamodb.amazonaws.com",
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "secretsmanager.${var.region}.amazonaws.com",
              "s3.${var.region}.amazonaws.com",
              "dynamodb.${var.region}.amazonaws.com",
            ]
          }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "platform_secrets" {
  name          = "alias/${local.cluster_name}-platform-secrets"
  target_key_id = aws_kms_key.platform_secrets.key_id
}

resource "aws_kms_key" "s3_data" {
  description             = "S3 data-tier encryption: observability, velero, cost-export, flow-logs (${local.cluster_name})"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = var.kms_enable_rotation

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowS3Usage"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.region}.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "s3_data" {
  name          = "alias/${local.cluster_name}-s3-data"
  target_key_id = aws_kms_key.s3_data.key_id
}

# ---------------------------------------------------------------------------
# EBS encryption-by-default at the region level.
# Applies to all future EBS volumes in the region — including ones created
# outside of this Terraform config (RDS, manual snapshots, etc.). Idempotent
# and account-wide, so the toggle is off by default to avoid surprising
# operators sharing the account. Flip on for production accounts.
# ---------------------------------------------------------------------------

resource "aws_ebs_encryption_by_default" "this" {
  count   = var.ebs_encryption_by_default_enabled ? 1 : 0
  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  count   = var.ebs_encryption_by_default_enabled ? 1 : 0
  key_arn = aws_kms_key.s3_data.arn

  depends_on = [aws_ebs_encryption_by_default.this]
}
