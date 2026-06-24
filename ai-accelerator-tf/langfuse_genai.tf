# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Agentic model for the agent_observability pack, served by OCI Generative AI.
# Two modes (var.agent_obs_genai_mode):
#   - "existing": reference an existing GenAI endpoint OCID (default).
#   - "create":  import dac_model_id from HuggingFace, provision a Dedicated AI
#                Cluster, and create an endpoint (billed hourly).
# The agent runtime in the blueprint calls the OpenAI-compatible inference URL
# and is instrumented with Langfuse so traces are captured.

locals {
  agent_obs_create_genai = local.deploy_app_agent_obs && var.agent_obs_genai_mode == "create"
  # Last path segment of the HF model id, sanitized for OCI: the imported-model
  # display_name allows only alphanumerics and hyphens (e.g. "Qwen3.6-35B-A3B"
  # has a '.' which OCI rejects with 400-InvalidParameter "cannot have special
  # characters"). Replace any non [a-zA-Z0-9-] with '-'.
  _agent_obs_model_name_raw = element(
    split("/", var.agent_obs_model_id),
    length(split("/", var.agent_obs_model_id)) - 1,
  )
  agent_obs_model_display_name = replace(local._agent_obs_model_name_raw, "/[^a-zA-Z0-9-]/", "-")

  # Minimal llama-stack config (oci-min): the OCI inference provider lists every
  # model/endpoint in the compartment — including the dedicated DAC endpoint — so
  # the imported model shows up in /v1/models. Kept minimal (inference only) to
  # avoid the vector_io/file_search schema surface. $${...} escapes Terraform
  # interpolation so the literal ${env....} reaches llama-stack.
  agent_obs_llamastack_config = <<-YAML
    version: 2
    distro_name: oci-min
    apis:
    - inference
    providers:
      inference:
      - provider_id: oci
        provider_type: remote::oci
        config:
          oci_auth_type: $${env.OCI_AUTH_TYPE:=instance_principal}
          oci_region: $${env.OCI_REGION:=us-ashburn-1}
          oci_compartment_id: $${env.OCI_COMPARTMENT_OCID:=}
    storage:
      backends:
        kv_default:
          type: kv_sqlite
          db_path: $${env.SQLITE_STORE_DIR:=/tmp/llama}/kvstore.db
        sql_default:
          type: sql_sqlite
          db_path: $${env.SQLITE_STORE_DIR:=/tmp/llama}/sql_store.db
      stores:
        metadata:
          namespace: registry
          backend: kv_default
        inference:
          table_name: inference_store
          backend: sql_default
    registered_resources:
      models: []
    server:
      port: 8321
  YAML
}

# create mode: import model from HuggingFace
resource "oci_generative_ai_imported_model" "agent_obs_model" {
  provider       = oci.genai_region
  count          = local.agent_obs_create_genai ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "${local.agent_obs_model_display_name}-${local.deploy_id}"

  data_source {
    source_type  = "HUGGING_FACE_MODEL"
    model_id     = var.agent_obs_model_id
    access_token = var.agent_obs_hf_token != "" ? var.agent_obs_hf_token : null
  }

  timeouts {
    create = "120m"
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

# create mode: hosting Dedicated AI Cluster
resource "oci_generative_ai_dedicated_ai_cluster" "agent_obs_dac" {
  provider       = oci.genai_region
  count          = local.agent_obs_create_genai ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "agent-obs-dac-${local.deploy_id}"
  type           = "HOSTING"
  unit_count     = 1
  unit_shape     = var.agent_obs_unit_shape

  timeouts {
    create = "60m"
  }

  lifecycle {
    ignore_changes = [defined_tags]
    precondition {
      condition     = var.agent_obs_billing_acknowledgement == true
      error_message = "You must acknowledge that the Dedicated AI Cluster will be billed hourly. Check the acknowledgement box to proceed."
    }
  }
}

# create mode: endpoint binding the model to the DAC
resource "oci_generative_ai_endpoint" "agent_obs_endpoint" {
  provider                = oci.genai_region
  count                   = local.agent_obs_create_genai ? 1 : 0
  compartment_id          = var.compartment_ocid
  dedicated_ai_cluster_id = oci_generative_ai_dedicated_ai_cluster.agent_obs_dac[0].id
  model_id                = oci_generative_ai_imported_model.agent_obs_model[0].id
  display_name            = "${local.agent_obs_model_display_name}-endpoint-${local.deploy_id}"

  timeouts {
    create = "60m"
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

locals {
  # Selected endpoint OCID: created endpoint or the provided existing one.
  agent_obs_endpoint_ocid = local.agent_obs_create_genai ? (
    length(oci_generative_ai_endpoint.agent_obs_endpoint) > 0 ? oci_generative_ai_endpoint.agent_obs_endpoint[0].id : ""
  ) : var.agent_obs_existing_endpoint_ocid

  # OpenAI-compatible inference URL for the agent runtime.
  agent_obs_inference_url = local.deploy_app_agent_obs && local.agent_obs_endpoint_ocid != "" ? format(
    "https://inference.generativeai.%s.oci.oraclecloud.com/%s/v1/chat/completions",
    var.genai_region,
    local.agent_obs_endpoint_ocid,
  ) : ""
}
