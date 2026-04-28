# ---------------------------------------------------------------------------
# Fargate pod logging — stdout/stderr → CloudWatch via the built-in
# Fluent Bit agent embedded in the EKS Fargate runtime.
#
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html
#
# Three pieces required for Fargate pod logs to ship:
#   1. `aws-observability` namespace with label `aws-observability=enabled`
#   2. `aws-logging` ConfigMap inside it (Fluent Bit OUTPUT config)
#   3. CloudWatch Logs write permission on each Fargate profile pod
#      execution role
#
# Without these, Fargate pods silently drop stdout/stderr and emit a
# `LoggingDisabled` warning event ("aws-logging configmap was not found").
# Log group `/aws/eks/<cluster>/fargate` lands the per-stream logs.
#
# Independent from the EKS cluster control-plane logs configured via
# `enabled_log_types` (those go to `/aws/eks/<cluster>/cluster`).
#
# Mirrors the legacy `cortex-eks-prod` pattern (security.tf:43-105) that
# has been running in production for over a year.
# ---------------------------------------------------------------------------

locals {
  # Self-disables when no Fargate profiles exist (defensive — our platform
  # always provisions at least `kube-system`, but operators with custom
  # `autoscaler = "none"` setups might remove it).
  fargate_logging_effective = var.fargate_logging_enabled && length(module.eks.fargate_profiles) > 0

  fargate_log_group_name            = "/aws/eks/${local.cluster_name}/fargate"
  fargate_log_retention_effective   = var.fargate_log_retention_days != null ? var.fargate_log_retention_days : var.cluster_log_retention_days
  fargate_log_kms_key_arn_effective = var.fargate_log_kms_key_arn != "" ? var.fargate_log_kms_key_arn : aws_kms_key.s3_data.arn
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "fargate" {
  count = local.fargate_logging_effective ? 1 : 0

  name              = local.fargate_log_group_name
  retention_in_days = local.fargate_log_retention_effective
  kms_key_id        = local.fargate_log_kms_key_arn_effective
}

# ---------------------------------------------------------------------------
# aws-observability namespace + aws-logging ConfigMap
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "aws_observability" {
  count = local.fargate_logging_effective ? 1 : 0

  metadata {
    name = "aws-observability"
    labels = {
      "aws-observability" = "enabled"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

resource "kubernetes_config_map_v1" "aws_logging" {
  count = local.fargate_logging_effective ? 1 : 0

  metadata {
    name      = "aws-logging"
    namespace = kubernetes_namespace_v1.aws_observability[0].metadata[0].name
  }

  # Fluent Bit config. Operators add filters via var.fargate_log_filters
  # (concatenated after [OUTPUT]). Output goes to the log group above with
  # `auto_create_group = true` as a defensive fallback (the resource above
  # creates it anyway, but Fluent Bit creates if missing).
  data = {
    "flb_log_cw"  = "true"
    "output.conf" = <<-EOT
      [OUTPUT]
          Name cloudwatch_logs
          Match *
          region ${var.region}
          log_group_name ${local.fargate_log_group_name}
          log_stream_prefix fargate-
          auto_create_group true
      ${var.fargate_log_filters}
    EOT
  }

  depends_on = [aws_cloudwatch_log_group.fargate]
}

# ---------------------------------------------------------------------------
# IAM policy on each Fargate profile pod execution role.
#
# The EKS module creates one role per Fargate profile. Without this policy
# attached, Fluent Bit boots but PutLogEvents fails with AccessDenied
# (silent — only visible in Fargate runtime logs you can't see).
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "fargate_logging" {
  for_each = local.fargate_logging_effective ? module.eks.fargate_profiles : {}

  name = "${local.cluster_name}-fargate-logging-${each.key}"
  role = each.value.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
      ]
      Resource = "arn:${data.aws_partition.current.partition}:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.fargate_log_group_name}:*"
    }]
  })
}
