# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# OCI Generative AI Dedicated AI Cluster (DAC) for Riyadh Air starter pack
# Provisions an H100 hosting cluster, imports the Qwen3-VL-235B model, and creates a serving endpoint.

locals {
  needs_dac = var.starter_pack_category == "riyadh_air"
}

# Dedicated AI Cluster — H100 hosting cluster for Qwen3-VL-235B
resource "oci_generative_ai_dedicated_ai_cluster" "riyadh_air_dac" {
  provider       = oci.genai_region
  count          = local.needs_dac ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "riyadh-air-dac-${local.deploy_id}"
  type           = "HOSTING"
  unit_count     = 1
  unit_shape     = "H100_X8"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

# Import the Qwen3-VL-235B-A22B-Instruct model from HuggingFace
resource "oci_generative_ai_imported_model" "qwen3_vl" {
  provider       = oci.genai_region
  count          = local.needs_dac ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "Qwen3-VL-235B-A22B-Instruct"
  vendor         = "qwen"
  version        = "3.0"

  data_source {
    source_type = "HUGGING_FACE_MODEL"
    model_id    = "Qwen/Qwen3-VL-235B-A22B-Instruct"
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }

  depends_on = [oci_generative_ai_dedicated_ai_cluster.riyadh_air_dac]
}

# Create a serving endpoint on the DAC for the Qwen model
resource "oci_generative_ai_endpoint" "qwen3_vl_endpoint" {
  provider                = oci.genai_region
  count                   = local.needs_dac ? 1 : 0
  compartment_id          = var.compartment_ocid
  dedicated_ai_cluster_id = oci_generative_ai_dedicated_ai_cluster.riyadh_air_dac[0].id
  model_id                = oci_generative_ai_imported_model.qwen3_vl[0].id
  display_name            = "qwen3-vl-endpoint-${local.deploy_id}"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
