# ---------------------------------------------------------------------------
# Outputs — surface everything the operator + downstream tooling need
# without having to read Terraform state directly.
# ---------------------------------------------------------------------------

# ===========================================================================
# Identity
# ===========================================================================

output "account_id" {
  description = "AWS account ID the cluster is provisioned in."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS region."
  value       = var.region
}

# ===========================================================================
# EKS cluster
# ===========================================================================

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the EKS API server."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster (used by IRSA federated trust policies)."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for EKS (used to trust IRSA roles)."
  value       = module.eks.oidc_provider_arn
}

output "kubeconfig_command" {
  description = "Command to populate ~/.kube/config for this cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}${var.aws_profile != "" ? " --profile ${var.aws_profile}" : ""}"
}

# ===========================================================================
# Networking
# ===========================================================================

output "vpc_id" {
  description = "VPC ID hosting the cluster."
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the cluster."
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs (when public_subnets_enabled)."
  value       = local.public_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "Static public IPs of NAT Gateway(s). Add to downstream allowlists that restrict by source IP."
  value       = local.nat_gateway_public_ips
}

# ===========================================================================
# KMS
# ===========================================================================

output "kms_cluster_secrets_arn" {
  description = "ARN of the KMS key used for EKS envelope encryption."
  value       = aws_kms_key.cluster_secrets.arn
}

output "kms_platform_secrets_arn" {
  description = "ARN of the KMS key used for Secrets Manager + DynamoDB lock + tfstate bucket."
  value       = aws_kms_key.platform_secrets.arn
}

output "kms_s3_data_arn" {
  description = "ARN of the KMS key used for observability/velero/cnpg/cost-export/flow-logs buckets."
  value       = aws_kms_key.s3_data.arn
}

# ===========================================================================
# Secrets Manager
# ===========================================================================

output "secrets_path_prefix" {
  description = "Base path prefix for all platform secrets in Secrets Manager (estabilis/{deployment_id})."
  value       = local.secrets_path_prefix
}

output "shared_hub_secrets_path_prefix" {
  description = "Shared Secrets Manager path for hub connection values consumed by workload clusters."
  value       = var.shared_hub_secrets_enabled ? local.shared_hub_secrets_prefix_effective : ""
}

# ===========================================================================
# S3 + storage
# ===========================================================================

output "tfstate_bucket_name" {
  description = "S3 bucket for Terraform state."
  value       = aws_s3_bucket.tfstate.id
}

output "tfstate_lock_table_name" {
  description = "DynamoDB table for Terraform state locking."
  value       = aws_dynamodb_table.tfstate_lock.id
}

output "observability_bucket_name" {
  description = "S3 bucket for Loki chunks + Mimir blocks."
  value       = aws_s3_bucket.observability.id
}

output "velero_backup_bucket_name" {
  description = "S3 bucket for Velero cluster backups."
  value       = aws_s3_bucket.velero.id
}

output "cnpg_backup_bucket_name" {
  description = "S3 bucket for CloudNativePG WAL + base backups."
  value       = aws_s3_bucket.cnpg_backup.id
}

output "flow_logs_bucket_name" {
  description = "S3 bucket for VPC Flow Logs (empty when vpc_flow_logs_enabled = false)."
  value       = var.vpc_flow_logs_enabled ? aws_s3_bucket.flow_logs[0].id : ""
}

# ===========================================================================
# IRSA roles
# ===========================================================================

output "external_secrets_role_arn" {
  description = "IAM role ARN for external-secrets ServiceAccount."
  value       = module.external_secrets_irsa.iam_role_arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN for external-dns ServiceAccount (empty when dns_provider != 'route53')."
  value       = var.dns_provider == "route53" ? module.external_dns_irsa[0].iam_role_arn : ""
}

output "cert_manager_role_arn" {
  description = "IAM role ARN for cert-manager ServiceAccount (empty when dns_provider != 'route53')."
  value       = var.dns_provider == "route53" ? module.cert_manager_irsa[0].iam_role_arn : ""
}

output "loki_role_arn" {
  description = "IAM role ARN for Loki ServiceAccount."
  value       = aws_iam_role.loki.arn
}

output "mimir_role_arn" {
  description = "IAM role ARN for Mimir ServiceAccount."
  value       = aws_iam_role.mimir.arn
}

output "velero_role_arn" {
  description = "IAM role ARN for Velero ServiceAccount."
  value       = module.velero_irsa.iam_role_arn
}

output "cnpg_role_arn" {
  description = "IAM role ARN for CloudNativePG ServiceAccount."
  value       = aws_iam_role.cnpg.arn
}

output "ebs_csi_role_arn" {
  description = "IAM role ARN for EBS CSI Driver addon."
  value       = module.ebs_csi_irsa.iam_role_arn
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller (empty when ingress_controller != 'alb')."
  value       = var.ingress_controller == "alb" ? module.alb_controller_irsa[0].iam_role_arn : ""
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler (empty when autoscaler != 'cluster_autoscaler')."
  value       = var.autoscaler == "cluster_autoscaler" ? module.cluster_autoscaler_irsa[0].iam_role_arn : ""
}

output "workload_operator_role_arn" {
  description = "IAM role ARN for estabilis-workload-operator (empty when shared_hub_secrets_enabled = false)."
  value       = var.shared_hub_secrets_enabled ? aws_iam_role.workload_operator[0].arn : ""
}

output "opencost_role_arn" {
  description = "IAM role ARN for OpenCost (empty when cost_export_enabled = false)."
  value       = var.cost_export_enabled ? aws_iam_role.opencost[0].arn : ""
}

# ===========================================================================
# Karpenter
# ===========================================================================

