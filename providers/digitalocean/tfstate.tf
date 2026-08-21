# ---------------------------------------------------------------------------
# Terraform state bucket (Spaces)
#
# Created HERE, migrated to LATER. Those are two separate steps on purpose and
# the order cannot be swapped: a backend must exist before `init` can point at
# it, and this module is what creates it. So the first apply of a deployment
# always runs on local state, and only afterwards does the operator uncomment
# the backend block and run `init -migrate-state`.
#
# See backend.tf for the block to uncomment and the exact values, and the
# `tfstate_backend_config` output for a ready-to-paste rendering of it.
#
# Hardening available on DigitalOcean, and what is missing compared to S3:
#   - Versioning ON — the rollback path when a state write corrupts.
#   - ACL private + a bucket policy denying non-TLS access.
#   - force_destroy defaults false, so `terraform destroy` refuses to delete a
#     bucket that still holds state files.
#   - NO object lock. Spaces has no equivalent to S3 Object Lock, so the AWS
#     provider's `s3_tfstate_protect_critical` has nothing to map to here.
#   - NO server-side-encryption configuration. Spaces encrypts at rest by
#     default and the resource exposes no knob, so there is nothing to set —
#     but there is also nothing to prove in a plan.
#   - NO DynamoDB equivalent for locking. Locking depends entirely on
#     `use_lockfile = true` in the backend block (Terraform >= 1.10).
# ---------------------------------------------------------------------------

# Not gated on tfstate_bucket_enabled: the bucket NAME has to be resolvable
# before the bucket exists, because the Spaces key that will create it is
# granted against that name. Generating six characters costs nothing and the
# value is stable in state from the first apply.
resource "random_string" "bucket_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  # Spaces bucket names share ONE namespace across every DigitalOcean account,
  # not just this one — the same rule as S3. The random suffix is what keeps
  # `{prefix}-tfstate-{env}` from colliding with someone else's bucket.
  _bucket_suffix = random_string.bucket_suffix.result

  tfstate_bucket_name = (
    var.tfstate_bucket_name_override != ""
    ? var.tfstate_bucket_name_override
    : "${var.name_prefix}-tfstate-${local.env_code}-${local._bucket_suffix}"
  )

  spaces_region_effective = var.spaces_region != "" ? var.spaces_region : var.region
}

# Rendered so the operator pastes values instead of transcribing them. A
# heredoc cannot sit inline in a conditional expression, hence the local.
locals {
  _tfstate_backend_block = <<-EOT
    terraform {
      backend "s3" {
        bucket = "${local.tfstate_bucket_name}"
        key    = "platform/terraform.tfstate"

        # Ignored by Spaces, but the s3 backend refuses to initialise without it.
        region = "us-east-1"

        endpoints = {
          s3 = "https://${local.spaces_region_effective}.digitaloceanspaces.com"
        }

        # Spaces has no DynamoDB equivalent. This is the ONLY locking available.
        use_lockfile = true

        # Not hardening choices — without these the backend tries to reach AWS
        # STS/IAM and init fails.
        skip_credentials_validation = true
        skip_metadata_api_check     = true
        skip_region_validation      = true
        skip_requesting_account_id  = true
        skip_s3_checksum            = true
      }
    }
  EOT

  tfstate_backend_config = (
    var.tfstate_bucket_enabled
    ? local._tfstate_backend_block
    : "tfstate_bucket_enabled = false - this deployment runs on local state."
  )
}

# Advisory only, and it has to be. The recommended way to supply Spaces
# credentials is SPACES_ACCESS_KEY_ID / SPACES_SECRET_ACCESS_KEY in the
# environment, which Terraform cannot see — the provider reads them directly.
# A precondition here would therefore block the documented happy path, which is
# exactly what it did the first time this was written. What is left is a
# warning that names the likely cause when the apply fails with a signature
# error that mentions neither Spaces nor credentials.
check "policy_and_scoped_key_are_exclusive" {
  assert {
    condition     = !(var.tfstate_deny_insecure_transport && var.tfstate_key_enabled && var.tfstate_bucket_enabled)
    error_message = "tfstate_deny_insecure_transport and tfstate_key_enabled cannot both be on: DigitalOcean rejects a bucket-scoped key for a bucket that carries an S3 bucket policy (412, 'Only All Permissions access keys support buckets with S3 bucket policies'). Pick one."
  }
}

