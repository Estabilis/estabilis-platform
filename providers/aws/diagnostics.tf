# ---------------------------------------------------------------------------
# Diagnostics
#
# EKS control-plane logs are already published to CloudWatch by the EKS
# module (see eks.tf — cluster_enabled_log_types). This file adds the
# Container Insights opt-in when container_insights_enabled = true. Logs
# and metrics flow into a dedicated CloudWatch log group; the cost is
# ~$2/node/mo (EKS charges both per-cluster and per-node).
#
# Container Insights is OFF by default — the platform ships Alloy + Mimir
# + Loki via the bootstrap chart, which is more cost-effective at scale.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "container_insights" {
  count = var.diagnostics_enabled && var.container_insights_enabled ? 1 : 0

  name              = "/aws/eks/${local.cluster_name}/application"
  retention_in_days = var.cluster_log_retention_days
  kms_key_id        = aws_kms_key.s3_data.arn
}

# The Container Insights addon itself is managed as an EKS addon named
# "amazon-cloudwatch-observability". When enabled, operators should extend
# var.cluster_addons to include it (keeps the addon lifecycle with the
# other cluster addons — single source of truth).
#
# Example override in client tfvars:
#   cluster_addons = {
#     amazon-cloudwatch-observability = { most_recent = true }
#     ... other defaults ...
#   }
