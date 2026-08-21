# ---------------------------------------------------------------------------
# VPC
#
# vpc_mode = "create" provisions a VPC; "existing" attaches the cluster to one
# already in the account (var.vpc_uuid). Both paths funnel through
# local.vpc_uuid_effective so doks.tf never has to branch.
#
# ip_range is left null by default. DigitalOcean then allocates a free /20 in
# the region — the documented provider behaviour, and the reason the account's
# default VPCs carry ranges like 10.108.0.0/20 nobody chose. A downstream that
# needs a specific range sets vpc_ip_range, but note DigitalOcean cannot alter
# a VPC's range in place: changing it forces a new VPC, and everything attached
# to the old one is replaced with it.
#
# digitalocean_vpc has no tags argument (confirmed against provider schema
# v2.100), so the CAF projection does not reach this resource. The name and
# description carry what identity they can.
# ---------------------------------------------------------------------------

resource "digitalocean_vpc" "this" {
  count = var.vpc_mode == "create" ? 1 : 0

  name        = var.vpc_name != "" ? var.vpc_name : "vpc-${local.base_name}"
  region      = var.region
  description = var.vpc_description
  # Immutable server-side: DigitalOcean rejects an ip_range change, so
  # Terraform plans a replacement of the VPC and everything attached to it.
  ip_range = var.vpc_ip_range
}

data "digitalocean_vpc" "existing" {
  count = var.vpc_mode == "existing" ? 1 : 0
  id    = var.vpc_uuid

  lifecycle {
    precondition {
      condition     = length(var.vpc_uuid) > 0
      error_message = "vpc_mode = \"existing\" requires vpc_uuid to be set."
    }
  }
}

locals {
  # one() over [*] rather than [0]: exactly one of these two counts is 1 and
  # the other is 0, and indexing the empty one is a plan-time error waiting to
  # happen. one() yields null for an empty list instead of blowing up.
  vpc_uuid_effective = (
    var.vpc_mode == "create"
    ? one(digitalocean_vpc.this[*].id)
    : one(data.digitalocean_vpc.existing[*].id)
  )

  vpc_ip_range_effective = (
    var.vpc_mode == "create"
    ? one(digitalocean_vpc.this[*].ip_range)
    : one(data.digitalocean_vpc.existing[*].ip_range)
  )
}

check "existing_vpc_region_matches" {
  assert {
    condition     = alltrue([for v in data.digitalocean_vpc.existing : v.region == var.region])
    error_message = "The existing VPC is in a different region than var.region. A DOKS cluster can only attach to a VPC in its own region."
  }
}
