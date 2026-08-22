# ---------------------------------------------------------------------------
# DigitalOcean Container Registry
# Toggle via: registry_enabled = true
#
# This is a much smaller surface than ECR or ACR, and the difference is the
# product rather than the provider. `digitalocean_container_registry` accepts
# three arguments — name, subscription tier, region — and computes the rest.
# There is no equivalent here for declared repositories, tag immutability, scan
# on push, retention policy, pull-through cache, network firewall, private
# endpoint, geo-replication, content trust, or scoped tokens. Nothing is being
# left out; there is nothing to expose.
#
# THREE THINGS THAT MAKE THIS RESOURCE UNLIKE EVERY OTHER ONE IN THIS MODULE.
#
# 1. The subscription is the ACCOUNT'S, not this registry's. `GET /v2/registry`
#    returns one registry and one subscription, and the tiers are sold as "10
#    registries" — a count that only means anything account-wide. So
#    registry_subscription_tier changes a billing setting that covers every
#    registry on the account, including ones this deployment did not create and
#    must not disturb. It is the only input in this module with that reach.
#
# 2. The tier decides how many registries may exist at all: one on starter and
#    basic, ten on professional. Enabling this on an account already holding a
#    registry, on either of the smaller tiers, fails at the API.
#
# 3. A registry cannot belong to a Project. The accepted urn types — read off
#    the API's own rejection message, in project.tf — do not include it. So
#    unlike the cluster, the VPC's gateway and the state bucket, this resource
#    will not appear under the platform Project. It is account-global, and
#    verify-project-membership.sh will not account for it.
#
# NO RETENTION POLICY EXISTS. DigitalOcean has garbage collection, but only as
# an imperative API and CLI call with no Terraform resource, so the equivalent
# of ecr_lifecycle_untagged_days is a scheduled job somebody has to write. On a
# shared account this is the difference between a registry that stays inside its
# storage allowance and one that quietly bills overage for years.
# ---------------------------------------------------------------------------

locals {
  # <name_prefix>[-<purpose>]-<env>[-<suffix>]. Registry names are globally
  # unique across all of DigitalOcean, which is why the suffix defaults on — the
  # same reason ACR carries one. It is the SAME suffix the state bucket uses, so
  # a deployment reads as one thing rather than a collection of strangers.
  registry_name = coalesce(
    var.registry_name_override,
    join("-", compact([
      var.name_prefix,
      var.registry_purpose,
      local.env_code,
      var.registry_random_suffix_enabled ? random_string.bucket_suffix.result : "",
    ]))
  )

  registry_region = var.registry_region != "" ? var.registry_region : var.region

  # Tiers that permit exactly one registry per account.
  registry_single_registry_tiers = ["starter", "basic"]
}

resource "digitalocean_container_registry" "this" {
  count = var.registry_enabled ? 1 : 0

  name                   = local.registry_name
  subscription_tier_slug = var.registry_subscription_tier
  region                 = local.registry_region

  lifecycle {
    precondition {
      # The account-wide reach in note 1 is the whole reason this is a
      # precondition rather than a comment. An operator turning the registry on
      # for this deployment should not discover afterwards that they changed
      # what another product pays.
      condition = (
        !contains(local.registry_single_registry_tiers, var.registry_subscription_tier)
        || var.registry_sole_account_registry
      )
      error_message = "registry_subscription_tier is \"${var.registry_subscription_tier}\", which allows ONE registry per account and sets the subscription for the whole account. If this deployment owns the account's only registry, set registry_sole_account_registry = true to say so. If the account has another registry — belonging to another product — either use \"professional\", which permits ten, or leave registry_enabled = false and attach to the existing one with registry_integration."
    }

    precondition {
      condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", local.registry_name))
      error_message = "Registry name \"${local.registry_name}\" is not valid. DigitalOcean requires lowercase letters, digits and hyphens, starting and ending alphanumeric. The name is also globally unique across DigitalOcean — leave registry_random_suffix_enabled on unless you have a reason."
    }
  }
}

# ---------------------------------------------------------------------------
# Credentials
#
# The cluster does not need these: registry_integration makes DigitalOcean
# inject an imagePullSecret into namespaces by itself. These are for everything
# outside the cluster — a CI job that pushes, a machine that pulls.
#
# Registry-wide by design, and that is a real limitation rather than an
# oversight: DigitalOcean has no scope maps, so `write` is the only dial. A
# credential that may push may push to every repository in the registry.
# ---------------------------------------------------------------------------

resource "digitalocean_container_registry_docker_credentials" "ci" {
  count = var.registry_enabled && var.registry_ci_credentials_enabled ? 1 : 0

  registry_name = digitalocean_container_registry.this[0].name
  write         = true

  # An expiring credential is the safer choice and the noisier one: Terraform
  # sees the expiry pass and proposes a new credential, so whatever consumes it
  # has to be re-fed on that cadence. 0 leaves it non-expiring.
  expiry_seconds = var.registry_credentials_expiry_seconds > 0 ? var.registry_credentials_expiry_seconds : null
}

resource "digitalocean_container_registry_docker_credentials" "pull" {
  count = var.registry_enabled && var.registry_pull_credentials_enabled ? 1 : 0

  registry_name  = digitalocean_container_registry.this[0].name
  write          = false
  expiry_seconds = var.registry_credentials_expiry_seconds > 0 ? var.registry_credentials_expiry_seconds : null
}

# ---------------------------------------------------------------------------
# registry_integration is a BOOLEAN on the cluster, with no registry selector.
# On an account holding one registry that is unambiguous. On professional, with
# up to ten, which one DigitalOcean binds is undocumented — so a deployment that
# enables integration while owning several registries is relying on behaviour
# nobody has written down.
#
# A check rather than a precondition: attaching the cluster to a registry this
# module did not create is a legitimate choice — it is how you use the account's
# existing registry without adopting it — and it should be visible, not blocked.
# ---------------------------------------------------------------------------

check "registry_integration_without_a_registry" {
  assert {
    condition     = !var.registry_integration || var.registry_enabled
    error_message = "registry_integration = true with registry_enabled = false: the cluster will be bound to whichever registry the ACCOUNT already owns, which this module did not create and does not manage. Intentional in most cases — this exists so it is not a surprise."
  }
}
