# ---------------------------------------------------------------------------
# ECR (Elastic Container Registry) — optional.
#
# Provisions:
#   - Per-repository with scan-on-push + immutable tags + lifecycle policy
#   - Optional pull-through cache rules for public upstream registries
#     (Docker Hub, Quay, GHCR, k8s.io, public ECR)
#
# CI/CD push automation (IAM role for pipelines) is intentionally out of
# scope for Phase 1.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = var.ecr_enabled ? toset(var.ecr_repositories) : toset([])

  name                 = each.value
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.s3_data.arn
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.ecr_enabled && var.ecr_lifecycle_untagged_days > 0 ? toset(var.ecr_repositories) : toset([])

  repository = aws_ecr_repository.this[each.value].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after ${var.ecr_lifecycle_untagged_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.ecr_lifecycle_untagged_days
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Pull-through cache
# ---------------------------------------------------------------------------

resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = var.ecr_enabled && var.ecr_pull_through_cache_enabled ? var.ecr_pull_through_cache_upstreams : {}

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value

  # Docker Hub authenticated cache requires a Secrets Manager ARN. Other
  # upstreams (quay, ghcr, k8s, public-ecr) are anonymous.
  credential_arn = each.key == "docker-hub" && length(var.ecr_dockerhub_credentials_secret_arn) > 0 ? var.ecr_dockerhub_credentials_secret_arn : null
}
