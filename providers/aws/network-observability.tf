# ---------------------------------------------------------------------------
# Container Network Observability — Amazon CloudWatch Network Flow Monitor
# (NFM) wired up to the EKS cluster.
#
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/network-observability.html
#
# Network Flow Monitor is a *general* CloudWatch service — `local_resource`
# accepts five types: AWS::EC2::VPC, AWS::EC2::Subnet,
# AWS::EC2::AvailabilityZone, AWS::EC2::Region, AWS::EKS::Cluster. We wire
# the EKS variant only; the upstream supports per-cluster monitoring out
# of the box.
#
# Three things get provisioned when network_observability_enabled = true:
#
#   1. NFM Scope — account+region singleton. A single Scope is shared
#      across every cluster in the same AWS account+region. Operators with
#      multiple clusters per account/region SHOULD set
#      `network_observability_scope_mode = "existing"` on every cluster
#      after the first and pass the existing scope ARN, so we don't duplicate
#      Scopes (NFM bills per Scope).
#
#   2. NFM Monitor — per-cluster, with `local_resource = AWS::EKS::Cluster`
#      pointing at module.eks.cluster_arn. Optionally narrows
#      `remote_resource` for cross-region/cross-VPC tracking.
#
#   3. NFM agent EKS addon (`aws-network-flow-monitoring-agent`, v1.1.0+) +
#      Pod Identity association binding it to a least-privilege IAM role
#      carrying the AWS-managed `CloudWatchNetworkFlowMonitorAgentPublishPolicy`.
#      Pod Identity (rather than IRSA) is preferred per AWS guidance; we
#      use the managed `eks-pod-identity-agent` addon already installed by
#      default.
#
# Cost: NFM is a paid service — see Amazon CloudWatch pricing. Disabled by
# default; enable per-deployment via tfvars.
#
# Regional availability: Limited to regions where Network Flow Monitor is
# supported. The `network_observability_region_check` precondition fails
# loud if the operator enables the feature in an unsupported region.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# IRSA / Pod Identity role for the NFM agent
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "network_flow_monitor_agent_trust" {
  count = var.network_observability_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "network_flow_monitor_agent" {
  count = var.network_observability_enabled ? 1 : 0

  name               = "${local.cluster_name}-nfm-agent"
  description        = "Network Flow Monitor agent (Pod Identity) for cluster ${local.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.network_flow_monitor_agent_trust[0].json
}

resource "aws_iam_role_policy_attachment" "network_flow_monitor_agent_publish" {
  count = var.network_observability_enabled ? 1 : 0

  role       = aws_iam_role.network_flow_monitor_agent[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchNetworkFlowMonitorAgentPublishPolicy"
}

resource "aws_eks_pod_identity_association" "network_flow_monitor_agent" {
  count = var.network_observability_enabled ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = var.network_observability_agent_namespace
  service_account = var.network_observability_agent_service_account
  role_arn        = aws_iam_role.network_flow_monitor_agent[0].arn
}

# ---------------------------------------------------------------------------
# NFM Scope (account+region singleton, optional)
# ---------------------------------------------------------------------------

locals {
  network_observability_scope_create = var.network_observability_enabled && var.network_observability_scope_mode == "create"

  network_observability_scope_arn_effective = (
    var.network_observability_scope_mode == "existing"
    ? var.network_observability_existing_scope_arn
    : (local.network_observability_scope_create ? aws_networkflowmonitor_scope.this[0].scope_arn : "")
  )
}

resource "aws_networkflowmonitor_scope" "this" {
  count = local.network_observability_scope_create ? 1 : 0

  target {
    region = var.region
    target_identifier {
      target_type = "ACCOUNT"
      target_id {
        account_id = data.aws_caller_identity.current.account_id
      }
    }
  }

  tags = {
    Name = "${local.cluster_name}-nfm-scope"
  }
}

# ---------------------------------------------------------------------------
# NFM Monitor — per-cluster
# ---------------------------------------------------------------------------

resource "aws_networkflowmonitor_monitor" "this" {
  count = var.network_observability_enabled ? 1 : 0

  monitor_name = coalesce(var.network_observability_monitor_name, "${local.cluster_name}-monitor")
  scope_arn    = local.network_observability_scope_arn_effective

  local_resource {
    type       = "AWS::EKS::Cluster"
    identifier = module.eks.cluster_arn
  }

  # Single-region default: if the operator passes no overrides, monitor
  # flows that stay within the cluster's region. Operators tracking
  # cross-region traffic should set network_observability_remote_resources
  # explicitly.
  dynamic "remote_resource" {
    for_each = length(var.network_observability_remote_resources) > 0 ? var.network_observability_remote_resources : [
      {
        type       = "AWS::EC2::Region"
        identifier = var.region
      }
    ]
    content {
      type       = remote_resource.value.type
      identifier = remote_resource.value.identifier
    }
  }

  tags = {
    Name = "${local.cluster_name}-nfm-monitor"
  }

  lifecycle {
    precondition {
      condition     = !var.network_observability_enabled || var.network_observability_scope_mode != "existing" || length(var.network_observability_existing_scope_arn) > 0
      error_message = "network_observability_scope_mode = \"existing\" requires network_observability_existing_scope_arn to be a non-empty Scope ARN. Use the output `network_observability_scope_arn` from the cluster that owns the Scope."
    }
  }
}

# ---------------------------------------------------------------------------
# NFM agent EKS addon
#
# Configuration_values is a JSON object with three documented OpenMetrics
# tuning knobs (off by default). Operators wanting to expose Prometheus-style
# metrics from the agent merge their override map into the default via
# var.network_observability_addon_config.
# ---------------------------------------------------------------------------

locals {
  network_observability_addon_default_config = {
    # Match the AWS documentation defaults verbatim. Operators only need
    # to override the keys they care about; merge() keeps the rest.
    OPEN_METRICS         = "off"
    OPEN_METRICS_ADDRESS = "127.0.0.1"
    OPEN_METRICS_PORT    = 80
  }

  network_observability_addon_config_effective = merge(
    local.network_observability_addon_default_config,
    var.network_observability_addon_config,
  )
}

resource "aws_eks_addon" "network_flow_monitor_agent" {
  count = var.network_observability_enabled ? 1 : 0

  cluster_name = module.eks.cluster_name
  addon_name   = "aws-network-flow-monitoring-agent"

  # Pinning by addon_version is left to the operator (var); leaving it null
  # tracks the most recent compatible version for the cluster's Kubernetes
  # minor — same default behavior as the platform addons in eks.tf.
  addon_version = var.network_observability_addon_version

  configuration_values = jsonencode(local.network_observability_addon_config_effective)

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_pod_identity_association.network_flow_monitor_agent,
    aws_networkflowmonitor_monitor.this,
  ]
}
