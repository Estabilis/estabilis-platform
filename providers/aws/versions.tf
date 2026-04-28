terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # v6 series — required for aws_networkflowmonitor_* resources (introduced in v6.21).
      # Breaking changes vs v5 audited and applied: aws_eks_addon `resolve_conflicts`
      # removed (split into _on_create / _on_update — handled by EKS module v21+).
      version = "~> 6.42"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.2"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # v3 series — v2 resource names (`kubernetes_namespace`, `kubernetes_secret`,
      # `kubernetes_config_map`) still function with deprecation warnings; new
      # work should land on the `_v1` suffixed variants.
      version = "~> 3.1"
    }
    helm = {
      source = "hashicorp/helm"
      # v3 series — provider configuration migrated from `kubernetes { ... }`
      # block syntax to `kubernetes = { ... }` object syntax (see main.tf).
      version = "~> 3.1"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
      # v5 series — `cloudflare_record` was renamed to `cloudflare_dns_record`
      # with new schema (v500). See acm.tf for usage. State migrations from v4
      # require `tf-migrate` from Cloudflare; this codebase ships v5 directly
      # so fresh applies pick up the new resource name without state surgery.
      version = "~> 5.19"
    }
  }
}
