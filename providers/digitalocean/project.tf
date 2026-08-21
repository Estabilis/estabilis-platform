# ---------------------------------------------------------------------------
# DigitalOcean Project
#
# A Project is a grouping/billing lens, not a security boundary — it does not
# isolate anything. What it changes is where a resource shows up in the console
# and on the invoice breakdown.
#
# It matters here because of the default: a resource created without a project
# lands in the ACCOUNT DEFAULT project, silently. On this account that default
# already holds production applications, so an unassigned platform cluster ends
# up filed next to them.
#
# Coverage is partial and that is a DigitalOcean limitation, not an omission:
# clusters, Spaces buckets, databases, droplets and load balancers can belong
# to a project; VPCs cannot (the API object carries no project field).
#
# project_mode:
#   create   — provision a project and attach this deployment's resources
#   existing — attach to a project that already exists (var.project_id)
#   none     — attach nothing; resources land in the account default
# ---------------------------------------------------------------------------

resource "digitalocean_project" "this" {
  count = var.project_mode == "create" ? 1 : 0

  name        = local.project_name
  description = var.project_description
  purpose     = var.project_purpose
  environment = local.project_environment

  # `resources` is deliberately NOT set here. On this resource the argument is
  # authoritative over the project's entire contents, so declaring it would
  # make Terraform remove anything another tool or another module attached.
  # Assignment goes through digitalocean_project_resources below, which is
  # authoritative only over the URNs it lists.
  lifecycle {
    ignore_changes = [resources]

    precondition {
      # is_default is not exposed as a variable on purpose: flipping it would
      # move the ACCOUNT's default project, changing where every future
      # unassigned resource lands — including resources this module never
      # touches.
      condition     = var.project_mode != "create" || local.project_name != ""
      error_message = "project_mode = \"create\" needs a name: set project_name, or leave it empty to derive `{name_prefix}-platform-{env}`."
    }
  }
}

data "digitalocean_project" "existing" {
  count = var.project_mode == "existing" ? 1 : 0
  id    = var.project_id

  lifecycle {
    precondition {
      condition     = length(var.project_id) > 0
      error_message = "project_mode = \"existing\" requires project_id."
    }
  }
}

locals {
  project_name = (
    var.project_name != ""
    ? var.project_name
    : "${var.name_prefix}-platform-${local.env_code}"
  )

  # DigitalOcean accepts only these three environment labels on a project,
  # which do not line up with the six this module allows.
  project_environment = {
    dev  = "Development"
    uat  = "Development"
    hml  = "Staging"
    stg  = "Staging"
    prd  = "Production"
    prod = "Production"
  }[var.environment]

  project_id_effective = (
    var.project_mode == "create" ? one(digitalocean_project.this[*].id) :
    var.project_mode == "existing" ? one(data.digitalocean_project.existing[*].id) :
    null
  )

  # SINGLE COLLECTION POINT for everything this module creates that cannot
  # carry project_id itself. Adding a resource to this module means adding its
  # urn here — there is no provider-level default that does it automatically.
  #
  # Which side a resource falls on is not a choice: 7 DigitalOcean resource
  # types accept project_id directly (app, database_cluster, loadbalancer,
  # vpc_nat_gateway, gradientai_*, vector_database) and take it that way; the
  # other 9 expose only a urn (droplet, volume, domain, floating_ip,
  # reserved_ip, reserved_ipv6, spaces_bucket, kubernetes_cluster, vpc) and
  # have to come through here.
  #
  # DANGER: digitalocean_project_resources is AUTHORITATIVE over the urns it
  # lists. A urn belonging to a resource in another project is not rejected —
  # it is MOVED into this one. Never put a urn here that does not come from a
  # resource this module created. This account runs production workloads.
  # Accepted types, straight from the API's own rejection message — this list
  # appears in no documentation:
  #
  #   AppPlatformApp  Bucket  ByoipPrefix  Database  Domain  DomainRecord
  #   Droplet  DropletSnapshot  Firewall  FloatingIp  GenAiAgent
  #   GenAiKnowledgeBase  Image  Kubernetes  LoadBalancer  MarketplaceApp
  #   NatGateway  ReservedIPv6  Saas  Volume  VolumeSnapshot
  #
  # VPC is NOT among them. digitalocean_vpc exposes a `urn` attribute, which
  # makes it look assignable, and the project API answers 400 for the type.
  # Adding it here fails the apply — verified, not assumed.
  # The state bucket is referenced by CONSTRUCTED urn, not by resource
  # attribute. It has to be: the bucket is created by this module and then
  # released from management (terraform state rm — see backend.tf), so
  # `digitalocean_spaces_bucket.tfstate[*].urn` is empty from then on. Reading
  # the urn off the resource made the bucket silently fall out of the project
  # the moment it was released, which is exactly what happened once.
  #
  # This is also the pattern for anything else this module creates but does not
  # keep managing. The danger noted above applies with full force here: a
  # constructed urn is not validated against ownership, so tfstate_bucket_name
  # must only ever name a bucket this deployment created.
  project_resource_urns = compact([
    digitalocean_kubernetes_cluster.this.urn,
    # Gated on the bucket EXISTING, not merely on its name being computable.
    # local.tfstate_bucket_name resolves from the random suffix as soon as that
    # exists, which is stage 1 — long before the bucket does. Adding the urn
    # then asks DigitalOcean to file a bucket that is not there: the API drops
    # it, config and state never agree, and the plan reports one change forever.
    #
    # The condition matches the one gating the scoped key, for the same reason:
    # the bucket is real once it is managed (stages 2-3) or once its name is
    # pinned because it was released (stage 4 onward).
    (var.tfstate_bucket_enabled || var.tfstate_bucket_name_override != "") ? "do:space:${local.tfstate_bucket_name}" : "",

    # NAT gateway. Assigned by urn rather than by its own project_id argument,
    # which DigitalOcean ignores — see the long note in nat.tf. The urn format
    # is `do:nat_gateway:` with an underscore; the API rejects every other
    # spelling.
    one(digitalocean_vpc_nat_gateway.this[*].id) != null ? "do:nat_gateway:${one(digitalocean_vpc_nat_gateway.this[*].id)}" : "",
  ])
}

resource "digitalocean_project_resources" "this" {
  count = var.project_mode != "none" ? 1 : 0

  project   = local.project_id_effective
  resources = local.project_resource_urns

  # Ordering, not coupling — the same problem the scoped key has, for the same
  # reason. The bucket enters this list as a CONSTRUCTED urn so the assignment
  # survives the bucket leaving Terraform management. That string carries no
  # dependency, so Terraform is free to update the project before the bucket
  # exists: DigitalOcean drops the unknown urn without erroring, and the plan
  # then reports one change forever while the API keeps answering with a
  # shorter list.
  #
  # Observed on a clean bootstrap through a downstream module, where stage 2
  # creates the bucket and updates the project in the same apply.
  depends_on = [digitalocean_spaces_bucket.tfstate]
}
