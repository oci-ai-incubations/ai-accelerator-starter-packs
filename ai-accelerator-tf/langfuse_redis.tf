# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# OCI Cache (managed Redis) — queue/cache backend for Langfuse worker
# (agent_observability pack). TLS is mandatory on OCI Cache, so Langfuse
# connects over rediss://. Endpoint is injected via the langfuse-secrets secret.

resource "oci_redis_redis_cluster" "langfuse_redis" {
  count              = local.deploy_app_agent_obs ? 1 : 0
  compartment_id     = var.compartment_ocid
  display_name       = "langfuse-redis-${local.deploy_id}"
  node_count         = local.agent_obs_size.redis_node_count
  node_memory_in_gbs = local.agent_obs_size.redis_memory_gbs
  software_version   = "REDIS_7_0"
  subnet_id          = local.autonomous_db_subnet_id

  timeouts {
    create = "60m"
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

locals {
  langfuse_redis_fqdn = local.deploy_app_agent_obs ? oci_redis_redis_cluster.langfuse_redis[0].primary_fqdn : ""
  # OCI Cache requires TLS; Langfuse honours the rediss:// scheme.
  langfuse_redis_connection_string = local.deploy_app_agent_obs ? format("rediss://%s:6379", local.langfuse_redis_fqdn) : ""
}
