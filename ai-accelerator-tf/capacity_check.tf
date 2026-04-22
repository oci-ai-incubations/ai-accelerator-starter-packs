# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Compute Capacity Pre-Check
# This runs FIRST before any resource provisioning to validate capacity exists.
# Checks all availability domains in the region to ensure capacity is available.

# -----------------------------------------------------------------------------
# Capacity Reports - Check availability for each shape needed across all ADs
# -----------------------------------------------------------------------------

# GPU Worker Node Capacity Check (BM.GPU4.8 for cuopt/vss) - Check all ADs
resource "oci_core_compute_capacity_report" "gpu_worker_capacity" {
  for_each = !local.run_capacity_checks ? {} : (
    local.starter_pack_config.worker_node_shape != "none" ?
    { for ad in data.oci_identity_availability_domains.ads.availability_domains : ad.name => ad } : {}
  )

  availability_domain = each.value.name
  compartment_id      = var.compartment_ocid

  shape_availabilities {
    instance_shape = local.starter_pack_config.worker_node_shape
  }
}

# Control Plane Node Pool Capacity Check (VM.Standard.E5.Flex) - Check all ADs
resource "oci_core_compute_capacity_report" "control_plane_capacity" {
  for_each = !local.run_capacity_checks ? {} : {
    for ad in data.oci_identity_availability_domains.ads.availability_domains : ad.name => ad
  }

  availability_domain = each.value.name
  compartment_id      = var.compartment_ocid

  shape_availabilities {
    instance_shape = local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape

    instance_shape_config {
      ocpus         = local.starter_pack_config.control_plane_node_pool_instance_shape.ocpus
      memory_in_gbs = local.starter_pack_config.control_plane_node_pool_instance_shape.memory
    }
  }
}

# CPU Worker Node Pool Capacity Check (VM.Standard.E5.Flex - only when needed) - Check all ADs
resource "oci_core_compute_capacity_report" "cpu_worker_capacity" {
  for_each = !local.run_capacity_checks ? {} : (
    local.starter_pack_config.cpu_worker_node_pool_size > 0 ?
    { for ad in data.oci_identity_availability_domains.ads.availability_domains : ad.name => ad } : {}
  )

  availability_domain = each.value.name
  compartment_id      = var.compartment_ocid

  shape_availabilities {
    instance_shape = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape

    instance_shape_config {
      ocpus         = local.starter_pack_config.cpu_worker_node_pool_instance_shape.ocpus
      memory_in_gbs = local.starter_pack_config.cpu_worker_node_pool_instance_shape.memory
    }
  }
}

# Bastion Instance Capacity Check (VM.Standard.E5.Flex) - Check all ADs
resource "oci_core_compute_capacity_report" "bastion_capacity" {
  for_each = !local.run_capacity_checks ? {} : (
    local.create_bastion_effective ?
    { for ad in data.oci_identity_availability_domains.ads.availability_domains : ad.name => ad } : {}
  )

  availability_domain = each.value.name
  compartment_id      = var.compartment_ocid

  shape_availabilities {
    instance_shape = var.bastion_instance_shape.instanceShape

    instance_shape_config {
      ocpus         = var.bastion_instance_shape.ocpus
      memory_in_gbs = var.bastion_instance_shape.memory
    }
  }
}

