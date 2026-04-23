# ---------------------------------------------------------------------------
# VPC Flow Logs — security audit + network troubleshooting
#
# Destination: S3 bucket provisioned below with the same hardening applied
# to every platform-owned bucket (SSE-KMS, versioning, ownership enforced,
# TLS-only, lifecycle). Retention controlled by vpc_flow_logs_retention_days
# (aligned with s3_flow_logs_lifecycle_days).
# ---------------------------------------------------------------------------

locals {
  flow_logs_bucket_name = "${var.name_prefix}-flow-logs-${local.env_code}-${random_string.bucket_suffix.result}"
}

resource "aws_s3_bucket" "flow_logs" {
  count = var.vpc_flow_logs_enabled ? 1 : 0

  bucket        = local.flow_logs_bucket_name
  force_destroy = var.s3_force_destroy
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  count  = var.vpc_flow_logs_enabled && var.s3_versioning_enabled ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count  = var.vpc_flow_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count  = var.vpc_flow_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "flow_logs" {
  count  = var.vpc_flow_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  count  = var.vpc_flow_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.flow_logs[0].arn
      },
      {
        # No s3:x-amz-acl condition: BucketOwnerEnforced (set in
        # aws_s3_bucket_ownership_controls above) disables ACLs entirely,
        # so the legacy "bucket-owner-full-control" ACL that flow-logs
        # service used to set no longer applies. The ownership control
        # itself guarantees the bucket owner owns every object.
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.flow_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.flow_logs[0].arn,
          "${aws_s3_bucket.flow_logs[0].arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.flow_logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count  = var.vpc_flow_logs_enabled && var.s3_flow_logs_lifecycle_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "expire-flow-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.s3_flow_logs_lifecycle_days
    }
  }
}

# ---------------------------------------------------------------------------
# Flow Log resource
# ---------------------------------------------------------------------------

resource "aws_flow_log" "platform" {
  count = var.vpc_flow_logs_enabled ? 1 : 0

  log_destination      = aws_s3_bucket.flow_logs[0].arn
  log_destination_type = "s3"
  traffic_type         = var.vpc_flow_logs_traffic_type
  vpc_id               = local.vpc_id

  destination_options {
    file_format        = "parquet"
    per_hour_partition = true
  }

  tags = {
    Name = "flowlog-${local.base_name}"
  }

  depends_on = [aws_s3_bucket_policy.flow_logs]
}
