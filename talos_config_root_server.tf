locals {
  # Root Server Config
  #
  # Generates a per-nodepool machine configuration template. Each root server must
  # be customised before first boot to add a static IPv4 address on the VLAN interface.
  # Use root_server_config_patches to supply per-node network configuration, e.g.:
  #
  #   root_server_config_patches = [
  #     yamlencode({
  #       machine = {
  #         network = {
  #           hostname = "my-cluster-dedicated-01"
  #           interfaces = [{
  #             interface = "bond0"
  #             vlans = [{
  #               vlanId    = 4000
  #               addresses = ["10.0.4.10/24"]
  #               dhcp      = false
  #             }]
  #           }]
  #         }
  #       }
  #     })
  #   ]
  #
  # Node hostnames must follow the pattern "<cluster_name>-<nodepool_name>-<suffix>"
  # for discovery to work when root_server_discovery_enabled = true.
  root_server_talos_config_patches = {
    for nodepool in local.root_server_nodepools : nodepool.name => [
      {
        machine = {
          nodeLabels      = nodepool.labels
          nodeAnnotations = nodepool.annotations
          kubelet = {
            extraConfig = merge(
              {
                registerWithTaints = nodepool.taints
                systemReserved = {
                  cpu               = "100m"
                  memory            = "300Mi"
                  ephemeral-storage = "1Gi"
                }
                kubeReserved = {
                  cpu               = "100m"
                  memory            = "350Mi"
                  ephemeral-storage = "1Gi"
                }
              },
              var.kubernetes_kubelet_extra_config
            )
          }
          network = {
            interfaces = [
              {
                # The physical interface name varies by server model; bond0 is common
                # for Hetzner dedicated servers. Override via root_server_config_patches
                # if your server uses a different interface name (e.g. eth0, enp*).
                interface = "bond0"
                vlans = [
                  {
                    vlanId = nodepool.vlan_id
                    dhcp   = false
                    routes = [
                      {
                        network = local.network_ipv4_cidr
                        gateway = cidrhost(nodepool.ip_range, 1)
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
      }
    ]
  }
}

data "talos_machine_configuration" "root_server" {
  for_each = { for nodepool in local.root_server_nodepools : nodepool.name => nodepool }

  talos_version      = var.talos_version
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.kube_api_url_internal
  kubernetes_version = var.kubernetes_version
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  docs               = false
  examples           = false

  config_patches = concat(
    [for patch in local.talos_base_config_patches : yamlencode(patch)],
    [for patch in local.root_server_talos_config_patches[each.key] : yamlencode(patch)],
    [for patch in var.root_server_config_patches : yamlencode(patch)]
  )
}
