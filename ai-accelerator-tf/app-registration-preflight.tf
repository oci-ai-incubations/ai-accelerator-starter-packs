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
  count    = local.deploy_application ? 1 : 0
  content  = local.preflight_content
  filename = local.preflight_filepath
}

resource "null_resource" "preflight_registration" {
  count      = local.deploy_application ? 1 : 0
  depends_on = [local_file.preflight_registration]

  provisioner "local-exec" {
    command = <<-EOT
      curl -X PUT --data-binary '@${local.preflight_filepath}' \
        ${local.registration_upload_path}preflight.json
    EOT
  }
}

# Postflight Registration - Uploads on destroy to track how long the app was up
locals {
  postflight_filepath = format("%s/%s-postflight", abspath(path.root), random_uuid.registration_id.result)
}

resource "null_resource" "postflight_registration" {
  count = local.deploy_application ? 1 : 0
  # Upload postflight data when the resource is destroyed
  # Generate JSON with current timestamp at destroy time
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      cat > ${self.triggers.postflight_filepath} <<EOF
{
  "registration_id": "${self.triggers.registration_id}",
  "stage": "postflight",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "tenancy_ocid": "${self.triggers.tenancy_ocid}",
  "region": "${self.triggers.region}",
  "compartment_ocid": "${self.triggers.compartment_ocid}",
  "starter_pack_category": "${self.triggers.starter_pack_category}",
  "starter_pack_size": "${self.triggers.starter_pack_size}"
}
EOF
      curl -X PUT --data-binary '@${self.triggers.postflight_filepath}' \
        ${self.triggers.registration_upload_path}postflight.json
    EOT
  }

  # Store values needed during destroy
  # Note: These triggers are evaluated at plan/apply time and stored for use during destroy
  triggers = {
    postflight_filepath      = local.postflight_filepath
    registration_upload_path = local.registration_upload_path
    registration_id          = random_uuid.registration_id.result
    tenancy_ocid             = var.tenancy_ocid
    region                   = var.region
    compartment_ocid         = var.compartment_ocid
    starter_pack_category    = var.starter_pack_category
    starter_pack_size        = var.starter_pack_size
  }

  # Prevent unnecessary replacement - only replace if triggers actually change
  lifecycle {
    create_before_destroy = false
  }
}

