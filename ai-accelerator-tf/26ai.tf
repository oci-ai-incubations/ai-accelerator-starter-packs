# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#

# Autonomous Database
resource "oci_database_autonomous_database" "oracle_26ai" {
  compartment_id                              = var.compartment_ocid
  db_name                                     = var.db_name
  display_name                                = var.db_display_name
  admin_password                              = var.db_password
  compute_count                               = var.db_compute_count
  compute_model                               = "ECPU"
  data_storage_size_in_tbs                    = var.db_data_storage_size_in_tbs
  db_workload                                 = var.db_workload_type
  license_model                               = var.db_license_model
  is_auto_scaling_enabled                     = true
  is_auto_scaling_for_storage_enabled         = false
  is_dedicated                                = false
  is_free_tier                                = false
  is_mtls_connection_required                 = true
  is_preview_version_with_service_terms_accepted = false
  autonomous_maintenance_schedule_type        = "REGULAR"
  backup_retention_period_in_days             = 60
  character_set                               = "AL32UTF8"
  ncharacter_set                              = "AL16UTF16"
  whitelisted_ips                             = []
  subnet_id                                   = local.db_subnet_id

  count = local.create_network_resources ? 1 : 0

  depends_on = [
    oci_core_subnet.oke_db_subnet
  ]
}