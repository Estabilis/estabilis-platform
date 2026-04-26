# ---------------------------------------------------------------------------
# ECR (Elastic Container Registry)
#
# Two ownership models, distinct on purpose:
#
#   1. Platform-managed repos (`var.ecr_repositories`) — declarative.
#      For repositories the platform itself publishes (CLI addons such as
#      the workload-operator image and chart). Lifecycle, scan-on-push,
#      immutability and KMS are enforced by Terraform; drift is detectable.
#
#   2. Workload application repos — CI-owned, auto-created on push.
#      Application images do NOT belong in `var.ecr_repositories`. The CI
#      pipeline (via the OIDC IAM role with `ecr:CreateRepository`) creates
#      the repo on first `docker push`. Adding every workload app to TF
#      would force a `terraform apply` on every onboarding.
#
#   3. Pull-through cache repos — auto-created by ECR on first pull.
#      `aws_ecr_repository_creation_template.pull_through_cache` aligns
#      cache-created repos with platform defaults (KMS + lifecycle).
#      Without it, AWS uses AES256 and no lifecycle.
#
# CI/CD push role (OIDC trust + IAM policy) is added in a follow-up.
# ---------------------------------------------------------------------------

locals {
  # Anonymous public upstreams applied when pull-through cache is enabled
  # but `var.ecr_pull_through_cache_upstreams` is left empty. Docker Hub is
  # opt-in (requires `ecr_dockerhub_credentials_secret_arn` to avoid the
  # 100-pulls/6h anonymous rate limit).
  ecr_default_pt_cache_upstreams = {
    ghcr       = "ghcr.io"
    quay       = "quay.io"
    k8s        = "registry.k8s.io"
    public-ecr = "public.ecr.aws"
  }

  ecr_pt_cache_upstreams = (
    var.ecr_enabled && var.ecr_pull_through_cache_enabled
    ? (length(var.ecr_pull_through_cache_upstreams) > 0
      ? var.ecr_pull_through_cache_upstreams
    : local.ecr_default_pt_cache_upstreams)
    : {}
  )

  ecr_lifecycle_policy_json = var.ecr_lifecycle_untagged_days > 0 ? jsonencode({
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
  }) : null
}

# ---------------------------------------------------------------------------
# Platform-managed repositories (CLI addons, declarative)
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
  policy     = local.ecr_lifecycle_policy_json
}

# ---------------------------------------------------------------------------
# Pull-through cache rules
# ---------------------------------------------------------------------------

resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = local.ecr_pt_cache_upstreams

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value

  # Only the docker-hub upstream supports authenticated pulls. Passing a
  # credential ARN to anonymous upstreams (ghcr, quay, k8s, public-ecr)
  # would error.
  credential_arn = each.key == "docker-hub" && length(var.ecr_dockerhub_credentials_secret_arn) > 0 ? var.ecr_dockerhub_credentials_secret_arn : null
}

# ---------------------------------------------------------------------------
# Repository creation templates — applied when ECR auto-creates a repo for
# pull-through cache. `applied_for` is scoped to PULL_THROUGH_CACHE only;
# operator/CI `docker push` does NOT trigger the template.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository_creation_template" "pull_through_cache" {
  for_each = local.ecr_pt_cache_upstreams

  prefix      = each.key
  description = "KMS + lifecycle for repos under '${each.key}/' created by pull-through cache."
  applied_for = ["PULL_THROUGH_CACHE"]

  # MUTABLE: upstream tags (`:stable`, `:latest`) move; an IMMUTABLE cached
  # repo would refuse re-pulls when the upstream tag is updated.
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.s3_data.arn
  }

  lifecycle_policy = local.ecr_lifecycle_policy_json
}
