# -----------------------------------
# OCI Generative AI Dedicated Cluster & Endpoint
# Created only for VSS poc-dedicated size
# -----------------------------------

locals {
  create_genai_dedicated = var.starter_pack_category == "vss" && var.starter_pack_size == "poc-dedicated"

  genai_maverick_model_id = local.create_genai_dedicated ? try([
    for m in data.oci_generative_ai_models.genai_models[0].model_collection[0].items :
    m.id if m.display_name == "meta.llama-4-maverick-17b-128e-instruct-fp8"
  ][0], null) : null
}

data "oci_generative_ai_models" "genai_models" {
  count          = local.create_genai_dedicated ? 1 : 0
  compartment_id = var.compartment_ocid
  provider       = oci.genai_region
}

resource "oci_generative_ai_dedicated_ai_cluster" "vss_genai_cluster" {
  count          = local.create_genai_dedicated ? 1 : 0
  compartment_id = var.compartment_ocid
  type           = "HOSTING"
  unit_count     = 1
  unit_shape     = "LARGE_GENERIC_2"
  provider       = oci.genai_region

  timeouts {
    create = "60m"
    delete = "60m"
  }
}

resource "oci_generative_ai_endpoint" "vss_genai_endpoint" {
  count                   = local.create_genai_dedicated ? 1 : 0
  compartment_id          = var.compartment_ocid
  dedicated_ai_cluster_id = oci_generative_ai_dedicated_ai_cluster.vss_genai_cluster[0].id
  model_id                = local.genai_maverick_model_id
  provider                = oci.genai_region

  lifecycle {
    precondition {
      condition     = local.genai_maverick_model_id != null
      error_message = "Model 'meta.llama-4-maverick-17b-128e-instruct-fp8' not found in region '${var.genai_region}'. The model is available in: us-chicago-1, uk-london-1, me-riyadh-1, ap-hyderabad-1, ap-osaka-1, sa-saopaulo-1."
    }
  }
}
