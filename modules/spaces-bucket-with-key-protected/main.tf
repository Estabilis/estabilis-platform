# ---------------------------------------------------------------------------
# A Spaces bucket and its scoped key, as one unit, that a plan CANNOT destroy.
#
# This is the protected sibling of `spaces-bucket-with-key`. The plain module
# gates its resources on `count = var.enabled ? 1 : 0`, which is the right shape
# for a throwaway: flip `enabled` to false and the next apply removes the bucket
# and the key together. That is exactly the wrong shape for a bucket that holds
# data. A bucket with objects is worth what a database is worth, and a config
# change should never be one flag away from deleting it.
#
# So this module differs in three deliberate ways, none of which can be a
# variable:
#
#   * `lifecycle { prevent_destroy = true }` on the bucket. The argument takes a
#     literal, not an expression, so protection cannot be a module input — it is
#     the identity of the module. Any plan that would destroy or replace the
#     bucket (a rename, a region change, a removal) fails at plan time.
#   * `force_destroy` is fixed to false. A bucket you have promised not to
#     destroy is not one you empty and drop.
#   * there is no `enabled` toggle. "Turn it off" and "delete the data" are the
#     same operation here, and this module refuses to make it available.
#
# Ordering falls out of the reference, exactly as in the plain module: create
# bucket then key (DigitalOcean rejects a grant naming a bucket that does not
# exist), destroy key then bucket (reverse dependency order — though the bucket's
# destroy is blocked regardless).
#
# Rotating the key is still allowed: the key carries no prevent_destroy, so a
# new grant or a replaced key applies normally. Only the bucket is frozen.
# ---------------------------------------------------------------------------

resource "digitalocean_spaces_bucket" "this" {
  name   = var.name
  region = var.region
  acl    = "private"

  # A data bucket is never force-emptied by Terraform. Emptying it (versions and
  # all) is a deliberate, manual act — see scripts/empty-spaces-bucket.py in the
  # consuming repository — done before a bucket is ever removed on purpose.
  force_destroy = false

  versioning {
    enabled = var.versioning_enabled
  }

  dynamic "lifecycle_rule" {
    for_each = var.abort_incomplete_multipart_days > 0 ? [1] : []
    content {
      id      = "abort-incomplete-multipart"
      enabled = true

      # A failed upload leaves parts that no listing shows and every invoice
      # counts.
      abort_incomplete_multipart_upload_days = var.abort_incomplete_multipart_days
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.expire_noncurrent_days > 0 && var.versioning_enabled ? [1] : []
    content {
      id      = "expire-noncurrent"
      enabled = true

      noncurrent_version_expiration {
        days = var.expire_noncurrent_days
      }
    }
  }

  lifecycle {
    # The whole point of the module. Not a variable: prevent_destroy takes a
    # literal, and a data bucket's protection must not be something a caller can
    # switch off from a tfvars file.
    prevent_destroy = true
  }
}

resource "digitalocean_spaces_key" "this" {
  name = var.key_name != "" ? var.key_name : "${var.name}-key"

  # Referencing the resource, not a string, so create/destroy order cannot be
  # declared wrongly. The key is intentionally replaceable — only the bucket is
  # frozen — so a rotation is an ordinary apply.
  grant {
    bucket     = digitalocean_spaces_bucket.this.name
    permission = var.permission
  }
}
