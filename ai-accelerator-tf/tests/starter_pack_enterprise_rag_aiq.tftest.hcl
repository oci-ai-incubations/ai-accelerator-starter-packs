# Enterprise RAG + AIQ starter pack test
# Static URL path (blueprint_file == "") -- no HTTP mocks needed.

mock_provider "oci" {
  override_data {
    target = data.oci_identity_regions.home_region
    values = {
      regions = [{
        name = "us-ashburn-1"
        key  = "IAD"
      }]
    }
  }

  override_data {
    target = data.oci_identity_availability_domains.ads
    values = {
      availability_domains = [{
        name = "US-ASHBURN-AD-1"
      }]
    }
  }

  override_data {
    target = data.oci_core_images.oracle_linux
    values = {
      images = [{
        id = "ocid1.image.oc1..test"
      }]
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "tls" {}
mock_provider "local" {}
mock_provider "null" {}
mock_provider "cloudinit" {}
mock_provider "random" {}
mock_provider "http" {}

variables {
  tenancy_ocid                    = "ocid1.tenancy.oc1..test"
  compartment_ocid                = "ocid1.compartment.oc1..test"
  region                          = "us-ashburn-1"
  current_user_ocid               = "ocid1.user.oc1..test"
  corrino_admin_username          = "testadmin"
  corrino_admin_password          = "TestP@ssw0rd123!"
  corrino_admin_email             = "test@example.com"
  starter_pack_category           = "enterprise_rag_aiq"
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
  tavily_api_key                  = ""
  # enterprise_rag_aiq provisions the 26ai database (same as paas_rag + enterprise_rag),
  # so the db_password precondition in 26ai.tf applies here.
  db_password = "TestDBP@ssw0rd123!"
}

# Test: enterprise_rag_aiq starter pack plans successfully with correct deployment name and registration triggers
run "plan_enterprise_rag_aiq_small" {
  command = plan

  assert {
    condition     = output.starter_pack_deployment_name == "enterprise-rag"
    error_message = "enterprise_rag_aiq deployment name should be 'enterprise-rag'"
  }

  assert {
    condition     = null_resource.postflight_registration[0].triggers.starter_pack_category == "enterprise_rag_aiq"
    error_message = "postflight trigger should capture starter pack category"
  }

  assert {
    condition     = null_resource.postflight_registration[0].triggers.region == "us-ashburn-1"
    error_message = "postflight trigger should capture region"
  }
}
