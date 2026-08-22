# ---------------------------------------------------------------------------
# Outputs — surface what the operator and downstream tooling need, and
# nothing that carries a credential.
#
# Deliberately absent: kube_config, its token, and the cluster CA. The AWS
# provider exports cluster_certificate_authority_data behind `sensitive`;
# here even that is withheld, because on DigitalOcean the CA travels inside
# the same kube_config attribute as a live bearer token and the two are easy
# to copy together. `kubeconfig_command` gives an operator the same access
# through doctl, which mints a fresh credential instead of echoing one.
#
# This keeps credentials out of the terminal, out of CI logs, and out of any
# `terraform output -json` artifact. It does NOT keep them out of the state
# file: digitalocean_kubernetes_cluster materialises kube_config there
# regardless. Treat the state as a secret — that is the argument for moving
# to the encrypted remote backend in phase 2.
# ---------------------------------------------------------------------------

# ===========================================================================
# Identity
# ===========================================================================

output "region" {
  description = "DigitalOcean region slug."
  value       = var.region
}

output "environment" {
  description = "Resolved environment code (prod normalises to prd)."
  value       = local.env_code
}

output "deployment_id" {
  description = "Deployment key in the client GitOps repo (platforms/{deployment_id}/)."
  value       = var.deployment_id
}

output "platform_version" {
  description = "Version of the Estabilis Platform upstream module that produced this deployment."
  value       = local.module_version
}

# ===========================================================================
# DOKS cluster
# ===========================================================================

output "cluster_id" {
  description = "DOKS cluster UUID."
  value       = digitalocean_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "DOKS cluster name."
  value       = digitalocean_kubernetes_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = digitalocean_kubernetes_cluster.this.endpoint
}

output "cluster_version" {
  description = "Resolved DOKS version slug running on the control plane."
  value       = digitalocean_kubernetes_cluster.this.version
}

output "cluster_urn" {
  description = "DigitalOcean URN for the cluster, for project assignment and tagging."
  value       = digitalocean_kubernetes_cluster.this.urn
}

output "cluster_ipv4_address" {
  description = "Public IPv4 of the control plane, when DigitalOcean assigns one."
  value       = digitalocean_kubernetes_cluster.this.ipv4_address
}

output "kubeconfig_command" {
  description = "Command to populate ~/.kube/config for this cluster. Mints a fresh credential rather than reusing the one in state."
  value       = "doctl kubernetes cluster kubeconfig save ${digitalocean_kubernetes_cluster.this.id}"
}

# ===========================================================================
# API server exposure — what the firewall actually ended up allowing
# ===========================================================================

output "control_plane_firewall_enabled" {
  description = "Whether the API server allowlist is in force."
  value       = var.control_plane_firewall_enabled
}

output "authorized_ip_ranges_effective" {
  description = "CIDRs the API server accepts, including the operator address when autodetected. Empty with the firewall enabled means the check in main.tf was bypassed via allow_public_api_endpoint."
  value       = local.authorized_ips
}

# ===========================================================================
# Networking
# ===========================================================================

output "vpc_uuid" {
  description = "UUID of the VPC hosting the cluster, whether created here or pre-existing."
  value       = local.vpc_uuid_effective
}

output "vpc_ip_range" {
  description = "CIDR of the VPC — the DigitalOcean-assigned range when vpc_ip_range was left null."
  value       = local.vpc_ip_range_effective
}

output "cluster_subnet" {
  description = "Pod CIDR in use."
  value       = digitalocean_kubernetes_cluster.this.cluster_subnet
}

output "service_subnet" {
  description = "Service ClusterIP CIDR in use."
  value       = digitalocean_kubernetes_cluster.this.service_subnet
}

# ===========================================================================
# Node pools
# ===========================================================================

output "default_node_pool_id" {
  description = "ID of the cluster's built-in node pool."
  value       = digitalocean_kubernetes_cluster.this.node_pool[0].id
}

output "additional_node_pool_ids" {
  description = "IDs of the standalone node pools, keyed by pool name."
  value       = { for k, v in digitalocean_kubernetes_node_pool.this : k => v.id }
}

# ===========================================================================
# Tagging
# ===========================================================================

output "caf_tags" {
  description = "Full-fidelity CAF tag map, in the same key-value shape the AWS and Azure providers build. This is the set the platform ConfigMap should publish."
  value       = local.tags
}

output "do_tags_applied" {
  description = "Flat `key:value` strings actually attached to DigitalOcean resources."
  value       = local.do_tags
}

output "do_tags_dropped" {
  description = "CAF keys that did not survive the DigitalOcean tag projection because their value falls outside the permitted character set (URLs, dotted semver, dotted SLA). They remain in caf_tags."
  value       = local.do_tags_dropped
}

