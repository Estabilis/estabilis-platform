# ---------------------------------------------------------------------------
# Terraform backend — two-phase bootstrap (same pattern as the Azure provider)
#
#   Phase 1 — local state. Leave the backend block commented out, run
#             `terraform init` and `terraform apply -target=aws_s3_bucket.tfstate
#             -target=aws_s3_bucket_versioning.tfstate ...` to provision the
#             state bucket + DynamoDB lock table (see tfstate.tf).
#
#   Phase 2 — remote state. Uncomment the block below, fill in the bucket
#             name and lock table from tfstate.tf outputs, and run
#             `terraform init -migrate-state`. Subsequent runs use S3.
#
# The bucket name must be globally unique across all AWS accounts. The
# {name_prefix}-tfstate-{bucket_suffix} naming in tfstate.tf guarantees
# uniqueness via random_string.bucket_suffix.
# ---------------------------------------------------------------------------

# terraform {
#   backend "s3" {
#     bucket         = "<filled-after-phase-1>"           # aws_s3_bucket.tfstate.id
#     key            = "platform/terraform.tfstate"
#     region         = "<aws-region>"                     # var.region
#     dynamodb_table = "<filled-after-phase-1>"           # aws_dynamodb_table.tfstate_lock.id
#     encrypt        = true
#     kms_key_id     = "<filled-after-phase-1>"           # aws_kms_key.platform_secrets.arn
#   }
# }
