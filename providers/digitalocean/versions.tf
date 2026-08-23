terraform {
  required_version = ">= 1.7.0"

  # Only the providers this phase actually uses. kubernetes, helm, tls and time
  # return alongside the code that needs them (ArgoCD seed) — declaring them
  # now makes every `terraform init` download hundreds of MB of plugins that
  # nothing references.
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      # v2.100+ — required for `control_plane_firewall`, `isolated_workers`
      # and `cluster_autoscaler_configuration` on digitalocean_kubernetes_cluster.
      version = "~> 2.100"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }
    # Only for the handoff in platform-outputs.tf. Nothing else here touches the
    # Kubernetes API.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}
