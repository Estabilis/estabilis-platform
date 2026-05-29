# ---------------------------------------------------------------------------
# BYO CNI — Self-managed Cilium with Hubble
# Only active when: network_dataplane = "byo-cni"
# IMPORTANT: Changing to byo-cni DESTROYS and RECREATES the cluster.
#            Requires byo_cni_i_understand_this_destroys_the_cluster = true.
#
# Minimum Cilium versions per K8s:
#   K8s 1.34 → Cilium >= 1.18.6
#   K8s 1.35 → Cilium >= 1.18.6
# Ref: https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium
# Ref: https://learn.microsoft.com/en-us/azure/aks/use-byo-cni
#
# Microsoft does NOT support CNI-related issues with BYO CNI.
# Support covers: node/VM availability, scaling, upgrades, storage, LB.
# NOT covered: pod-to-pod traffic, network policies, CNI plugin issues.
#
# v0.62.0 — workload parity (literal port from estabilis-workload cilium.tf).
# ---------------------------------------------------------------------------

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.platform.kube_admin_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.platform.kube_admin_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.platform.kube_admin_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.platform.kube_admin_config[0].cluster_ca_certificate)
  }
}

resource "helm_release" "cilium" {
  count            = var.network_dataplane == "byo-cni" ? 1 : 0
  name             = "cilium"
  namespace        = "kube-system"
  repository       = "https://helm.cilium.io"
  chart            = "cilium"
  version          = var.cilium_version
  create_namespace = false
  wait             = true
  timeout          = 600

  # AKS BYO CNI mode
  set {
    name  = "aksbyocni.enabled"
    value = "true"
  }
  set {
    name  = "nodeinit.enabled"
    value = "true"
  }

  # Disable Azure CNI integration (incompatible with BYO CNI)
  set {
    name  = "azure.enabled"
    value = "false"
  }

  # Replace kube-proxy with Cilium eBPF — set explicitly, do NOT rely on
  # auto-detection (cilium/cilium#38920: AKS leaves residual windows-kube-proxy-initializer)
  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }

  # VXLAN tunnel — default for BYO CNI on AKS (direct routing unavailable)
  # Do NOT use routingMode=native or loadBalancer.mode=dsr (causes prolonged NotReady, cilium/cilium#34601)
  set {
    name  = "tunnelProtocol"
    value = "vxlan"
  }

  # IPAM — pod IP allocation from cluster pool
  set {
    name  = "ipam.mode"
    value = "cluster-pool"
  }
  set {
    name  = "ipam.operator.clusterPoolIPv4PodCIDRList"
    value = "{${var.pod_cidr}}"
  }
  set {
    name  = "ipam.operator.clusterPoolIPv4MaskSize"
    value = "24"
  }

  # Hubble — observability (flow logs, metrics, UI)
  set {
    name  = "hubble.enabled"
    value = "true"
  }
  set {
    name  = "hubble.relay.enabled"
    value = "true"
  }
  set {
    name  = "hubble.ui.enabled"
    value = "true"
  }

  # Prometheus metrics — for Alloy/Mimir scraping
  set {
    name  = "prometheus.enabled"
    value = "true"
  }
  set {
    name  = "operator.prometheus.enabled"
    value = "true"
  }
  set {
    name  = "hubble.metrics.enabled"
    value = "{dns,drop,tcp,flow,icmp,http}"
  }

  # Replicas — operator uses 1 for faster bootstrap (leader election, standby not needed)
  # Hubble relay scales with zones for HA
  set {
    name  = "operator.replicas"
    value = "1"
  }
  set {
    name  = "hubble.relay.replicas"
    value = length(var.system_availability_zones) > 1 ? 2 : 1
  }

  # Tolerations for system pool (CriticalAddonsOnly taint)
  # Agent: already tolerates everything (operator: Exists) — no override needed
  # Operator: set replaces defaults, so we must include all original tolerations + ours
  # Relay/UI: no defaults — need CriticalAddonsOnly + not-ready
  set {
    name  = "operator.tolerations[0].key"
    value = "node-role.kubernetes.io/control-plane"
  }
  set {
    name  = "operator.tolerations[0].operator"
    value = "Exists"
  }
  set {
    name  = "operator.tolerations[1].key"
    value = "node-role.kubernetes.io/master"
  }
  set {
    name  = "operator.tolerations[1].operator"
    value = "Exists"
  }
  set {
    name  = "operator.tolerations[2].key"
    value = "node.kubernetes.io/not-ready"
  }
  set {
    name  = "operator.tolerations[2].operator"
    value = "Exists"
  }
  set {
    name  = "operator.tolerations[3].key"
    value = "node.cloudprovider.kubernetes.io/uninitialized"
  }
  set {
    name  = "operator.tolerations[3].operator"
    value = "Exists"
  }
  set {
    name  = "operator.tolerations[4].key"
    value = "CriticalAddonsOnly"
  }
  set {
    name  = "operator.tolerations[4].operator"
    value = "Exists"
  }
  set {
    name  = "operator.tolerations[4].effect"
    value = "NoSchedule"
  }
  set {
    name  = "hubble.relay.tolerations[0].key"
    value = "CriticalAddonsOnly"
  }
  set {
    name  = "hubble.relay.tolerations[0].operator"
    value = "Exists"
  }
  set {
    name  = "hubble.relay.tolerations[0].effect"
    value = "NoSchedule"
  }
  set {
    name  = "hubble.relay.tolerations[1].key"
    value = "node.kubernetes.io/not-ready"
  }
  set {
    name  = "hubble.relay.tolerations[1].operator"
    value = "Exists"
  }
  set {
    name  = "hubble.relay.tolerations[1].effect"
    value = "NoSchedule"
  }
  set {
    name  = "hubble.ui.tolerations[0].key"
    value = "CriticalAddonsOnly"
  }
  set {
    name  = "hubble.ui.tolerations[0].operator"
    value = "Exists"
  }
  set {
    name  = "hubble.ui.tolerations[0].effect"
    value = "NoSchedule"
  }
  set {
    name  = "hubble.ui.tolerations[1].key"
    value = "node.kubernetes.io/not-ready"
  }
  set {
    name  = "hubble.ui.tolerations[1].operator"
    value = "Exists"
  }
  set {
    name  = "hubble.ui.tolerations[1].effect"
    value = "NoSchedule"
  }

  depends_on = [azurerm_kubernetes_cluster.platform]
}
