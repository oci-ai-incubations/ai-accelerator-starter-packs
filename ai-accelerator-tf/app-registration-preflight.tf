# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Stage 1: Pre-flight Registration
# Captures deployment intent immediately at the start of terraform apply

locals {
  preflight_content = jsonencode({
    registration_id       = random_uuid.registration_id.result
    stage                 = "preflight"
    timestamp             = timestamp()
    tenancy_ocid          = var.tenancy_ocid
    region                = var.region
    compartment_ocid      = var.compartment_ocid
    starter_pack_category = var.starter_pack_category
    starter_pack_size     = var.starter_pack_size
  })

  preflight_filepath = format("%s/%s-preflight", abspath(path.root), random_uuid.registration_id.result)
}

resource "local_file" "preflight_registration" {
  content  = local.preflight_content
  filename = local.preflight_filepath
}

resource "null_resource" "preflight_registration" {
  depends_on = [local_file.preflight_registration]

  provisioner "local-exec" {
    command = <<-EOT
      curl -X PUT --data-binary '@${local.preflight_filepath}' \
        ${local.registration_upload_path}preflight.json
    EOT
  }
}

