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

# The observability bucket holds two categories of object with opposing
# needs, and an unfiltered expiration rule cannot tell them apart:
#
#   blocks/ fake/ index/ single-tenant/   time series      -> expire
#   alertmanager/alerts/<tenant>          Alertmanager cfg -> NEVER expire
#   ruler/rules/<tenant>/...              alert rules      -> NEVER expire
#   *_cluster_seed.json                   cluster identity -> NEVER expire
#
# Expiring the configuration breaks alerting SILENTLY: Mimir Alertmanager
# falls back to a default config with no receivers, rules keep evaluating,
# and every notification is discarded without an error or a log line. The
# only reason this stayed hidden is that the mimir-rules and
# mimir-alertmanager-config charts rewrite those objects on every sync,
# resetting the clock before it reaches the expiration window. That is an
# accidental side effect of reconciliation, not a design — any pause (app
# OutOfSync, upgrade, feature gated off) restarts the countdown.
#
# So expiration is scoped to the data prefixes and configuration is simply
# never matched by a rule that deletes a current version. The failure
# direction is deliberate: a new prefix that nobody adds to the list costs
# storage, it does not cost configuration.
#
# Per-prefix days exist because one number cannot serve every component.
# Mimir's compactor_blocks_retention_period defaults to 2160h (90 days)
# while Loki and Tempo retain 720h (30 days). With a single value, S3
# deletes the blocks Mimir still promises to serve — again silently.
locals {
  # prefix => expiration days. The override map wins; otherwise every
  # prefix gets the bucket-wide default.
  s3_observability_prefix_days = {
    for p in var.s3_observability_data_prefixes :
    p => try(var.s3_observability_prefix_lifecycle_days[p], var.s3_observability_lifecycle_days)
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "observability" {
  count  = var.s3_observability_lifecycle_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.observability.id

  # Time series — one rule per data prefix so each component can be given
  # a window that matches its own retention setting.
  dynamic "rule" {
    for_each = local.s3_observability_prefix_days

    content {
      id     = "expire-${trim(replace(rule.key, "/", "-"), "-")}"
      status = "Enabled"

      filter {
        prefix = rule.key
      }

      expiration {
        days = rule.value
      }
    }
  }

  # Non-current versions of ANY object, including configuration. On a
  # versioned bucket the rules above only write a delete marker; this is
  # what reclaims the bytes. It never touches a current version, so the
  # live configuration is safe. `expired_object_delete_marker` clears the
  # markers left behind once their versions are gone — the prd bucket had
  # 2k+ of them accumulated under ruler/.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.s3_observability_lifecycle_days
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  lifecycle {
    precondition {
      condition = length(setsubtract(
        keys(var.s3_observability_prefix_lifecycle_days),
        var.s3_observability_data_prefixes,
      )) == 0
      error_message = join(" ", [
        "s3_observability_prefix_lifecycle_days has keys that are not in",
        "s3_observability_data_prefixes:",
        join(", ", setsubtract(
          keys(var.s3_observability_prefix_lifecycle_days),
          var.s3_observability_data_prefixes,
        )),
        "- an override on a prefix that has no rule is silently ignored,",
        "which is exactly the failure mode this resource exists to prevent.",
        "Prefixes are matched literally and need the trailing slash.",
      ])
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
