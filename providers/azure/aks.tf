# ---------------------------------------------------------------------------
# AKS Cluster
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "platform" {
  name                = "aks-${var.name_prefix}-platform"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  dns_prefix          = "aks-${var.name_prefix}-platform"
  kubernetes_version  = var.kubernetes_version

  # --- Identity ----------------------------------------------------------
  identity {
    type = "SystemAssigned"
  }

  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # --- Default (system) node pool ----------------------------------------
  default_node_pool {
    name                        = "system"
    node_count                  = var.system_node_count
    vm_size                     = var.system_vm_size
    vnet_subnet_id              = azurerm_subnet.aks_nodes.id
    os_disk_size_gb             = var.system_os_disk_size_gb
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # --- Network profile ---------------------------------------------------
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    pod_cidr            = var.pod_cidr
  }

  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Additional node pool – platform workloads (Spot)
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "platform_wl" {
  name                        = "platformwl"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.platform.id
  vm_size                     = var.workload_vm_size
  node_count                  = var.workload_node_count
  vnet_subnet_id              = azurerm_subnet.aks_nodes.id
  os_disk_size_gb             = var.workload_os_disk_size_gb
  temporary_name_for_rotation = "plattmp"

  # Spot configuration (only when workload_priority = "Spot")
  priority        = var.workload_priority
  eviction_policy = var.workload_priority == "Spot" ? "Delete" : null
  spot_max_price  = var.workload_priority == "Spot" ? -1 : null

  # Taints & labels so only platform workloads land here
  node_labels = {
    "estabilis.io/workload-type" = "platform"
  }

  node_taints = [
    "estabilis.io/workload-type=platform:NoSchedule"
  ]

  tags = var.tags
}
