# ---------------------------------------------------------------------------
# VPC NAT Gateway — egress for isolated workers
#
# Why this exists: DOKS worker nodes get public IPv4 addresses by default, and
# that is the only egress path they have. Removing those addresses
# (isolated_workers = true) removes egress with them — a cluster whose pods
# cannot reach GHCR or DOCR does not start, it sits in ImagePullBackOff with no
# way out except rebuilding. So the gateway has to exist BEFORE the workers are
# isolated, never after.
#
# The usual objection to NAT — "our apps would then share an egress endpoint
# with everything else in the VPC" — does not apply to this deployment. The VPC
# this module creates has exactly one member, the cluster. The gateway is
# therefore a DEDICATED egress identity for the platform, which is the same
# thing App Platform's dedicated egress IPs provide for third-party allowlists.
#
# Undocumented, and established by probing the API rather than reading:
#   - `size` is a count. 1 and 2 are accepted; 4 returns "exceeded NAT Gateway
#     size limit".
#   - `type` is an enum; PUBLIC is valid.
#   - NatGateway IS an accepted project resource type, and the resource takes
#     project_id directly — so it does not go through project_resources.
#   - There is no product page and no published price. Cost shows up on the
#     invoice.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# The egress address cannot be pinned. This is a DigitalOcean limitation, not
# an omission, and it was established the expensive way.
#
# Every rebuild of the gateway produces a different public address — observed
# across four of them here: 138.197.49.150, 134.199.251.183, 159.89.247.20,
# 45.55.98.208. That defeats the main reason to want a dedicated egress: no
# third party can allowlist a value that changes whenever the platform is
# rebuilt.
#
# `egresses.public_gateways.ipv4` looks like the fix, and the provider
# describes it as accepting "a BYOIP / reserved IP". It does NOT accept a
# DigitalOcean reserved IP. Passing one returns
#
#   404  BYOIP address <addr> not found on this account
#
# The field wants a BYOIP prefix — an address range the account owns and has
# onboarded through /v2/byoip_prefixes. This account has none, and acquiring
# one is a procurement exercise, not a Terraform change.
#
# Two further traps, both hit while establishing the above:
#
#   - The field is CREATE-ONLY despite `terraform plan` reporting an in-place
#     update for it. The apply reports success and the API changes nothing —
#     the same silent no-op as `project_id` below. Pinning therefore requires
#     REPLACING the gateway, and the gateway is the cluster's only route out:
#     replacing it drops egress, and a failed re-create leaves the cluster
#     with no path to its own control plane until a working gateway returns.
#
#   - `prevent_destroy` on a reserved IP created for this blocks the rollback
#     that removing it would need. Do not add it here.
#
# If a stable egress identity becomes a requirement, the route is BYOIP, and
# the work starts outside this repository.
# ---------------------------------------------------------------------------

resource "digitalocean_vpc_nat_gateway" "this" {
  count = var.nat_gateway_enabled ? 1 : 0

  name   = var.nat_gateway_name_override != "" ? var.nat_gateway_name_override : "nat-${local.base_name}"
  region = var.region
  type   = var.nat_gateway_type
  size   = var.nat_gateway_size

  # project_id is NOT set here, and that is deliberate.
  #
  # The attribute exists and the provider sends it, but DigitalOcean ignores it
  # on create — the gateway lands in the ACCOUNT DEFAULT project regardless. An
  # update to correct it reports success and changes nothing. And because the
  # field is ForceNew, Terraform then plans a destroy-and-recreate on every
  # single run, forever, chasing a value the API will not accept.
  #
  # All of that verified against the live API, not inferred.
  #
  # The assignment therefore goes through digitalocean_project_resources in
  # project.tf, with the urn `do:nat_gateway:<id>` — a format that also had to
  # be found by probing: `do:natgateway:`, `do:vpcnatgateway:` and
  # `do:vpc_nat_gateway:` are all rejected.
  #
  # Leaving project_id unset lets it stay Computed, so Terraform records
  # whatever the API reports and never plans a change against it.

  vpcs {
    vpc_uuid = local.vpc_uuid_effective

    # Set to true, matching what the API reports for this gateway.
    #
    # Getting here took some doing, and the trap is worth recording. `vpcs` is
    # a schema.TypeSet, so Terraform identifies members by hashing the WHOLE
    # element. If the configured element and the refreshed one disagree on any
    # field, Terraform does not see an update — it sees one member removed and
    # another added. And since `vpc_uuid` and `subnet_uuid` are ForceNew,
    # swapping a member REPLACES the gateway, dropping the egress IP with it.
    #
    # What made this hard to read: the CREATE response omits default_gateway,
    # so the first apply recorded `false` in state while the config said
    # `true` — a permanent replace diff. A later GET does return the field, so
    # `terraform state rm` + `terraform import` reconciles state to `true` and
    # the diff disappears.
    #
    # Two consequences to respect:
    #   - Do not "simplify" by deleting this line. Omitting it puts the config
    #     back out of step with the API and the replace loop returns, this time
    #     in the other direction.
    #   - After the first apply of a NEW gateway, expect one spurious replace
    #     diff. Re-import rather than applying it.
    default_gateway = true
  }

  tcp_timeout_seconds  = var.nat_gateway_tcp_timeout_seconds
  udp_timeout_seconds  = var.nat_gateway_udp_timeout_seconds
  icmp_timeout_seconds = var.nat_gateway_icmp_timeout_seconds

}
