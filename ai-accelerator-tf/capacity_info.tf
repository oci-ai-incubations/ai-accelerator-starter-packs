# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Capacity guidance message displayed in Terraform logs during deployment

resource "terraform_data" "capacity_guidance" {
  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "============================================================"
      echo "DEPLOYMENT NOTICE"
      echo "============================================================"
      echo ""
      echo "Starter Pack: ${var.starter_pack_category}"
      echo "Region: ${var.region}"
      echo ""
      echo "Required Capacity:"
      echo "  GPU Worker Nodes:"
      echo "    Shape: ${local.starter_pack_config.worker_node_shape}"
      echo "    Quantity: ${local.starter_pack_config.worker_node_pool_size}"
      echo ""
      echo "  Control Plane Nodes:"
      echo "    Shape: ${local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape}"
      echo "    Quantity: ${local.starter_pack_config.control_plane_node_pool_size}"
      echo ""
      echo "  CPU Worker Nodes:"
      echo "    Shape: ${local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape}"
      echo "    Quantity: ${local.starter_pack_config.cpu_worker_node_pool_size}"
      echo ""
      echo "If this deployment fails, you may be out of capacity in this"
      echo "region or you do not have quota."
      echo ""
      echo "Please contact your Oracle sales representative to help"
      echo "allocate quota and find a region with proper capacity for"
      echo "this AI Accelerator pack."
      echo ""
      echo "============================================================"
      echo ""
    EOT
  }
}