output "karpenter_queue_name" {
  description = "SQS interruption queue name for Karpenter (empty when autoscaler does not provision Karpenter)."
  value       = contains(["karpenter", "hybrid"], var.autoscaler) ? module.karpenter[0].queue_name : ""
}

output "karpenter_node_iam_role_name" {
  description = "IAM role name used by Karpenter-provisioned nodes (empty when autoscaler does not provision Karpenter)."
  value       = contains(["karpenter", "hybrid"], var.autoscaler) ? module.karpenter[0].node_iam_role_name : ""
}

output "karpenter_controller_role_arn" {
  description = "IAM role ARN of the Karpenter controller (empty when autoscaler does not provision Karpenter)."
  value       = contains(["karpenter", "hybrid"], var.autoscaler) ? module.karpenter[0].iam_role_arn : ""
}

# ===========================================================================
# DNS / TLS
# ===========================================================================

output "route53_zone_id" {
  description = "Route53 public hosted zone ID for var.domain (empty when dns_provider != 'route53')."
  value       = local.route53_zone_id
}

output "route53_zone_name_servers" {
  description = "Name servers of the Route53 zone (only populated when route53_zone_mode = 'create'). Delegate these at your registrar."
  value       = local.route53_zone_name_servers
}

output "acm_wildcard_certificate_arn" {
  description = "ARN of the wildcard ACM certificate (empty when acm_enabled = false)."
  value       = var.acm_enabled ? aws_acm_certificate.wildcard[0].arn : ""
}

# ===========================================================================
# ECR
# ===========================================================================

output "ecr_registry_url" {
  description = "ECR registry URL (account-region base). Empty when ecr_enabled = false."
  value       = var.ecr_enabled ? "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com" : ""
}

output "ecr_repository_urls" {
  description = "Map of platform-managed ECR repository name to URL. Empty when no `ecr_repositories` are declared. Workload app repos created by CI are not in this output."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "ecr_pull_through_cache_prefixes" {
  description = "Map of pull-through cache prefix to upstream URL. Construct cached image refs as `<ecr_registry_url>/<prefix>/<upstream-path>:<tag>` — e.g. `<registry>/k8s/coredns/coredns:v1.11.1` caches `registry.k8s.io/coredns/coredns:v1.11.1`."
  value       = { for k, v in aws_ecr_pull_through_cache_rule.this : k => v.upstream_registry_url }
}

# ===========================================================================
# Cost export
# ===========================================================================

output "cur_report_name" {
  description = "Name of the Cost and Usage Report (empty when cost_export_enabled = false)."
  value       = var.cost_export_enabled ? local.cur_report_name : ""
}

output "cur_bucket_name" {
  description = "S3 bucket for the CUR report (empty when cost_export_enabled = false)."
  value       = var.cost_export_enabled ? aws_s3_bucket.cur[0].id : ""
}

# ===========================================================================
# Exposures — JSON-encoded so client tooling can consume them uniformly.
# ===========================================================================

output "grafana_exposures_json" {
  description = "JSON-encoded Grafana exposures (resolved hosts)."
  value       = jsonencode({ for k, v in local.grafana_exposures_resolved : k => v if v.enabled })
}

output "loki_exposures_json" {
  description = "JSON-encoded Loki exposures (resolved hosts)."
  value       = jsonencode({ for k, v in local.loki_exposures_resolved : k => v if v.enabled })
}

output "mimir_exposures_json" {
  description = "JSON-encoded Mimir exposures (resolved hosts)."
  value       = jsonencode({ for k, v in local.mimir_exposures_resolved : k => v if v.enabled })
}

output "argocd_exposures_json" {
  description = "JSON-encoded ArgoCD exposures (resolved hosts)."
  value       = jsonencode({ for k, v in local.argocd_exposures_resolved : k => v if v.enabled })
}

output "hubble_ui_exposures_json" {
  description = "JSON-encoded Hubble UI exposures (resolved hosts)."
  value       = jsonencode({ for k, v in local.hubble_ui_exposures_resolved : k => v if v.enabled })
}

# --- Vault (v0.27.0+) ---

output "vault_kms_key_id" {
  description = "AWS KMS key ID for Vault auto-unseal. Empty when vault_enabled=false."
  value       = var.vault_enabled ? aws_kms_key.vault[0].key_id : ""
}

output "vault_kms_key_arn" {
  description = "AWS KMS key ARN for Vault auto-unseal. Empty when vault_enabled=false."
  value       = var.vault_enabled ? aws_kms_key.vault[0].arn : ""
}

output "vault_kms_region" {
  description = "AWS region where the Vault unseal KMS key lives."
  value       = var.region
}

output "vault_irsa_role_arn" {
  description = "IRSA role ARN for the vault ServiceAccount. Empty when vault_enabled=false."
  value       = var.vault_enabled ? module.vault_irsa[0].iam_role_arn : ""
}

output "vault_backup_bucket_name" {
  description = "S3 bucket name for Vault Raft snapshot backups. Empty when vault_enabled=false."
  value       = var.vault_enabled ? aws_s3_bucket.vault_backup[0].id : ""
}

output "vault_exposures_json" {
  description = "JSON-encoded Vault exposures (resolved hosts)."
  value       = jsonencode({ for k, v in local.vault_exposures_resolved : k => v if v.enabled })
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

output "default_storage_class_name" {
  description = "Name of the default StorageClass created by this module. Empty when create_default_storage_class is false. Downstream consumers can reference this to pin chart `storageClass` values without hardcoding."
  value       = var.create_default_storage_class ? kubernetes_storage_class_v1.gp3[0].metadata[0].name : ""
}
