terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.1"
    }
    # v0.62.0 — required by cilium.tf (BYO Cilium install when network_dataplane="byo-cni").
    # Hard-pinned to align with workload module (no minor drift across managed clusters).
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.5"
    }
  }
}
