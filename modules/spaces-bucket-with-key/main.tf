# ---------------------------------------------------------------------------
# A Spaces bucket and the scoped key that reaches it, as one unit.
#
# The point of the module is that the two cannot be separated. On DigitalOcean
# a scoped key can only reach the single bucket named in its grant, so every
# bucket needs its own key — and a bucket without its key is unusable while a
# key without its bucket is an orphaned credential. Keeping them in one module
# with one `enabled` flag makes both states unrepresentable.
#
# Ordering falls out of the reference rather than being declared:
#
#   create   bucket then key — DigitalOcean rejects a grant naming a bucket
#            that does not exist (403 invalid grant)
#   destroy  key then bucket — Terraform destroys in reverse dependency order
#
# Note this is the opposite arrangement from the Terraform state bucket, which
# grants by NAME and uses depends_on. That one has to survive its bucket
# leaving Terraform management; a component bucket never does.
# ---------------------------------------------------------------------------

resource "digitalocean_spaces_bucket" "this" {
  count = var.enabled ? 1 : 0

  name   = var.name
  region = var.region
  acl    = "private"

  force_destroy = var.force_destroy

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
}

resource "digitalocean_spaces_key" "this" {
  count = var.enabled ? 1 : 0

  name = var.key_name != "" ? var.key_name : "${var.name}-key"

  # Referencing the resource, not a string. This is what binds the two
  # lifecycles: Terraform cannot order these wrongly in either direction, and
  # flipping `enabled` to false takes both in a single apply.
  grant {
    bucket     = digitalocean_spaces_bucket.this[0].name
    permission = var.permission
  }
}
