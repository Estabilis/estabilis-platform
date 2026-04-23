# ---------------------------------------------------------------------------
# Terraform state bucket + DynamoDB lock table
#
# Hardening applied (AWS security best practices):
#   - SSE-KMS with a dedicated customer-managed key (kms.tf)
#   - Versioning ON (allows rollback on accidental state corruption)
#   - Block Public Access at bucket level (no ACLs, no policies can override)
#   - Bucket ownership enforced (ACLs disabled — AWS recommendation 2023+)
#   - TLS-only access via resource policy (deny aws:SecureTransport=false)
#   - Optional Object Lock for compliance (s3_tfstate_protect_critical)
#   - Optional cross-region replication (s3_tfstate_replication_enabled)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.name_prefix}-tfstate-${local.env_code}-${random_string.bucket_suffix.result}"

  # s3_tfstate_protect_critical enables Object Lock which must be set on
  # bucket creation (cannot be enabled after).
  object_lock_enabled = var.s3_tfstate_protect_critical

  # Primary safety guard against accidental destroy is force_destroy. With
  # force_destroy = false (default) Terraform refuses to delete a bucket that
  # still has objects — the real tfstate file(s) in the bucket. Flip to true
  # only during controlled teardown (e.g., HML rebuild).
  #
  # lifecycle.prevent_destroy is intentionally NOT set here: Terraform does
  # not support variable-driven prevent_destroy, which would force operators
  # to patch the module cache every time they want to teardown a test
  # deployment. Object Lock + force_destroy=false + (optionally)
  # s3_tfstate_protect_critical=true provide equivalent protection for
  # production use cases.
  force_destroy = var.s3_force_destroy
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.platform_secrets.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# TLS-only policy — deny any request that does not use https. Combined with
# the public access block above this forms the defensive baseline required
# by CIS AWS Foundations Benchmark 2.1.2.
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# Optional Object Lock (governance mode). Prevents accidental or malicious
# deletion of state objects for the configured retention. Equivalent to
# Azure's storage_protect_critical resource lock on tfstate storage.
resource "aws_s3_bucket_object_lock_configuration" "tfstate" {
  count  = var.s3_tfstate_protect_critical ? 1 : 0
  bucket = aws_s3_bucket.tfstate.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 30
    }
  }
}

# Optional cross-region replication for disaster recovery.
resource "aws_iam_role" "tfstate_replication" {
  count = var.s3_tfstate_replication_enabled ? 1 : 0
  name  = "${local.base_name}-tfstate-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "tfstate_replication" {
  count = var.s3_tfstate_replication_enabled ? 1 : 0
  name  = "${local.base_name}-tfstate-replication"
  role  = aws_iam_role.tfstate_replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
        ]
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
        ]
        Resource = "${var.s3_tfstate_replication_destination_bucket_arn}/*"
      },
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "tfstate" {
  count  = var.s3_tfstate_replication_enabled ? 1 : 0
  role   = aws_iam_role.tfstate_replication[0].arn
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = var.s3_tfstate_replication_destination_bucket_arn
      storage_class = "STANDARD"
    }

    delete_marker_replication {
      status = "Enabled"
    }
  }

  depends_on = [aws_s3_bucket_versioning.tfstate]
}

# ---------------------------------------------------------------------------
# DynamoDB table for state locking
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.name_prefix}-tfstate-lock-${local.env_code}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.platform_secrets.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  # Lock table is ephemeral (holds only active terraform lock records).
  # Recreating it is instant. No prevent_destroy so test deployments can
  # tear down cleanly. For production extra safety, rely on the S3 bucket's
  # force_destroy=false and/or Object Lock via s3_tfstate_protect_critical.
}
