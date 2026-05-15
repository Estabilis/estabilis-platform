# ============================================================================
# ALB Controller webhook TLS — Terraform-managed (alternative to chart auto-gen)
# ============================================================================
#
# When var.alb_controller_webhook_tls_managed_by = "terraform", these resources
# generate a stable CA + webhook cert that the aws-load-balancer-controller
# chart consumes via webhookTLS.{caCert,cert,key} values. This avoids the
# race condition where the chart's `genSignedCert` helper produces a new cert
# on every render, while ALB Controller pods keep serving the previous cert
# from memory because the Deployment template lacks a `checksum/secret`
# annotation. Symptom: `x509: certificate signed by unknown authority` blocks
# every Service creation cluster-wide until pods are manually restarted.
#
# Gating:
#   - var.ingress_controller = "alb"
#   - var.alb_controller_webhook_tls_managed_by = "terraform"
#   Both required — defaults keep the chart's auto-gen path in place.
#
# Lifecycle:
#   - CA: 10 year validity. Rotation is operator-driven via
#     `terraform taint tls_private_key.alb_controller_ca` + apply.
#   - Webhook cert: 5 year validity. Same rotation path.
#   Rotation is a manual maintenance window task — acceptable at this cadence.
#
# Out-of-scope (future work, separate ADR):
#   - Migration to cert-manager.io/Certificate with cert-manager CAInjector.
#     That eliminates the manual rotation but requires wave reordering
#     (cert-manager must run before ALB Controller, currently it runs after).
# ============================================================================

locals {
  alb_controller_webhook_tls_tf_managed = (
    var.ingress_controller == "alb" &&
    var.alb_controller_webhook_tls_managed_by == "terraform"
  )
}

resource "tls_private_key" "alb_controller_ca" {
  count = local.alb_controller_webhook_tls_tf_managed ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb_controller_ca" {
  count = local.alb_controller_webhook_tls_tf_managed ? 1 : 0

  private_key_pem = tls_private_key.alb_controller_ca[0].private_key_pem

  subject {
    common_name  = "estabilis-alb-controller-ca"
    organization = "estabilis-platform"
  }

  validity_period_hours = 8760 * 10 # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "tls_private_key" "alb_controller_webhook" {
  count = local.alb_controller_webhook_tls_tf_managed ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "alb_controller_webhook" {
  count = local.alb_controller_webhook_tls_tf_managed ? 1 : 0

  private_key_pem = tls_private_key.alb_controller_webhook[0].private_key_pem

  subject {
    common_name = "aws-load-balancer-webhook-service.aws-load-balancer-controller.svc"
  }

  # SANs mirror the chart's webhookCerts helper (_helpers.tpl). Service short
  # name + svc + svc.cluster.local form the canonical webhook URL set the
  # API server tries when calling MutatingWebhookConfiguration.clientConfig.
  dns_names = [
    "aws-load-balancer-webhook-service",
    "aws-load-balancer-webhook-service.aws-load-balancer-controller",
    "aws-load-balancer-webhook-service.aws-load-balancer-controller.svc",
    "aws-load-balancer-webhook-service.aws-load-balancer-controller.svc.cluster.local",
  ]
}

resource "tls_locally_signed_cert" "alb_controller_webhook" {
  count = local.alb_controller_webhook_tls_tf_managed ? 1 : 0

  cert_request_pem   = tls_cert_request.alb_controller_webhook[0].cert_request_pem
  ca_private_key_pem = tls_private_key.alb_controller_ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.alb_controller_ca[0].cert_pem

  validity_period_hours = 8760 * 5 # 5 years

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}
