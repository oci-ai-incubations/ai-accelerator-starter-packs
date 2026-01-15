# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Stage 3: Success Registration
# Captures all resource OCIDs after successful deployment

resource "local_file" "registration" {
  content  = local.registration.object_content
  filename = local.registration.object_filepath
}

resource "null_resource" "success_registration" {
  depends_on = [
    kubernetes_deployment_v1.corrino_cp_deployment,
    local_file.registration,
    # Key resources to ensure they're all created
    oci_containerengine_cluster.oke_cluster,
    oci_containerengine_cluster.oke_cluster_existing_vcn,
    oci_containerengine_node_pool.oke_node_pool,
  ]

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      curl -X PUT --data-binary '@${local.registration.object_filepath}' \
        ${local.registration_upload_path}success.json
    EOT
  }
}
