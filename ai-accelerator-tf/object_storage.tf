# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#

resource "oci_objectstorage_bucket" "paas_rag_bucket" {
  count          = var.starter_pack_category == "paas_rag" ? 1 : 0
  compartment_id = var.compartment_ocid
  name           = "paas-rag-${local.deploy_id}-bucket"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  access_type    = var.bucket_access_type
  storage_tier   = var.bucket_storage_tier
  versioning     = "Enabled"
  
  lifecycle {
    ignore_changes = []
  }
}

resource "oci_identity_customer_secret_key" "oci_identity_customer_secret_key" {
    display_name = "paas-rag-${local.deploy_id}"
    user_id = data.oci_identity_user.user.user_id
}