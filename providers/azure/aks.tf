# ---------------------------------------------------------------------------
# AKS Cluster
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "platform" {
  name                         = "aks-${local.base_name}"
  location                     = azurerm_resource_group.platform.location
  resource_group_name          = azurerm_resource_group.platform.name
  dns_prefix                   = "aks-${local.base_name}"
  kubernetes_version           = var.kubernetes_version
  sku_tier                     = var.sku_tier
  automatic_upgrade_channel    = var.auto_upgrade_channel
  run_command_enabled          = var.run_command_enabled
  image_cleaner_enabled        = var.image_cleaner_enabled
  image_cleaner_interval_hours = var.image_cleaner_interval_hours

  # --- Identity ----------------------------------------------------------
  identity {
    type = "SystemAssigned"
  }

  workload_identity_enabled = true
  oidc_issuer_enabled       = true
  local_account_disabled    = var.local_account_disabled

  # --- Azure AD integration -----------------------------------------------
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.aad_managed_enabled ? [1] : []
    content {
      azure_rbac_enabled     = var.azure_rbac_enabled
      admin_group_object_ids = var.aad_admin_group_ids
    }
  }

  # --- Default (system) node pool ----------------------------------------
  default_node_pool {
    name                         = "system"
    node_count                   = var.system_auto_scaling_enabled ? null : var.system_node_count
    vm_size                      = var.system_vm_size
    vnet_subnet_id               = azurerm_subnet.aks_nodes.id
    os_disk_size_gb              = var.system_os_disk_size_gb
    os_disk_type                 = var.system_os_disk_type
    zones                        = var.availability_zones
    auto_scaling_enabled         = var.system_auto_scaling_enabled
    min_count                    = var.system_auto_scaling_enabled ? var.system_min_count : null
    max_count                    = var.system_auto_scaling_enabled ? var.system_max_count : null
    only_critical_addons_enabled = var.only_critical_addons_enabled
    temporary_name_for_rotation  = "systemtmp"

    upgrade_settings {
      max_surge = var.system_max_surge
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
    authorized_ip_ranges = var.nat_gateway_enabled ? concat(
      local.authorized_ips,
      ["${azurerm_public_ip.nat_gateway[0].ip_address}/32"]
    ) : local.authorized_ips
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

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Additional node pool – Spot (preferred for platform workloads)
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "platform_spot" {
  count                       = var.workload_spot_enabled ? 1 : 0
  name                        = "platformsp"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.platform.id
  vm_size                     = var.workload_vm_size
  vnet_subnet_id              = azurerm_subnet.aks_nodes.id
  os_disk_size_gb             = var.workload_os_disk_size_gb
  os_disk_type                = var.workload_os_disk_type
  zones                       = var.availability_zones
  temporary_name_for_rotation = "platspttmp"

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = var.spot_max_price

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
  tags = local.tags

  lifecycle {
    ignore_changes = [
      node_labels["kubernetes.azure.com/scalesetpriority"],
      upgrade_settings,
    ]
  }
}

# ---------------------------------------------------------------------------
# Additional node pool – Regular (platform components run here)
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "platform_regular" {
  count                       = var.workload_regular_enabled ? 1 : 0
  name                        = "platformrg"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.platform.id
  vm_size                     = var.workload_vm_size
  vnet_subnet_id              = azurerm_subnet.aks_nodes.id
  os_disk_size_gb             = var.workload_os_disk_size_gb
  os_disk_type                = var.workload_os_disk_type
  zones                       = var.availability_zones
  temporary_name_for_rotation = "platrgtmp"

  priority = "Regular"

  auto_scaling_enabled = true
  min_count            = 1
  max_count            = var.workload_regular_max_count

  upgrade_settings {
    max_surge                     = var.workload_max_surge
    drain_timeout_in_minutes      = var.workload_drain_timeout_in_minutes
    node_soak_duration_in_minutes = var.workload_node_soak_duration_in_minutes
  }

  node_labels = {
    "estabilis.io/workload-type" = "platform"
    "estabilis.io/pool-type"     = "regular"
  }
  tags = local.tags
}

# ---------------------------------------------------------------------------
# Azure RBAC — role assignments on the AKS cluster
# Available roles:
#   - Azure Kubernetes Service Cluster Admin Role (full access)
#   - Azure Kubernetes Service Cluster User Role (get credentials)
#   - Azure Kubernetes Service RBAC Admin (manage K8s RBAC)
#   - Azure Kubernetes Service RBAC Cluster Admin (cluster-admin via RBAC)
#   - Azure Kubernetes Service RBAC Reader (read-only K8s resources)
#   - Azure Kubernetes Service RBAC Writer (read + write K8s resources)
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "aks_rbac" {
  count                = var.aad_managed_enabled && var.azure_rbac_enabled ? length(var.aks_role_assignments) : 0
  scope                = azurerm_kubernetes_cluster.platform.id
  role_definition_name = var.aks_role_assignments[count.index].role
  principal_id         = var.aks_role_assignments[count.index].principal_id
}