# Operator Instance Capacity Check (VM.Standard.E5.Flex) - Check all ADs
resource "oci_core_compute_capacity_report" "operator_capacity" {
  for_each = !local.run_capacity_checks ? {} : (
    local.create_bastion_effective ?
    { for ad in data.oci_identity_availability_domains.ads.availability_domains : ad.name => ad } : {}
  )

  availability_domain = each.value.name
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
  # Check if capacity is available in ANY availability domain
  gpu_worker_available = var.skip_capacity_check ? true : (
    local.starter_pack_config.worker_node_shape == "none" ? true : (
      length(oci_core_compute_capacity_report.gpu_worker_capacity) > 0 ?
      anytrue([
        for report in oci_core_compute_capacity_report.gpu_worker_capacity :
        report.shape_availabilities[0].availability_status == "AVAILABLE" && report.availability_domain == var.worker_node_availability_domain
      ]) : true
    )
  )

  control_plane_available = var.skip_capacity_check ? true : (
    length(oci_core_compute_capacity_report.control_plane_capacity) > 0 ?
    anytrue([
      for report in oci_core_compute_capacity_report.control_plane_capacity :
      report.shape_availabilities[0].availability_status == "AVAILABLE"
    ]) : true
  )

  cpu_worker_available = var.skip_capacity_check ? true : (
    local.starter_pack_config.cpu_worker_node_pool_size == 0 ? true : (
      length(oci_core_compute_capacity_report.cpu_worker_capacity) > 0 ?
      anytrue([
        for report in oci_core_compute_capacity_report.cpu_worker_capacity :
        report.shape_availabilities[0].availability_status == "AVAILABLE"
      ]) : true
    )
  )

  bastion_available = var.skip_capacity_check ? true : (
    !local.create_bastion_effective ? true : (
      length(oci_core_compute_capacity_report.bastion_capacity) > 0 ?
      anytrue([
        for report in oci_core_compute_capacity_report.bastion_capacity :
        report.shape_availabilities[0].availability_status == "AVAILABLE"
      ]) : true
    )
  )

  operator_available = var.skip_capacity_check ? true : (
    !local.create_bastion_effective ? true : (
      length(oci_core_compute_capacity_report.operator_capacity) > 0 ?
      anytrue([
        for report in oci_core_compute_capacity_report.operator_capacity :
        report.shape_availabilities[0].availability_status == "AVAILABLE"
      ]) : true
    )
  )

  # Use the user-provided availability domain for worker nodes
  # For GPU starter packs, this is required. For paas_rag (worker_node_shape == "none"), it's optional.
  # Capacity checking will validate this AD has capacity when skip_capacity_check is false
  worker_node_availability_domain = var.worker_node_availability_domain != "" ? var.worker_node_availability_domain : (
    # Fallback to first AD if not provided (only for paas_rag)
    data.oci_identity_availability_domains.ads.availability_domains[0].name
  )

  # Overall capacity validation
  # Exclude GPU workers from validation if worker_node_shape is "none"
  all_capacity_available = (
    # (local.starter_pack_config.worker_node_shape == "none" || local.gpu_worker_available) &&
    local.gpu_worker_available &&
    local.control_plane_available &&
    local.cpu_worker_available &&
    local.bastion_available &&
    local.operator_available
  )

  # Build detailed capacity status message with AD breakdown
  capacity_error_message = <<-EOT

============================================================
CAPACITY CHECK FAILED
============================================================

Starter Pack: ${var.starter_pack_category} (${var.starter_pack_size})
Region: ${var.region}
Availability Domains Checked: ${length(data.oci_identity_availability_domains.ads.availability_domains)}

Required Capacity Status:
%{if local.starter_pack_config.worker_node_shape != "none"~}
  GPU Worker Nodes:
    Shape: ${local.starter_pack_config.worker_node_shape}
    Quantity: ${local.starter_pack_config.worker_node_pool_size}
    Status: ${local.gpu_worker_available ? "AVAILABLE in at least one AD" : "NOT AVAILABLE in any AD"}
%{if length(oci_core_compute_capacity_report.gpu_worker_capacity) > 0~}
    AD Details:
%{for ad_name, report in oci_core_compute_capacity_report.gpu_worker_capacity~}
      - ${ad_name}: ${report.shape_availabilities[0].availability_status}
%{endfor~}
%{endif~}
%{endif~}
  Control Plane Nodes:
    Shape: ${local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape}
    OCPUs: ${local.starter_pack_config.control_plane_node_pool_instance_shape.ocpus}
    Memory: ${local.starter_pack_config.control_plane_node_pool_instance_shape.memory} GB
    Quantity: ${local.starter_pack_config.control_plane_node_pool_size}
    Status: ${local.control_plane_available ? "AVAILABLE in at least one AD" : "NOT AVAILABLE in any AD"}
%{if length(oci_core_compute_capacity_report.control_plane_capacity) > 0~}
    AD Details:
%{for ad_name, report in oci_core_compute_capacity_report.control_plane_capacity~}
      - ${ad_name}: ${report.shape_availabilities[0].availability_status}
%{endfor~}
%{endif~}
%{if local.starter_pack_config.cpu_worker_node_pool_size > 0~}
  CPU Worker Nodes:
    Shape: ${local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape}
    OCPUs: ${local.starter_pack_config.cpu_worker_node_pool_instance_shape.ocpus}
    Memory: ${local.starter_pack_config.cpu_worker_node_pool_instance_shape.memory} GB
    Quantity: ${local.starter_pack_config.cpu_worker_node_pool_size}
    Status: ${local.cpu_worker_available ? "AVAILABLE in at least one AD" : "NOT AVAILABLE in any AD"}
%{if length(oci_core_compute_capacity_report.cpu_worker_capacity) > 0~}
    AD Details:
%{for ad_name, report in oci_core_compute_capacity_report.cpu_worker_capacity~}
      - ${ad_name}: ${report.shape_availabilities[0].availability_status}
%{endfor~}
%{endif~}
%{endif~}
%{if local.create_bastion_effective~}
  Bastion Instance:
    Shape: ${var.bastion_instance_shape.instanceShape}
    Status: ${local.bastion_available ? "AVAILABLE in at least one AD" : "NOT AVAILABLE in any AD"}
%{if length(oci_core_compute_capacity_report.bastion_capacity) > 0~}
    AD Details:
%{for ad_name, report in oci_core_compute_capacity_report.bastion_capacity~}
      - ${ad_name}: ${report.shape_availabilities[0].availability_status}
%{endfor~}
%{endif~}

  Operator Instance:
    Shape: ${var.operator_instance_shape.instanceShape}
    Status: ${local.operator_available ? "AVAILABLE in at least one AD" : "NOT AVAILABLE in any AD"}
%{if length(oci_core_compute_capacity_report.operator_capacity) > 0~}
    AD Details:
%{for ad_name, report in oci_core_compute_capacity_report.operator_capacity~}
      - ${ad_name}: ${report.shape_availabilities[0].availability_status}
%{endfor~}
%{endif~}
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
  count = local.deploy_infrastructure ? 1 : 0

  # This resource validates capacity and acts as a dependency gate

  lifecycle {
    # Require worker_node_availability_domain for GPU starter packs (when worker_node_shape != "none")
    precondition {
      condition     = local.starter_pack_config.worker_node_shape == "none" || var.worker_node_availability_domain != ""
      error_message = "worker_node_availability_domain is required for GPU starter packs (cuopt, vss, enterprise_rag, nemoclaw self_hosted). It is optional for paas_rag and nemoclaw API providers."
    }

    # Validate that the provided AD exists in the region (only if provided)
    precondition {
      condition     = var.worker_node_availability_domain == "" || contains([for ad in data.oci_identity_availability_domains.ads.availability_domains : ad.name], var.worker_node_availability_domain)
      error_message = "The provided worker_node_availability_domain '${var.worker_node_availability_domain}' is not a valid availability domain in region ${var.region}. Valid ADs: ${join(", ", [for ad in data.oci_identity_availability_domains.ads.availability_domains : ad.name])}"
    }

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
    null_resource.capacity_registration,
    oci_core_compute_capacity_report.gpu_worker_capacity,
    oci_core_compute_capacity_report.control_plane_capacity,
    oci_core_compute_capacity_report.cpu_worker_capacity,
    oci_core_compute_capacity_report.bastion_capacity,
    oci_core_compute_capacity_report.operator_capacity
  ]
}

