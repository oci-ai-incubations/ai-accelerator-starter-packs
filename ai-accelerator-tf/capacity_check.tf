# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Compute Capacity Pre-Check
# This runs FIRST before any resource provisioning to validate capacity exists.

# Get the first availability domain for capacity checks
data "oci_identity_availability_domain" "ad" {
  compartment_id = var.tenancy_ocid
  ad_number      = 1
}

# -----------------------------------------------------------------------------
# Capacity Reports - Check availability for each shape needed
# -----------------------------------------------------------------------------

# GPU Worker Node Capacity Check (BM.GPU4.8 for cuopt/vss)
resource "oci_core_compute_capacity_report" "gpu_worker_capacity" {
  count = var.skip_capacity_check ? 0 : (local.starter_pack_config.worker_node_shape != "none" ? 1 : 0)

  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid

  shape_availabilities {
    instance_shape = local.starter_pack_config.worker_node_shape
  }
}

# Control Plane Node Pool Capacity Check (VM.Standard.E5.Flex)
resource "oci_core_compute_capacity_report" "control_plane_capacity" {
  count = var.skip_capacity_check ? 0 : 1

  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid

  shape_availabilities {
    instance_shape = local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape

    instance_shape_config {
      ocpus         = local.starter_pack_config.control_plane_node_pool_instance_shape.ocpus
      memory_in_gbs = local.starter_pack_config.control_plane_node_pool_instance_shape.memory
    }
  }
}

# CPU Worker Node Pool Capacity Check (VM.Standard.E5.Flex - only when needed)
resource "oci_core_compute_capacity_report" "cpu_worker_capacity" {
  count = var.skip_capacity_check ? 0 : (local.starter_pack_config.cpu_worker_node_pool_size > 0 ? 1 : 0)

  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid

  shape_availabilities {
    instance_shape = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape

    instance_shape_config {
      ocpus         = local.starter_pack_config.cpu_worker_node_pool_instance_shape.ocpus
      memory_in_gbs = local.starter_pack_config.cpu_worker_node_pool_instance_shape.memory
    }
  }
}

# Bastion Instance Capacity Check (VM.Standard.E5.Flex)
resource "oci_core_compute_capacity_report" "bastion_capacity" {
  count = var.skip_capacity_check ? 0 : (var.create_bastion ? 1 : 0)

  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid

  shape_availabilities {
    instance_shape = var.bastion_instance_shape.instanceShape

    instance_shape_config {
      ocpus         = var.bastion_instance_shape.ocpus
      memory_in_gbs = var.bastion_instance_shape.memory
    }
  }
}

# Operator Instance Capacity Check (VM.Standard.E5.Flex)
resource "oci_core_compute_capacity_report" "operator_capacity" {
  count = var.skip_capacity_check ? 0 : (var.create_bastion ? 1 : 0)

  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid

  shape_availabilities {
    instance_shape = var.operator_instance_shape.instanceShape

    instance_shape_config {
      ocpus         = var.operator_instance_shape.ocpus
      memory_in_gbs = var.operator_instance_shape.memory
    }
  }
}