check "spaces_credentials_present" {
  assert {
    condition = (
      !var.tfstate_bucket_enabled ||
      (var.spaces_access_id != "" && var.spaces_secret_key != "") ||
      length(digitalocean_spaces_bucket.tfstate) > 0
    )
    error_message = "tfstate_bucket_enabled is on and no Spaces credentials were passed as variables. If SPACES_ACCESS_KEY_ID / SPACES_SECRET_ACCESS_KEY are exported, ignore this. If the apply fails with a signature error, this is why: Spaces credentials are a different pair from the DigitalOcean API token."
  }
}

resource "digitalocean_spaces_bucket" "tfstate" {
  count = var.tfstate_bucket_enabled ? 1 : 0

  # Depends on the bootstrap key in BOTH directions, and the destroy direction
  # is the one that matters.
  #
  # Terraform destroys in reverse dependency order, so declaring this makes the
  # bucket go BEFORE the key that is the only credential able to delete it.
  # Without it the two are independent and Terraform destroys them in parallel:
  # the key wins the race, the bucket delete fails, and the deployment is left
  # with an orphaned bucket and nothing authorised to remove it. Recovering
  # means creating a Spaces key by hand — outside Terraform, mid-teardown.
  #
  # On the way up it encodes the same truth the bootstrap stages describe: a
  # bucket cannot be created without an account-wide key.

  name   = local.tfstate_bucket_name
  region = local.spaces_region_effective
  acl    = "private"

  # Primary guard against losing state to a stray destroy. With force_destroy
  # false, DigitalOcean refuses to delete a bucket that still has objects — and
  # the objects here ARE the state. Flip to true only for a deliberate teardown.
  force_destroy = var.tfstate_force_destroy

  depends_on = [digitalocean_spaces_key.bootstrap]

  versioning {
    enabled = var.tfstate_versioning_enabled
  }

  lifecycle_rule {
    id      = "abort-incomplete-multipart"
    enabled = true

    # A failed state write can leave multipart parts behind that are invisible
    # in the bucket listing and still billed.
    abort_incomplete_multipart_upload_days = 7
  }

}

