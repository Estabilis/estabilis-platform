# ---------------------------------------------------------------------------
# Route53 — public hosted zone for var.domain
#
# When var.dns_provider = 'route53':
#   - route53_zone_mode = 'create': zone is created (NS records must be
#     delegated to it at the registrar)
#   - route53_zone_mode = 'existing': zone is looked up by name
#
# local.route53_zone_arns_or_wildcard is consumed by iam.tf (external-dns
# and cert-manager IRSA modules) to scope their policies to this zone.
# Empty list when dns_provider != 'route53' means the IRSA modules default
# to the wildcard (safe because they are count-gated off in that case).
# ---------------------------------------------------------------------------

resource "aws_route53_zone" "platform" {
  count = var.dns_provider == "route53" && var.route53_zone_mode == "create" ? 1 : 0

  name = var.domain

  comment = "Managed by estabilis-platform (${local.base_name})"
}

data "aws_route53_zone" "existing" {
  count        = var.dns_provider == "route53" && var.route53_zone_mode == "existing" ? 1 : 0
  name         = var.domain
  private_zone = false
}

# route53_zone_arns_or_wildcard is in locals.tf (shared with iam.tf).
locals {
  route53_zone_id = (
    var.dns_provider == "route53" && var.route53_zone_mode == "create" ? aws_route53_zone.platform[0].zone_id
    : var.dns_provider == "route53" && var.route53_zone_mode == "existing" ? data.aws_route53_zone.existing[0].zone_id
    : ""
  )

  route53_zone_name_servers = (
    var.dns_provider == "route53" && var.route53_zone_mode == "create" ? aws_route53_zone.platform[0].name_servers
    : []
  )
}
