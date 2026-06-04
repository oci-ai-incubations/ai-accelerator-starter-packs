# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Stage 2: Post-Capacity-Check Registration
# Captures capacity check results before potential failure
# This runs AFTER capacity reports are generated but BEFORE validation fails

locals {
  capacity_content = jsonencode({
    registration_id       = random_uuid.registration_id.result
    stage                 = "capacity_check"
    timestamp             = timestamp()
    tenancy_ocid          = local.tenancy_ocid
    region                = local.region
    compartment_ocid      = local.compartment_ocid
    starter_pack_category = var.starter_pack_category
    starter_pack_size     = var.starter_pack_size

    # Capacity results
    capacity_available = local.all_capacity_available
    capacity_failed    = !local.all_capacity_available

    # Detailed capacity status
    gpu_worker_available    = local.gpu_worker_available
    control_plane_available = local.control_plane_available
    cpu_worker_available    = local.cpu_worker_available
    bastion_available       = local.bastion_available
    operator_available      = local.operator_available

    # Shape info for debugging
    worker_node_shape     = local.starter_pack_config.worker_node_shape
    worker_node_pool_size = local.starter_pack_config.worker_node_pool_size
  })

  capacity_filepath = format("%s/%s-capacity", abspath(path.root), random_uuid.registration_id.result)
}

resource "local_file" "capacity_registration" {
  count    = local.deploy_infrastructure ? 1 : 0
  content  = local.capacity_content
  filename = local.capacity_filepath

  depends_on = [
    oci_core_compute_capacity_report.gpu_worker_capacity,
    oci_core_compute_capacity_report.control_plane_capacity,
    oci_core_compute_capacity_report.cpu_worker_capacity,
    oci_core_compute_capacity_report.bastion_capacity,
    oci_core_compute_capacity_report.operator_capacity
  ]
}

resource "null_resource" "capacity_registration" {
  count      = local.deploy_infrastructure ? 1 : 0
  depends_on = [local_file.capacity_registration]

  provisioner "local-exec" {
    command = <<-EOT
      curl -X PUT --data-binary '@${local.capacity_filepath}' \
        ${local.registration_upload_path}capacity_check.json
    EOT
  }
}

