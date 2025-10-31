# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# Bastion Instance
resource "oci_core_instance" "bastion" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "AI-Accel-Bastion-${random_string.deploy_id.result}"
  shape               = var.bastion_instance_shape.instanceShape

  dynamic "shape_config" {
    for_each = length(regexall("Flex", var.bastion_instance_shape.instanceShape)) > 0 ? [1] : []
    content {
      ocpus         = var.bastion_instance_shape.ocpus
      memory_in_gbs = var.bastion_instance_shape.memory
    }
  }

  create_vnic_details {
    subnet_id                 = oci_core_subnet.oke_bastion_subnet[0].id
    display_name              = "AI-Accel-Bastion-VNIC-${random_string.deploy_id.result}"
    assign_public_ip          = true
    assign_private_dns_record = true
    hostname_label            = "bastion"
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id

    boot_volume_size_in_gbs = var.bastion_boot_volume_size_in_gbs
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.oke_ssh_key[0].public_key_openssh
    user_data = base64encode(templatefile("${path.module}/scripts/bastion_bootstrap.sh", {
      operator_private_ip = oci_core_instance.operator[0].private_ip
    }))
  }

  count = local.create_network_resources && var.create_bastion ? 1 : 0

  depends_on = [
    oci_core_subnet.oke_bastion_subnet
  ]
}

# Operator Instance
resource "oci_core_instance" "operator" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "AI-Accel-Operator-${random_string.deploy_id.result}"
  shape               = var.operator_instance_shape.instanceShape

  dynamic "shape_config" {
    for_each = length(regexall("Flex", var.operator_instance_shape.instanceShape)) > 0 ? [1] : []
    content {
      ocpus         = var.operator_instance_shape.ocpus
      memory_in_gbs = var.operator_instance_shape.memory
    }
  }

  create_vnic_details {
    subnet_id                 = oci_core_subnet.oke_operator_subnet[0].id
    display_name              = "AI-Accel-Operator-VNIC-${random_string.deploy_id.result}"
    assign_public_ip          = false
    assign_private_dns_record = true
    hostname_label            = "operator"
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id

    boot_volume_size_in_gbs = var.operator_boot_volume_size_in_gbs
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.oke_ssh_key[0].public_key_openssh
    user_data = base64encode(templatefile("${path.module}/scripts/operator_bootstrap.sh", {
      cluster_id     = local.oke_cluster.id
      region         = var.region
      tenancy_ocid   = var.tenancy_ocid
      compartment_id = var.compartment_ocid
    }))
  }

  count = local.create_network_resources && var.create_bastion ? 1 : 0

  depends_on = [
    oci_core_subnet.oke_operator_subnet,
    oci_containerengine_cluster.oke_cluster,
    oci_containerengine_cluster.oke_cluster_existing_vcn,
  ]
}
