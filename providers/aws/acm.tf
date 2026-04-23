# ---------------------------------------------------------------------------
# ACM wildcard certificate (opt-in)
#
# Used when ingress_controller = 'alb' and the operator wants TLS terminated
# at the ALB with an AWS-native certificate (no cert-manager on the public
# path). DNS-01 validation is automatic when dns_provider = 'route53'; for
# Cloudflare the caller must create the _acme-challenge CNAMEs manually
# (the certificate waits up to 90 minutes, so this path is discouraged).
#
# Domain: *.{cluster_name}.{domain}
# Extra SANs: var.acm_extra_domain_names
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "wildcard" {
  count = var.acm_enabled ? 1 : 0

  domain_name               = "*.${local.cluster_name}.${var.domain}"
  subject_alternative_names = var.acm_extra_domain_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# DNS validation records (only when dns_provider = route53 — we can create
# them automatically; Cloudflare requires manual CNAME creation).
# ---------------------------------------------------------------------------

resource "aws_route53_record" "acm_validation" {
  for_each = var.acm_enabled && var.dns_provider == "route53" ? {
    for dvo in aws_acm_certificate.wildcard[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = local.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "wildcard" {
  count = var.acm_enabled && var.dns_provider == "route53" ? 1 : 0

  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}
