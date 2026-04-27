# ---------------------------------------------------------------------------
# Shared locals — centralized here so cross-file dependencies are explicit.
#
# Rule of thumb:
#   - File-local helpers (computation that only one file consumes) live in
#     that file's own locals block.
#   - Values consumed by two or more .tf files live here, so a rename or
#     refactor doesn't silently break references in sibling files.
#
# Locals that currently stay in their origin files:
#   main.tf                  — base_name, cluster_name, tags, env_code,
#                              cluster_endpoint shortcuts, host derivation,
#                              exposures_resolved, authorized_ips, operator_ip
#   vpc.tf                   — vpc_id, vpc_cidr_block, private_subnet_ids,
#                              public_subnet_ids, private_route_table_ids,
#                              azs_available, private_subnet_cidrs, etc.
#   nat-gateway.tf           — nat_gateway_render, nat_gateway_count,
#                              nat_gateway_public_ips
#   eks.tf                   — default_addons, effective_addons,
#                              fargate_profiles_default, eks_access_entries_map
#   vpc-endpoints.tf         — gateway/interface endpoint service maps
#   cost-export.tf           — cur_report_name, cur_bucket_name
#   secrets-manager.tf       — secrets_path_prefix
# ---------------------------------------------------------------------------

locals {
  # Consumed by iam.tf (external_dns_irsa, cert_manager_irsa) — defined here
  # because the resolution logic depends on route53.tf resources, and iam.tf
  # would otherwise silently break if route53.tf renamed the local.
  route53_zone_arns_or_wildcard = (
    var.dns_provider == "route53" && var.route53_zone_mode == "create" ? [aws_route53_zone.platform[0].arn]
    : var.dns_provider == "route53" && var.route53_zone_mode == "existing" ? [data.aws_route53_zone.existing[0].arn]
    : ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/*"]
  )

  # Consumed by iam.tf (workload_operator policy), platform-outputs.tf
  # (ConfigMap + hub cluster secret annotations), and outputs.tf.
  shared_hub_secrets_prefix_effective = length(var.shared_hub_secrets_prefix) > 0 ? var.shared_hub_secrets_prefix : "estabilis/shared/${var.name_prefix}"

  # ---------------------------------------------------------------------------
  # ExternalSecret path resolution — provider-agnostic.
  #
  # The `tier` + `secret_path_template` pair is published as cluster
  # annotations (see platform-outputs.tf, hub-cluster Secret) so client
  # ApplicationSets can inject them into helm parameters. Apps using the
  # Cortex `common-app` chart (>= v0.2.0) consume them to construct the
  # ExternalSecret backend path:
  #
  #   {tier} → derived from environment (prd|prod → "production")
  #   {app}  → Release.Name on render
  #
  # Provider mapping (today only Vault wired; AKV / AWS SM follow the
  # same shape — only the template string changes):
  #
  #   Vault              "secret/data/org/{tier}/{app}"
  #   Azure Key Vault    "{app}-{tier}"   (no slashes allowed in AKV name)
  #   AWS Secrets Manager "estabilis/{tier}/{app}" or any chosen prefix
  #
  # When vault_enabled = false, secret_path_template is empty — the
  # client AppSet sees an empty annotation and the chart's `required`
  # check on `pathTemplate` raises a clear error instead of rendering
  # an invalid path. This matches "fail loud" — no silent best-effort.
  # ---------------------------------------------------------------------------
  bridge_tier                 = contains(["prd", "prod"], var.environment) ? "production" : var.environment
  bridge_secret_path_template = var.vault_enabled ? "secret/data/org/{tier}/{app}" : ""
}
