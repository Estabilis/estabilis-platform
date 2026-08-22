# ---------------------------------------------------------------------------
# Platform component storage
#
# Each bucket belongs to the component that uses it, not to the cluster, and is
# created when that component is turned on — not before. A bucket for a
# component nobody enabled is an orphan with a scoped key attached to it.
#
# The code lives here because only Terraform can create a Spaces bucket; ArgoCD
# cannot. What changes with the component is the flag, not the location.
#
# Every one of these goes through modules/spaces-bucket-with-key so the bucket
# and its key cannot drift apart. See that module for why the two are bound.
#
# On cost: DigitalOcean bills Spaces as ONE account-level subscription
# (USD 5/month covering 250 GB and 1 TB of transfer), not per bucket — checked
# against an invoice showing a single "Spaces Subscription" line for fourteen
# buckets. So an extra empty bucket is close to free. The reason to keep these
# off is lifecycle, not price.
# ---------------------------------------------------------------------------

module "observability_storage" {
  source = "../../modules/spaces-bucket-with-key"

  enabled = var.observability_bucket_enabled
  name    = "${var.name_prefix}-observability-${local.env_code}-${local._bucket_suffix}"
  region  = local.spaces_region_effective

  # Loki, Mimir and Tempo write chunks they manage themselves; versioning would
  # multiply that storage for no recoverable benefit.
  versioning_enabled = false
}

module "velero_storage" {
  source = "../../modules/spaces-bucket-with-key"

  enabled = var.velero_bucket_enabled
  name    = "${var.name_prefix}-velero-${local.env_code}-${local._bucket_suffix}"
  region  = local.spaces_region_effective

  versioning_enabled     = true
  expire_noncurrent_days = var.velero_noncurrent_retention_days
}

module "cnpg_storage" {
  source = "../../modules/spaces-bucket-with-key"

  # Off by default and likely to stay that way on DigitalOcean: this provider
  # points Grafana at a managed PostgreSQL rather than running CNPG, so the
  # cnpg-cluster component does not render here at all.
  enabled = var.cnpg_bucket_enabled
  name    = "${var.name_prefix}-cnpg-${local.env_code}-${local._bucket_suffix}"
  region  = local.spaces_region_effective

  versioning_enabled = true
}

# Vault's Raft snapshots. The AWS provider has carried an equivalent since the
# Vault work landed there; this is the DigitalOcean side of it.
#
# Off by default like every other component bucket, and for a sharper reason
# here: a snapshot of a Vault that nobody has initialised is an empty object in
# a bucket with a key attached. Turn it on with Vault, not before.
#
# VERSIONING IS ON, unlike observability. A Raft snapshot is the only copy of
# the platform's secrets that exists outside the cluster, and the failure it
# guards against is a bad snapshot overwriting a good one — a corrupted or
# truncated upload replacing the last known-good backup with itself. Object
# storage cannot tell those apart; versions can.
#
# What this bucket does NOT protect against is losing the unseal key. Snapshots
# are encrypted under Vault's root key, which is wrapped by the cloud KMS key —
# destroy that and every version in here becomes ciphertext nobody can read.
# See the seal configuration in the deployment that owns it.
module "vault_backup_storage" {
  source = "../../modules/spaces-bucket-with-key"

  enabled = var.vault_backup_bucket_enabled
  name    = "${var.name_prefix}-vault-backup-${local.env_code}-${local._bucket_suffix}"
  region  = local.spaces_region_effective

  versioning_enabled = true

  # Snapshots are small and taken often. Without expiry the bucket grows
  # forever, and old versions of a rotated snapshot are worth nothing after the
  # window in which you would have noticed the corruption.
  expire_noncurrent_days = var.vault_backup_noncurrent_retention_days
}
