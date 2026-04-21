# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#

# Autonomous Database
resource "oci_database_autonomous_database" "oracle_26ai" {
  compartment_id                                 = var.compartment_ocid
  db_name                                        = "AIAccel${var.db_name}${random_string.deploy_id.result}"
  display_name                                   = "AIAccel${var.db_display_name}${random_string.deploy_id.result}"
  admin_password                                 = var.db_password
  compute_count                                  = local.starter_pack_config.database_compute_count
  db_version                                     = "26ai"
  compute_model                                  = "ECPU"
  data_storage_size_in_tbs                       = local.starter_pack_config.database_storage_size_in_tbs
  db_workload                                    = var.db_workload_type
  license_model                                  = var.db_license_model
  is_auto_scaling_enabled                        = true
  is_auto_scaling_for_storage_enabled            = false
  is_dedicated                                   = false
  is_free_tier                                   = false
  is_mtls_connection_required                    = false
  is_preview_version_with_service_terms_accepted = false
  autonomous_maintenance_schedule_type           = "REGULAR"
  backup_retention_period_in_days                = 60
  character_set                                  = "AL32UTF8"
  ncharacter_set                                 = "AL16UTF16"
  subnet_id                                      = local.autonomous_db_subnet_id
  private_endpoint_label                         = "aiaccel${random_string.deploy_id.result}"

  count = local.deploy_app_26ai ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.db_password != null
      error_message = "db_password is required for pack categories that provision the 26ai database (paas_rag, enterprise_rag, enterprise_rag_aiq)."
    }
  }

  depends_on = [
    oci_core_subnet.oke_db_subnet
  ]
}

resource "kubernetes_secret_v1" "oadb-admin" {
  metadata {
    name      = "oadb-admin"
    namespace = "default"
  }
  data = {
    oadb_admin_pw = var.db_password
  }
  type = "Opaque"

  count      = local.deploy_app_26ai ? 1 : 0
  depends_on = [oci_database_autonomous_database.oracle_26ai, oci_containerengine_node_pool.oke_node_pool]
}

resource "kubernetes_secret_v1" "oadb-connection" {
  metadata {
    name      = "oadb-connection"
    namespace = "default"
  }
  data = {
    oadb_service = "${var.db_name}_TP"
  }
  type = "Opaque"

  count      = local.deploy_app_26ai ? 1 : 0
  depends_on = [oci_database_autonomous_database.oracle_26ai, oci_containerengine_node_pool.oke_node_pool]
}

locals {
  oracle26ai_high_connection_string = local.needs_26ai && length(oci_database_autonomous_database.oracle_26ai) > 0 ? "tcps://${oci_database_autonomous_database.oracle_26ai[0].private_endpoint}:1521/${regex("[^/]+$", oci_database_autonomous_database.oracle_26ai[0].connection_strings[0].high)}" : ""
}

# Secret containing the oracle26ai_high connection string
resource "kubernetes_secret_v1" "oadb_high_connection" {
  metadata {
    name      = "oadb-high-connection"
    namespace = "default"
  }
  data = {
    connection_string = local.oracle26ai_high_connection_string
  }
  type = "Opaque"

  count      = local.deploy_app_26ai ? 1 : 0
  depends_on = [oci_database_autonomous_database.oracle_26ai, oci_containerengine_node_pool.oke_node_pool]
}