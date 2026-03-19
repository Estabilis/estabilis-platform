# ---------------------------------------------------------------------------
# AKS Cluster
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "platform" {
  name                      = "aks-${var.name_prefix}-platform"
  location                  = azurerm_resource_group.platform.location
  resource_group_name       = azurerm_resource_group.platform.name
  dns_prefix                = "aks-${var.name_prefix}-platform"
  kubernetes_version        = var.kubernetes_version
  sku_tier                  = var.sku_tier
  automatic_upgrade_channel = var.auto_upgrade_channel

  # --- Identity ----------------------------------------------------------
  identity {
    type = "SystemAssigned"
  }

  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # --- Default (system) node pool ----------------------------------------
  default_node_pool {
    name                        = "system"
    node_count                  = var.system_auto_scaling_enabled ? null : var.system_node_count
    vm_size                     = var.system_vm_size
    vnet_subnet_id              = azurerm_subnet.aks_nodes.id
    os_disk_size_gb             = var.system_os_disk_size_gb
    os_disk_type                = var.os_disk_type
    zones                       = var.availability_zones
    auto_scaling_enabled        = var.system_auto_scaling_enabled
    min_count                   = var.system_auto_scaling_enabled ? var.system_min_count : null
    max_count                   = var.system_auto_scaling_enabled ? var.system_max_count : null
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # --- Network profile ---------------------------------------------------
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    outbound_type       = var.nat_gateway_enabled ? "userAssignedNATGateway" : "loadBalancer"
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    pod_cidr            = var.pod_cidr
  }

  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges
  }

  dynamic "monitor_metrics" {
    for_each = var.azure_monitor_enabled ? [1] : []
    content {}
  }

  dynamic "oms_agent" {
    for_each = var.azure_monitor_enabled && var.diagnostics_enabled ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id
    }
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = var.maintenance_window_day
    start_time  = format("%02d:00", var.maintenance_window_start_hour)
    duration    = var.maintenance_window_duration
    utc_offset  = "+00:00"
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = var.maintenance_window_day
    start_time  = format("%02d:00", var.maintenance_window_start_hour)
    duration    = var.maintenance_window_duration
    utc_offset  = "+00:00"
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.aks_nodes,
    azurerm_subnet_network_security_group_association.aks_nodes,
  ]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Additional node pool – Spot (preferred for platform workloads)
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "platform_spot" {
  name                        = "platformsp"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.platform.id
  vm_size                     = var.workload_vm_size
  vnet_subnet_id              = azurerm_subnet.aks_nodes.id
  os_disk_size_gb             = var.workload_os_disk_size_gb
  os_disk_type                = var.os_disk_type
  zones                       = var.availability_zones
  temporary_name_for_rotation = "platspttmp"

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = var.workload_spot_max_count

  node_labels = {
    "estabilis.io/workload-type" = "platform"
    "estabilis.io/pool-type"     = "spot"
  }
  node_taints = [
    "estabilis.io/workload-type=platform:NoSchedule",
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule",
  ]
  tags = var.tags

  lifecycle {
    ignore_changes = [
      node_labels["kubernetes.azure.com/scalesetpriority"],
      upgrade_settings,
    ]
  }
}

# ---------------------------------------------------------------------------
# Additional node pool – Regular (fallback, always has min 1 node)
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "platform_regular" {
  name                        = "platformrg"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.platform.id
  vm_size                     = var.workload_vm_size
  vnet_subnet_id              = azurerm_subnet.aks_nodes.id
  os_disk_size_gb             = var.workload_os_disk_size_gb
  os_disk_type                = var.os_disk_type
  zones                       = var.availability_zones
  temporary_name_for_rotation = "platrgtmp"

  priority = "Regular"

  auto_scaling_enabled = true
  min_count            = 1
  max_count            = var.workload_regular_max_count

  upgrade_settings {
    max_surge                     = "10%"
    drain_timeout_in_minutes      = 0
    node_soak_duration_in_minutes = 0
  }

  node_labels = {
    "estabilis.io/workload-type" = "platform"
    "estabilis.io/pool-type"     = "regular"
  }
  node_taints = [
    "estabilis.io/workload-type=platform:NoSchedule",
  ]
  tags = var.tags
}
