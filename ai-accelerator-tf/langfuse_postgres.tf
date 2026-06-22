# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# OCI Database with PostgreSQL — managed transactional store for Langfuse
# (agent_observability pack). Langfuse requires PostgreSQL, so we use the OCI
# managed service rather than Oracle 26ai/ADB. Connection details are injected
# into the Langfuse blueprint via the langfuse-secrets Kubernetes secret.

locals {
  # Per-size sizing for the managed backing services.
  agent_obs_sizing = {
    small = {
      pg_instance_count = 2
      pg_ocpu_count     = 2
      pg_memory_gbs     = 16
      redis_node_count  = 2
      redis_memory_gbs  = 4
      ch_shards         = 1
      ch_replicas       = 2
    }
    medium = {
      pg_instance_count = 2
      pg_ocpu_count     = 4
      pg_memory_gbs     = 32
      redis_node_count  = 2
      redis_memory_gbs  = 8
      ch_shards         = 2
      ch_replicas       = 2
    }
  }
  agent_obs_size = lookup(local.agent_obs_sizing, var.starter_pack_size, local.agent_obs_sizing["small"])

  langfuse_pg_username = "langfuse"
  langfuse_pg_dbname   = "postgres" # OCI PSQL default database; Langfuse migrations create their own tables
}

resource "oci_psql_db_system" "langfuse_pg" {
  count          = local.deploy_app_agent_obs ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "langfuse-pg-${local.deploy_id}"
  db_version     = "14"
  shape          = "PostgreSQL.VM.Standard.E4.Flex"

  instance_count              = local.agent_obs_size.pg_instance_count
  instance_ocpu_count         = local.agent_obs_size.pg_ocpu_count
  instance_memory_size_in_gbs = local.agent_obs_size.pg_memory_gbs

  network_details {
    subnet_id = local.autonomous_db_subnet_id
  }

  storage_details {
    is_regionally_durable = true
    system_type           = "OCI_OPTIMIZED_STORAGE"
  }

  credentials {
    username = local.langfuse_pg_username
    password_details {
      password_type = "PLAIN_TEXT"
      password      = random_password.langfuse_pg_password[0].result
    }
  }

  timeouts {
    create = "60m"
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

# Connection endpoint (FQDN) for building DATABASE_URL.
data "oci_psql_db_system_connection_detail" "langfuse_pg" {
  count        = local.deploy_app_agent_obs ? 1 : 0
  db_system_id = oci_psql_db_system.langfuse_pg[0].id
}

locals {
  langfuse_pg_fqdn = local.deploy_app_agent_obs ? data.oci_psql_db_system_connection_detail.langfuse_pg[0].primary_db_endpoint[0].fqdn : ""
  langfuse_database_url = local.deploy_app_agent_obs ? format(
    "postgresql://%s:%s@%s:5432/%s?sslmode=require",
    local.langfuse_pg_username,
    random_password.langfuse_pg_password[0].result,
    local.langfuse_pg_fqdn,
    local.langfuse_pg_dbname,
  ) : ""
}