# ===========================================================================
# Terraform state backend
# ===========================================================================

output "tfstate_bucket_name" {
  description = "Spaces bucket holding Terraform state, whether or not it is still under management."
  # local.tfstate_bucket_name rather than the resource attribute: after the
  # bucket is released from management (README > State) the resource has count
  # 0 and reading `one(...[*].name)` returns null. That broke the documented
  # decommissioning procedure at its first step, which asks for exactly this
  # value in order to know what to empty and delete. The local resolves from
  # the override in that case, so the answer survives the release.
  value = local.tfstate_bucket_name
}

output "tfstate_bucket_region" {
  description = "Region of the state bucket."
  value       = one(digitalocean_spaces_bucket.tfstate[*].region)
}

output "tfstate_bucket_endpoint" {
  description = "S3-compatible endpoint for the state bucket."
  value       = one(digitalocean_spaces_bucket.tfstate[*].endpoint)
}

output "tfstate_key_access_id" {
  description = "Access key ID of the scoped Spaces key for the backend. The matching secret is in the state; read it with `terraform output -raw tfstate_key_secret`."
  value       = one(digitalocean_spaces_key.tfstate[*].access_key)
}

output "tfstate_key_secret" {
  description = "Secret for the scoped Spaces key. Export as SPACES_SECRET_ACCESS_KEY (or AWS_SECRET_ACCESS_KEY for the s3 backend) before `init -migrate-state`."
  value       = one(digitalocean_spaces_key.tfstate[*].secret_key)
  sensitive   = true
}

output "tfstate_backend_config" {
  description = "The backend block to paste into backend.tf, rendered with this deployment's values. Uncomment it there AFTER the first apply, then run `terraform init -migrate-state`."
  value       = local.tfstate_backend_config
}

# ===========================================================================
# DigitalOcean Project
# ===========================================================================

output "project_id" {
  description = "UUID of the project holding this deployment. Null when project_mode = \"none\" (resources sit in the account default)."
  value       = local.project_id_effective
}

output "project_name" {
  description = "Name of the project holding this deployment."
  value       = var.project_mode == "create" ? local.project_name : one(data.digitalocean_project.existing[*].name)
}

output "project_resource_urns" {
  description = "Resource URNs attached to the project. VPCs are absent because DigitalOcean projects do not accept them."
  value       = var.project_mode != "none" ? local.project_resource_urns : []
}

output "tfstate_bootstrap_key_access_id" {
  description = "Access key ID of the TEMPORARY account-wide bootstrap key. Export as SPACES_ACCESS_KEY_ID for the apply that creates the bucket, then set tfstate_bootstrap_key_enabled = false to destroy it."
  value       = one(digitalocean_spaces_key.bootstrap[*].access_key)
}

output "tfstate_bootstrap_key_secret" {
  description = "Secret of the temporary bootstrap key. Export as SPACES_SECRET_ACCESS_KEY."
  value       = one(digitalocean_spaces_key.bootstrap[*].secret_key)
  sensitive   = true
}

# ===========================================================================
# NAT Gateway
# ===========================================================================

output "nat_gateway_id" {
  description = "VPC NAT Gateway id. Null when nat_gateway_enabled = false."
  value       = one(digitalocean_vpc_nat_gateway.this[*].id)
}

output "nat_gateway_egresses" {
  description = "Public egress addresses of the NAT Gateway — the identity the cluster presents outbound, and what a third party would allowlist."
  value       = one(digitalocean_vpc_nat_gateway.this[*].egresses)
}

# ============================================================================
# Container registry
# ============================================================================

output "registry_name" {
  description = "Name of the container registry, or null when disabled."
  value       = var.registry_enabled ? digitalocean_container_registry.this[0].name : null
}

output "registry_endpoint" {
  description = "Registry endpoint for tagging images, e.g. registry.digitalocean.com/<name>."
  value       = var.registry_enabled ? digitalocean_container_registry.this[0].endpoint : null
}

output "registry_server_url" {
  description = "Registry server URL, for `docker login`."
  value       = var.registry_enabled ? digitalocean_container_registry.this[0].server_url : null
}

output "registry_ci_docker_credentials" {
  description = "Read-write Docker config JSON for CI push. Read with `terraform output -raw` and pipe it straight into its consumer."
  value       = var.registry_enabled && var.registry_ci_credentials_enabled ? digitalocean_container_registry_docker_credentials.ci[0].docker_credentials : null
  sensitive   = true
}

output "registry_pull_docker_credentials" {
  description = "Read-only Docker config JSON, for pulls from outside the cluster."
  value       = var.registry_enabled && var.registry_pull_credentials_enabled ? digitalocean_container_registry_docker_credentials.pull[0].docker_credentials : null
  sensitive   = true
}