# -----------------------------------------------------------------------------
# Locals for capacity status extraction
# -----------------------------------------------------------------------------
locals {
  # Extract availability status from each capacity report
  gpu_worker_available = var.skip_capacity_check ? true : (
    local.starter_pack_config.worker_node_shape == "none" ? true : (
      length(oci_core_compute_capacity_report.gpu_worker_capacity) > 0 ?
      oci_core_compute_capacity_report.gpu_worker_capacity[0].shape_availabilities[0].availability_status == "AVAILABLE" : true
    )
  )

  control_plane_available = var.skip_capacity_check ? true : (
    length(oci_core_compute_capacity_report.control_plane_capacity) > 0 ?
    oci_core_compute_capacity_report.control_plane_capacity[0].shape_availabilities[0].availability_status == "AVAILABLE" : true
  )

  cpu_worker_available = var.skip_capacity_check ? true : (
    local.starter_pack_config.cpu_worker_node_pool_size == 0 ? true : (
      length(oci_core_compute_capacity_report.cpu_worker_capacity) > 0 ?
      oci_core_compute_capacity_report.cpu_worker_capacity[0].shape_availabilities[0].availability_status == "AVAILABLE" : true
    )
  )

  bastion_available = var.skip_capacity_check ? true : (
    !var.create_bastion ? true : (
      length(oci_core_compute_capacity_report.bastion_capacity) > 0 ?
      oci_core_compute_capacity_report.bastion_capacity[0].shape_availabilities[0].availability_status == "AVAILABLE" : true
    )
  )

  operator_available = var.skip_capacity_check ? true : (
    !var.create_bastion ? true : (
      length(oci_core_compute_capacity_report.operator_capacity) > 0 ?
      oci_core_compute_capacity_report.operator_capacity[0].shape_availabilities[0].availability_status == "AVAILABLE" : true
    )
  )

  # Overall capacity validation
  all_capacity_available = (
    local.gpu_worker_available &&
    local.control_plane_available &&
    local.cpu_worker_available &&
    local.bastion_available &&
    local.operator_available
  )

  # Build detailed capacity status message
  capacity_error_message = <<-EOT

============================================================
CAPACITY CHECK FAILED
============================================================

Starter Pack: ${var.starter_pack_category} (${var.starter_pack_size})
Region: ${var.region}

Required Capacity Status:
%{if local.starter_pack_config.worker_node_shape != "none"~}
  GPU Worker Nodes:
    Shape: ${local.starter_pack_config.worker_node_shape}
    Quantity: ${local.starter_pack_config.worker_node_pool_size}
    Status: ${local.gpu_worker_available ? "AVAILABLE" : "NOT AVAILABLE"}
%{endif~}
  Control Plane Nodes:
    Shape: ${local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape}
    OCPUs: ${local.starter_pack_config.control_plane_node_pool_instance_shape.ocpus}
    Memory: ${local.starter_pack_config.control_plane_node_pool_instance_shape.memory} GB
    Quantity: ${local.starter_pack_config.control_plane_node_pool_size}
    Status: ${local.control_plane_available ? "AVAILABLE" : "NOT AVAILABLE"}
%{if local.starter_pack_config.cpu_worker_node_pool_size > 0~}
  CPU Worker Nodes:
    Shape: ${local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape}
    OCPUs: ${local.starter_pack_config.cpu_worker_node_pool_instance_shape.ocpus}
    Memory: ${local.starter_pack_config.cpu_worker_node_pool_instance_shape.memory} GB
    Quantity: ${local.starter_pack_config.cpu_worker_node_pool_size}
    Status: ${local.cpu_worker_available ? "AVAILABLE" : "NOT AVAILABLE"}
%{endif~}
%{if var.create_bastion~}
  Bastion Instance:
    Shape: ${var.bastion_instance_shape.instanceShape}
    Status: ${local.bastion_available ? "AVAILABLE" : "NOT AVAILABLE"}

  Operator Instance:
    Shape: ${var.operator_instance_shape.instanceShape}
    Status: ${local.operator_available ? "AVAILABLE" : "NOT AVAILABLE"}
%{endif~}

Please contact your Oracle sales representative to help
allocate quota and find a region with proper capacity for
this AI Accelerator pack.

============================================================

EOT
}

# -----------------------------------------------------------------------------
# Validation Resource - This is what other resources depend on
# -----------------------------------------------------------------------------
resource "terraform_data" "capacity_validated" {
  # This resource validates capacity and acts as a dependency gate

  lifecycle {
    precondition {
      condition     = var.skip_capacity_check || local.gpu_worker_available
      error_message = "Insufficient capacity for GPU worker nodes (${local.starter_pack_config.worker_node_shape}) in region ${var.region}.${local.capacity_error_message}"
    }

    precondition {
      condition     = var.skip_capacity_check || local.control_plane_available
      error_message = "Insufficient capacity for control plane nodes (${local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape}) in region ${var.region}.${local.capacity_error_message}"
    }

    precondition {
      condition     = var.skip_capacity_check || local.cpu_worker_available
      error_message = "Insufficient capacity for CPU worker nodes (${local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape}) in region ${var.region}.${local.capacity_error_message}"
    }

    precondition {
      condition     = var.skip_capacity_check || local.bastion_available
      error_message = "Insufficient capacity for bastion instance (${var.bastion_instance_shape.instanceShape}) in region ${var.region}.${local.capacity_error_message}"
    }

    precondition {
      condition     = var.skip_capacity_check || local.operator_available
      error_message = "Insufficient capacity for operator instance (${var.operator_instance_shape.instanceShape}) in region ${var.region}.${local.capacity_error_message}"
    }
  }

  depends_on = [
    oci_core_compute_capacity_report.gpu_worker_capacity,
    oci_core_compute_capacity_report.control_plane_capacity,
    oci_core_compute_capacity_report.cpu_worker_capacity,
    oci_core_compute_capacity_report.bastion_capacity,
    oci_core_compute_capacity_report.operator_capacity
  ]
}

