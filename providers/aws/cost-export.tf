# ---------------------------------------------------------------------------
# AWS Cost and Usage Report (CUR) — consumed by OpenCost
#
# Constraints (CUR v1 / aws_cur_report_definition):
#   1. The CUR API is only available in us-east-1. The API call must use a
#      provider pinned to us-east-1 (see provider "aws.cur" alias below).
#   2. The destination S3 bucket MUST be in us-east-1 too — the CUR billing
#      service writes reports directly there, and buckets in other regions
#      are rejected with InvalidParameterException.
#   3. Only one CUR report per granularity type may exist per account.
#      Creating a second conflicts with the first. Operators in
#      multi-deployment accounts should set cost_export_enabled = true on
#      ONE deployment and share the bucket via OpenCost config in the others.
#
# Everything in this file (bucket + its accessory resources + CUR definition
# + OpenCost IRSA read path) uses provider = aws.cur so the bucket lands in
# us-east-1 regardless of var.region.
# ---------------------------------------------------------------------------

provider "aws" {
  alias   = "cur"
  region  = "us-east-1"
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = local.tags
  }
}

locals {
  cur_report_name = length(var.cost_export_report_name) > 0 ? var.cost_export_report_name : "${var.name_prefix}-${var.deployment_id}"
  cur_bucket_name = "${var.name_prefix}-cur-${local.env_code}-${random_string.bucket_suffix.result}"
}

# ---------------------------------------------------------------------------
# CUR destination bucket — provisioned in us-east-1 via aws.cur alias.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "cur" {
  count    = var.cost_export_enabled ? 1 : 0
  provider = aws.cur

  bucket        = local.cur_bucket_name
  force_destroy = var.s3_force_destroy
}

resource "aws_s3_bucket_versioning" "cur" {
  count    = var.cost_export_enabled && var.s3_versioning_enabled ? 1 : 0
  provider = aws.cur
  bucket   = aws_s3_bucket.cur[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cur" {
  count    = var.cost_export_enabled ? 1 : 0
  provider = aws.cur
  bucket   = aws_s3_bucket.cur[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    # CUR service cannot encrypt using a customer-managed KMS key it does
    # not have explicit kms:GenerateDataKey permission on. SSE-S3 (AES256)
    # is the AWS-documented default for CUR buckets.
  }
}

resource "aws_s3_bucket_public_access_block" "cur" {
  count    = var.cost_export_enabled ? 1 : 0
  provider = aws.cur
  bucket   = aws_s3_bucket.cur[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cur" {
  count    = var.cost_export_enabled ? 1 : 0
  provider = aws.cur
  bucket   = aws_s3_bucket.cur[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# CUR requires specific bucket policy granting the billing service permission
# to write. Documented at:
# https://docs.aws.amazon.com/cur/latest/userguide/cur-s3.html
resource "aws_s3_bucket_policy" "cur" {
  count    = var.cost_export_enabled ? 1 : 0
  provider = aws.cur
  bucket   = aws_s3_bucket.cur[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBillingReports"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
        ]
        Resource = aws_s3_bucket.cur[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          StringLike = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
          }
        }
      },
      {
        Sid       = "AllowBillingReportsWrite"
        Effect    = "Allow"
        Principal = { Service = "billingreports.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cur[0].arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          StringLike = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cur[0].arn,
          "${aws_s3_bucket.cur[0].arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cur]
}

# ---------------------------------------------------------------------------
# CUR report itself — API only available in us-east-1, and writes to the
# bucket above (also us-east-1). s3_region is hardcoded since CUR v1 does
# not support non-us-east-1 buckets.
# ---------------------------------------------------------------------------

resource "aws_cur_report_definition" "opencost" {
  count    = var.cost_export_enabled ? 1 : 0
  provider = aws.cur

  report_name                = local.cur_report_name
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = aws_s3_bucket.cur[0].id
  s3_region                  = "us-east-1"
  s3_prefix                  = "cur"
  additional_artifacts       = ["ATHENA"]
  refresh_closed_reports     = true
  report_versioning          = "OVERWRITE_REPORT"

  depends_on = [aws_s3_bucket_policy.cur]
}

# ---------------------------------------------------------------------------
# IRSA for OpenCost — read CUR data + query basic pricing APIs.
# Role itself is in the EKS cluster region (IAM is global).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "opencost_trust" {
  count = var.cost_export_enabled ? 1 : 0

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
      values   = ["system:serviceaccount:opencost:opencost"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "opencost_cur" {
  count = var.cost_export_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.cur[0].arn,
      "${aws_s3_bucket.cur[0].arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
      "athena:GetWorkGroup",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "pricing:GetProducts",
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "opencost" {
  count              = var.cost_export_enabled ? 1 : 0
  name               = "${local.cluster_name}-opencost"
  assume_role_policy = data.aws_iam_policy_document.opencost_trust[0].json
}

resource "aws_iam_role_policy" "opencost_cur" {
  count  = var.cost_export_enabled ? 1 : 0
  name   = "${local.cluster_name}-opencost-cur"
  role   = aws_iam_role.opencost[0].id
  policy = data.aws_iam_policy_document.opencost_cur[0].json
}
