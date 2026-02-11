
locals {
  # https://cloudinit.readthedocs.io/en/latest/explanation/format.html#mime-multi-part-archive
  default_cloud_init_content_type = "text/x-shellscript"

  # https://canonical-cloud-init.readthedocs-hosted.com/en/latest/reference/merging.html
  default_cloud_init_merge_type = "list(append)+dict(no_replace,recurse_list)+str(append)"
}

data "cloudinit_config" "workers" {
  gzip          = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content      = yamlencode(local.cloud_init)
  }
}

resource "oci_core_instance_configuration" "worker_nodes_configuration" {
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-Worker-Nodes-Configuration-${random_string.deploy_id.result}"
  instance_details {
    instance_type = "compute"
    launch_details {
      compartment_id           = var.compartment_ocid
      is_ai_enterprise_enabled = local.starter_pack_config.nvaie_enabled
      display_name             = "AI-Accel-Worker-Node-${random_string.deploy_id.result}"
      shape                    = local.starter_pack_config.worker_node_shape
      source_details {
        source_type             = "image"
        image_id                = oci_core_image.nvidia_image[0].id
        boot_volume_size_in_gbs = 500
      }
      agent_config {
        are_all_plugins_disabled = false
        is_management_disabled   = false
        is_monitoring_disabled   = false
        plugins_config {
          desired_state = "ENABLED"
          name          = "Management Agent"
        }
        plugins_config {
          desired_state = "ENABLED"
          name          = "Compute Instance Monitoring"
        }
        plugins_config {
          desired_state = "ENABLED"
          name          = "Custom Logs Monitoring"
        }
      }
      metadata = {
        user_data = data.cloudinit_config.workers.rendered
      }
    }
  }

  depends_on = [oci_core_image.nvidia_image, terraform_data.capacity_validated]
  count      = local.should_import_nvidia_gpu_image ? 1 : 0

  lifecycle {
    ignore_changes = [
      instance_details[0].launch_details[0].metadata["user_data"]
    ]
  }
}

resource "oci_core_instance_pool" "worker_nodes_pool" {
  compartment_id            = var.compartment_ocid
  display_name              = "AI-Accel-Worker-Nodes-Pool-${random_string.deploy_id.result}"
  instance_configuration_id = oci_core_instance_configuration.worker_nodes_configuration[0].id
  size                      = local.starter_pack_config.worker_node_pool_size
  placement_configurations {
    availability_domain = local.worker_node_availability_domain
    primary_subnet_id   = oci_core_subnet.oke_nodes_subnet[0].id
  }
  depends_on = [oci_containerengine_cluster.oke_cluster, oci_core_instance_configuration.worker_nodes_configuration, terraform_data.capacity_validated]
  count      = local.should_import_nvidia_gpu_image ? 1 : 0
}

resource "oci_core_cluster_network" "worker_nodes_cluster_network" {
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-Worker-Nodes-Cluster-Network-${random_string.deploy_id.result}"
  instance_pools {
    instance_configuration_id = oci_core_instance_configuration.worker_nodes_configuration[0].id
    size                      = local.starter_pack_config.worker_node_pool_size
  }
  dynamic "placement_configuration" {
    for_each = data.oci_identity_availability_domains.ads.availability_domains
    content {
      availability_domain = placement_configuration.value.name
      primary_subnet_id   = local.node_subnet_id
    }
  }
  depends_on = [oci_containerengine_cluster.oke_cluster, oci_core_instance_configuration.worker_nodes_configuration, terraform_data.capacity_validated]
  count      = 0
}


locals {
  ssh_authorized_keys = compact([
    trimspace(var.ssh_public_key),
  ])
  runcmd_bootstrap_script = format(
    "bash /var/run/worker_node_bootstrap.sh '%v' || echo 'Error bootstrapping OKE' >&2",
    var.k8s_version
  )
  runcmd_bootstrap = format(
    "curl -sL -o /var/run/oke-ubuntu-cloud-init.sh https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/files/oke-ubuntu-cloud-init.sh && (bash /var/run/oke-ubuntu-cloud-init.sh '%v' '%v' '%v' || echo 'Error bootstrapping OKE' >&2)",
    var.k8s_version, var.setup_credential_provider_for_ocir, var.override_hostnames
  )
  runcmd_nvme_raid = format(
    "curl -sL -o /var/run/oke-nvme-raid.sh https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/files/oke-nvme-raid.sh && (bash /var/run/oke-nvme-raid.sh '%v' || echo 'Error initializing RAID' >&2)",
    var.nvme_raid_level
  )
  write_files = [
    {
      content = local.cluster_endpoint_private,
      path    = "/etc/oke/oke-apiserver",
    },
    {
      encoding    = "b64",
      content     = base64encode(local.cluster_ca_certificate),
      owner       = "root:root"
      path        = "/etc/kubernetes/ca.crt"
      permissions = "0644"
    },
    {
      content     = file("${path.module}/scripts/worker_node_bootstrap.sh"),
      path        = "/var/run/worker_node_bootstrap.sh"
      permissions = "0755"
      owner       = "root:root"
    }
  ]

  # These commands must be executed in this order. If you change runcmd_nvme_raid to run second, it changes the mount location of the kubelet.
  # This happens after kubelet is started by bootstrap, and so all pods after that will fail to start because they cannot find the volume (because it has moved).
  cloud_init = {
    ssh_authorized_keys = local.ssh_authorized_keys
    runcmd              = compact([local.runcmd_nvme_raid, local.runcmd_bootstrap_script]) # These commands must be executed in this order. 
    write_files         = local.write_files
  }
}