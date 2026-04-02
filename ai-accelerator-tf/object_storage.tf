# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#

resource "oci_objectstorage_bucket" "paas_rag_bucket" {
  count          = local._needs_object_storage ? 1 : 0
  compartment_id = var.compartment_ocid
  name           = "${var.starter_pack_category == "contract_analysis" ? "contract-analysis" : "paas-rag"}-${local.deploy_id}-bucket"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Enabled"

  lifecycle {
    ignore_changes = []
  }
}

resource "oci_identity_customer_secret_key" "aws_compat_access_key" {
  count        = local._needs_object_storage && var.aws_access_key_id == null ? 1 : 0
  provider     = oci.home_region
  display_name = "${var.starter_pack_category == "contract_analysis" ? "contract-analysis" : "paas-rag"}-${local.deploy_id}"
  user_id      = var.current_user_ocid
}

locals {
  _needs_object_storage     = contains(["paas_rag", "contract_analysis"], var.starter_pack_category)
  bucket_name               = local._needs_object_storage ? oci_objectstorage_bucket.paas_rag_bucket[0].name : "#Not configured"
  aws_compat_access_key_id  = local._needs_object_storage ? (var.aws_access_key_id != null ? var.aws_access_key_id : oci_identity_customer_secret_key.aws_compat_access_key[0].id) : "#Not configured"
  aws_compat_access_key_key = local._needs_object_storage ? (var.aws_secret_access_key != null ? var.aws_secret_access_key : oci_identity_customer_secret_key.aws_compat_access_key[0].key) : "#Not configured"
}