# Deny anything that is not TLS.
#
# OFF by default, and the reason is a DigitalOcean incompatibility rather than
# a preference: a bucket carrying an S3 bucket policy accepts ONLY
# `All Permissions` access keys. Attaching this policy makes the scoped key in
# this same file impossible — the API answers
#
#   412 ... Only 'All Permissions' access keys support buckets with S3 bucket
#   policies
#
# So the two hardening measures are mutually exclusive and one has to win. The
# scoped key wins: a leaked account-wide key reaches every bucket in the
# account — fourteen of them here, holding production data — while the missing
# policy costs a plaintext request that the Terraform backend never makes,
# since its endpoint is https and the bucket is private either way.
#
# Turn this on only for a bucket that no scoped key needs to reach.
resource "digitalocean_spaces_bucket_policy" "tfstate_tls_only" {
  count = var.tfstate_bucket_enabled && var.tfstate_deny_insecure_transport ? 1 : 0

  region = digitalocean_spaces_bucket.tfstate[0].region
  bucket = digitalocean_spaces_bucket.tfstate[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        "arn:aws:s3:::${digitalocean_spaces_bucket.tfstate[0].name}",
        "arn:aws:s3:::${digitalocean_spaces_bucket.tfstate[0].name}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# Spaces keys — two of them, and the reason is a hard DigitalOcean constraint
#
# Creating a bucket requires Spaces credentials. Creating a key SCOPED to a
# bucket requires that bucket to already exist — DigitalOcean rejects the grant
# otherwise, with `403 invalid grant` (verified against the live API, not
# assumed). Those two facts together mean no single scoped key can bootstrap
# its own bucket, and no ordering inside one apply resolves it.
#
# So the bootstrap runs in two stages, both in Terraform:
#
#   Stage 1  tfstate_bootstrap_key_enabled = true, tfstate_bucket_enabled = false
#            Creates a TEMPORARY account-wide key using only the API token.
#            Export it as SPACES_ACCESS_KEY_ID / SPACES_SECRET_ACCESS_KEY.
#
#   Stage 2  tfstate_bucket_enabled = true
#            The bucket is created with the bootstrap key, and the scoped key
#            is created against the bucket that now exists.
#
#   Stage 3  tfstate_bootstrap_key_enabled = false
#            Destroys the account-wide key. What remains is one key that
#            reaches exactly one bucket.
#
# Leaving the bootstrap key in place is the failure mode to avoid — it is how
# an account ends up with the eight `fullaccess` keys this one already has.
# ---------------------------------------------------------------------------

resource "digitalocean_spaces_key" "bootstrap" {
  count = var.tfstate_bootstrap_key_enabled ? 1 : 0

  name = "${var.name_prefix}-tfstate-bootstrap-${local.env_code}"

  # bucket = "" is an account-wide grant. The provider marks `bucket` required
  # so it cannot be omitted, but the API treats the empty string as "no bucket
  # restriction" — which is the only grant that can create a bucket that does
  # not exist yet. Temporary by design; see stage 3.
  grant {
    bucket     = ""
    permission = "fullaccess"
  }
}

# Gated on tfstate_key_enabled alone, and granted against the bucket NAME
# rather than the bucket resource. Both are deliberate: once the bucket is
# released from Terraform management (see the note in backend.tf), the resource
# no longer exists in state, but the key that reads and writes the state object
# has to outlive it. A grant by name works because the bucket exists by then —
# DigitalOcean only rejects grants naming a bucket that was never created.
resource "digitalocean_spaces_key" "tfstate" {
  # Two conditions, and the second is what makes a clean bootstrap work.
  #
  # DigitalOcean rejects a grant naming a bucket that does not exist yet
  # (403 invalid grant), so this key cannot be created during stage 1 — the
  # bucket does not exist until stage 2. But it also has to OUTLIVE stage 4,
  # where the bucket is released from Terraform management and
  # `digitalocean_spaces_bucket.tfstate` stops existing in state.
  #
  # So: create it when the bucket is under management (stages 2-3), or when its
  # name is pinned because it was released (stage 4 onward). Never in stage 1.
  #
  # Gating this on tfstate_key_enabled alone looks correct and passes every
  # incremental apply, because by then the bucket already exists. It only fails
  # on a deployment built from nothing — which is exactly why one was built
  # from nothing.
  count = var.tfstate_key_enabled && (var.tfstate_bucket_enabled || var.tfstate_bucket_name_override != "") ? 1 : 0

  name = "${var.name_prefix}-tfstate-${local.env_code}"

  grant {
    bucket     = local.tfstate_bucket_name
    permission = "readwrite"
  }

  # Ordering, not coupling.
  #
  # The grant above names the bucket by STRING so this key can outlive the
  # bucket leaving Terraform management in stage 4. That is deliberate — and it
  # also removes the dependency edge Terraform would otherwise infer, so during
  # stage 2 it happily creates the key in PARALLEL with the bucket and the
  # grant lands before the bucket exists: 403 invalid grant, again.
  #
  # depends_on restores the ordering without restoring the reference. Pointing
  # at the counted resource is safe in both directions: with count = 0 the list
  # is empty and there is simply no dependency to wait on.
  depends_on = [digitalocean_spaces_bucket.tfstate]
}
