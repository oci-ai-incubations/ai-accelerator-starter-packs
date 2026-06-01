# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# OCI Generative AI resources for Document Extractor starter pack
# 1. Import model from HuggingFace
# 2. Create Dedicated AI Cluster
# 3. Create endpoint binding the model to the DAC

locals {
  needs_dac = var.starter_pack_category == "dox_pack" && local.deploy_application
  # OpenAI-compatible inference URL for the DAC endpoint
  dac_inference_url = local.needs_dac && length(oci_generative_ai_endpoint.qwen3_vl_endpoint) > 0 ? "https://inference.generativeai.${var.genai_region}.oci.oraclecloud.com/${oci_generative_ai_endpoint.qwen3_vl_endpoint[0].id}/v1/chat/completions" : ""
  # Extract a short display name from the model ID (e.g. "Qwen3-VL-235B-A22B-Instruct" from "Qwen/Qwen3-VL-235B-A22B-Instruct")
  dac_model_display_name = element(split("/", var.dac_model_id), length(split("/", var.dac_model_id)) - 1)
}

# Step 1: Import model from HuggingFace
resource "oci_generative_ai_imported_model" "qwen3_vl" {
  provider       = oci.genai_region
  count          = local.needs_dac ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "${local.dac_model_display_name}-${local.deploy_id}"

  data_source {
    source_type = "HUGGING_FACE_MODEL"
    model_id    = var.dac_model_id
  }

  timeouts {
    create = "120m"
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

# Step 2: Create Dedicated AI Cluster for hosting the model
resource "oci_generative_ai_dedicated_ai_cluster" "dox_pack_dac" {
  provider       = oci.genai_region
  count          = local.needs_dac ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "dox-pack-dac-${local.deploy_id}"
  type           = "HOSTING"
  unit_count     = 1
  unit_shape     = var.dac_unit_shape

  timeouts {
    create = "60m"
  }

  lifecycle {
    ignore_changes = [defined_tags]
    precondition {
      condition     = var.dac_billing_acknowledgement == true
      error_message = "You must acknowledge that the Dedicated AI Cluster will be billed hourly. Check the acknowledgement box to proceed."
    }
  }
}

# Step 3: Create endpoint binding the imported model to the DAC
resource "oci_generative_ai_endpoint" "qwen3_vl_endpoint" {
  provider                = oci.genai_region
  count                   = local.needs_dac ? 1 : 0
  compartment_id          = var.compartment_ocid
  dedicated_ai_cluster_id = oci_generative_ai_dedicated_ai_cluster.dox_pack_dac[0].id
  model_id                = oci_generative_ai_imported_model.qwen3_vl[0].id
  display_name            = "${local.dac_model_display_name}-endpoint-${local.deploy_id}"

  timeouts {
    create = "60m"
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
