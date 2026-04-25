# ---------------------------------------------------------------------------
# ACM wildcard certificate (opt-in)
#
# Used when ingress_controller = 'alb'. ALB Controller only consumes ACM
# certificates (it cannot read k8s Secrets — cert-manager-issued certs
# do NOT work on ALB). DNS-01 validation is automatic for both
# 'route53' and 'cloudflare' providers — the latter writes the
# _acme-challenge CNAME via the Cloudflare API token already required
# by external-dns / cert-manager DNS-01 issuer.
#
# Domain: *.{cluster_name}.{domain}
# Extra SANs: var.acm_extra_domain_names
# ---------------------------------------------------------------------------

# Cross-variable validation: ALB Controller only consumes ACM certificates —
# cert-manager-issued k8s Secrets do NOT work. If the operator picks
# ingress_controller = "alb" but forgets acm_enabled, fail at plan time
# instead of after a successful apply that produces broken Ingresses.
resource "null_resource" "alb_requires_acm_validation" {
  count = var.ingress_controller == "alb" ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.acm_enabled
      error_message = "ingress_controller = \"alb\" requires acm_enabled = true. AWS Load Balancer Controller cannot consume cert-manager-issued k8s Secrets — only ACM certificates are supported. Set acm_enabled = true to provision a wildcard ACM cert validated automatically via the configured dns_provider (route53 or cloudflare)."
    }
  }
}

# Cross-variable validation: ACM DNS validation only automated for
# 'route53' and 'cloudflare'. With dns_provider = "none" the operator
# would have to place CNAMEs by hand and the certificate_validation
# resource would block forever — fail loud upfront.
resource "null_resource" "acm_requires_managed_dns" {
  count = var.acm_enabled ? 1 : 0

  lifecycle {
    precondition {
      condition     = contains(["route53", "cloudflare"], var.dns_provider)
      error_message = "acm_enabled = true requires dns_provider = \"route53\" or \"cloudflare\" so Terraform can place the validation CNAMEs automatically. With dns_provider = \"none\" you would have to validate by hand and the apply would block — disable acm_enabled or pick a managed DNS provider."
    }
  }
}

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
# DNS validation records — Route53 path.
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

# ---------------------------------------------------------------------------
# DNS validation records — Cloudflare path.
#
# ACM emits validation records as fully-qualified CNAMEs ending with
# `.${var.domain}.` — Cloudflare's API expects relative names, so we
# trimsuffix the zone to keep the record under the right zone without
# duplicating the apex.
# ---------------------------------------------------------------------------

resource "cloudflare_record" "acm_validation" {
  for_each = var.acm_enabled && var.dns_provider == "cloudflare" ? {
    for dvo in aws_acm_certificate.wildcard[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(each.value.name, ".${var.domain}.")
  content = trimsuffix(each.value.record, ".")
  type    = each.value.type
  ttl     = 60
  proxied = false
  comment = "ACM cert validation for ${local.cluster_name} (managed by estabilis-platform)"
}

resource "aws_acm_certificate_validation" "wildcard" {
  count = var.acm_enabled && contains(["route53", "cloudflare"], var.dns_provider) ? 1 : 0

  certificate_arn = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = var.dns_provider == "route53" ? (
    [for r in aws_route53_record.acm_validation : r.fqdn]
    ) : (
    [for r in cloudflare_record.acm_validation : r.hostname]
  )
}
