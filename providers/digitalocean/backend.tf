# ---------------------------------------------------------------------------
# Terraform backend — Spaces, in two phases
#
# READ THIS BEFORE UNCOMMENTING ANYTHING BELOW.
#
# The bucket that holds the state is created BY THIS MODULE (tfstate.tf). That
# is a circular dependency, and the two-phase bootstrap is how it is broken. It
# cannot be skipped and the order cannot be swapped: a backend has to exist
# before `init` can point Terraform at it, and nothing creates it until the
# first apply has already run.
#
#   PHASE 1 — local state, backend block below stays COMMENTED.
#
#     export DIGITALOCEAN_ACCESS_TOKEN=...
#     export SPACES_ACCESS_KEY_ID=...        # NOT the API token — see below
#     export SPACES_SECRET_ACCESS_KEY=...
#     terraform init
#     terraform apply
#
#   The apply creates the VPC, the DOKS cluster, the state bucket and a Spaces
#   key scoped to that bucket. State is still a local file at this point.
#
#   PHASE 2 — migrate, only AFTER the cluster is up and the apply is green.
#
#     terraform output tfstate_backend_config   # renders the block below, filled in
#     # paste it here, uncomment
#
#     export AWS_ACCESS_KEY_ID=$(terraform output -raw tfstate_key_access_id)
#     export AWS_SECRET_ACCESS_KEY=$(terraform output -raw tfstate_key_secret)
#     terraform init -migrate-state
#     terraform plan          # MUST report "No changes" — that is the proof
#                             # the migrated state matches the live cluster
#
#   Do not migrate before a successful apply. Migrating an empty or partial
#   state means the bucket now holds a state that does not describe the
#   infrastructure, and the next plan proposes to build a second cluster.
#
# ---------------------------------------------------------------------------
# Credentials — two different pairs, and mixing them up is the usual failure
#
#   DIGITALOCEAN_ACCESS_TOKEN  drives the API: cluster, VPC, keys.
#   SPACES_ACCESS_KEY_ID       drives the S3-compatible endpoint: the bucket.
#   SPACES_SECRET_ACCESS_KEY
#
# The s3 backend itself reads AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, so the
# Spaces pair has to be exported under the AWS names for `init` — which is why
# the phase-2 snippet above does exactly that. A Spaces key presented as an API
# token fails with a signature error that says nothing about which credential
# was wrong.
#
# ---------------------------------------------------------------------------
# Spaces is S3-compatible, not S3
#
#   - The skip_* flags are MANDATORY, not hardening preferences. Without them
#     the backend tries to reach AWS STS/IAM and init fails.
#   - `region` is required by the backend and ignored by Spaces. The real
#     location is in `endpoints.s3`.
#   - There is no DynamoDB equivalent. `use_lockfile = true` (Terraform >=
#     1.10) keeps a .tflock object in the bucket and is the ONLY locking
#     available. Confirm it is present before a second person runs apply.
# ---------------------------------------------------------------------------

# Filled in from `terraform output tfstate_backend_config` after the first apply.
# Filled in from `terraform output tfstate_backend_config` after stage 2.
# Filled in from `terraform output tfstate_backend_config` after stage 2.
# Backend commented out for decommissioning (README > Decommissioning, step 1).
# terraform {
#   backend "s3" {
#     bucket = "nsights-tfstate-prd-6wbds0"
#     key    = "platform/terraform.tfstate"
#
#     # Ignored by Spaces, but the s3 backend refuses to initialise without it.
#     region = "us-east-1"
#
#     endpoints = {
#       s3 = "https://nyc3.digitaloceanspaces.com"
#     }
#
#     # Spaces has no DynamoDB equivalent. This is the ONLY locking available.
#     use_lockfile = true
#
#     # Not hardening choices — without these the backend tries to reach AWS
#     # STS/IAM and init fails.
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     skip_region_validation      = true
#     skip_requesting_account_id  = true
#     skip_s3_checksum            = true
#   }
# }
#
