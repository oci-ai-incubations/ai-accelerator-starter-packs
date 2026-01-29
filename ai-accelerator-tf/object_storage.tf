# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#

resource "oci_objectstorage_bucket" "paas_rag_bucket" {
  count          = var.starter_pack_category == "paas_rag" ? 1 : 0
  compartment_id = var.compartment_ocid
  name           = "paas-rag-${local.deploy_id}-bucket"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Enabled"
  
  lifecycle {
    ignore_changes = []
  }
}

resource "oci_identity_customer_secret_key" "aws_compat_access_key" {
    count           = var.starter_pack_category == "paas_rag" ? 1 : 0
    provider        = oci.home_region
    display_name    = "paas-rag-${local.deploy_id}"
    user_id         = var.current_user_ocid
}