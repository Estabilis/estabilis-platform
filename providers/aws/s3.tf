# ---------------------------------------------------------------------------
# Platform S3 buckets — observability (Loki/Mimir), velero, cnpg-backup,
# cost-export.
#
# Every bucket follows the same hardening baseline:
#   - SSE-KMS with aws_kms_key.s3_data
#   - Versioning ON (when s3_versioning_enabled)
#   - Bucket ownership enforced (ACLs disabled)
#   - Block Public Access (all four flags)
#   - TLS-only access policy
#   - Per-bucket lifecycle rules (object expiration)
# ---------------------------------------------------------------------------

# ===========================================================================
# Observability — Loki chunks + Mimir blocks share the same bucket with
# distinct key prefixes (loki/, mimir/). Prefix isolation is enforced by
# the IRSA roles in iam.tf (loki_s3 and mimir_s3 resource ARNs).
# ===========================================================================

resource "aws_s3_bucket" "observability" {
  bucket        = "${var.name_prefix}-obs-${local.env_code}-${random_string.bucket_suffix.result}"
  force_destroy = var.s3_force_destroy
}

resource "aws_s3_bucket_versioning" "observability" {
  count  = var.s3_versioning_enabled ? 1 : 0
  bucket = aws_s3_bucket.observability.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "observability" {
  bucket = aws_s3_bucket.observability.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "observability" {
  bucket = aws_s3_bucket.observability.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "observability" {
  bucket = aws_s3_bucket.observability.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "observability" {
  bucket = aws_s3_bucket.observability.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.observability.arn,
          "${aws_s3_bucket.observability.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.observability]
}

resource "aws_s3_bucket_lifecycle_configuration" "observability" {
  count  = var.s3_observability_lifecycle_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.observability.id

  rule {
    id     = "expire-observability"
    status = "Enabled"

    filter {}

    expiration {
      days = var.s3_observability_lifecycle_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.s3_observability_lifecycle_days
    }
  }
}

# ===========================================================================
# Velero — cluster backups (namespaces, PVs via CSI snapshots)
# ===========================================================================

resource "aws_s3_bucket" "velero" {
  bucket        = "${var.name_prefix}-velero-${local.env_code}-${random_string.bucket_suffix.result}"
  force_destroy = var.s3_force_destroy
}

resource "aws_s3_bucket_versioning" "velero" {
  count  = var.s3_versioning_enabled ? 1 : 0
  bucket = aws_s3_bucket.velero.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket = aws_s3_bucket.velero.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "velero" {
  bucket = aws_s3_bucket.velero.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.velero.arn,
          "${aws_s3_bucket.velero.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.velero]
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  count  = var.s3_velero_lifecycle_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.velero.id

  rule {
    id     = "expire-velero"
    status = "Enabled"

    filter {}

    expiration {
      days = var.s3_velero_lifecycle_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.s3_velero_lifecycle_days
    }
  }
}

# ===========================================================================
# CNPG backup — WAL + base backups. Even though no DB is provisioned in
# Phase 1, the bucket is created so CNPG clusters defined downstream can
# back up immediately without an infra change.
# ===========================================================================

resource "aws_s3_bucket" "cnpg_backup" {
  bucket        = "${var.name_prefix}-cnpg-${local.env_code}-${random_string.bucket_suffix.result}"
  force_destroy = var.s3_force_destroy
}

resource "aws_s3_bucket_versioning" "cnpg_backup" {
  count  = var.s3_versioning_enabled ? 1 : 0
  bucket = aws_s3_bucket.cnpg_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cnpg_backup" {
  bucket = aws_s3_bucket.cnpg_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cnpg_backup" {
  bucket = aws_s3_bucket.cnpg_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cnpg_backup" {
  bucket = aws_s3_bucket.cnpg_backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "cnpg_backup" {
  bucket = aws_s3_bucket.cnpg_backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cnpg_backup.arn,
          "${aws_s3_bucket.cnpg_backup.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cnpg_backup]
}

resource "aws_s3_bucket_lifecycle_configuration" "cnpg_backup" {
  bucket = aws_s3_bucket.cnpg_backup.id

  rule {
    id     = "expire-cnpg"
    status = "Enabled"

    filter {}

    expiration {
      days = var.cnpg_backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.cnpg_backup_retention_days
    }
  }
}
