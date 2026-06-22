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
  agent_obs_model_display_name = element(
    split("/", var.agent_obs_model_id),
    length(split("/", var.agent_obs_model_id)) - 1,
  )
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
