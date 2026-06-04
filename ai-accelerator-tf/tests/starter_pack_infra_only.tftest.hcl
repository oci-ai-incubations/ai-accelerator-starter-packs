# Infrastructure-only mode tests -- validates that deploy_application=false
# creates cluster infrastructure but skips all application-layer outputs.

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
  starter_pack_category           = "cuopt"
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
  deploy_application              = false
  db_password                     = "TestDbP@ssw0rd123!"
}

# Test: infrastructure-only mode still plans the OKE cluster resource
run "infra_only_creates_cluster" {
  command = plan

  assert {
    condition     = length(oci_containerengine_cluster.oke_cluster) == 1
    error_message = "Infrastructure-only mode should still create an OKE cluster"
  }
}

# Test: infrastructure-only mode does not output application-layer URLs
run "infra_only_skips_app_outputs" {
  command = plan

  assert {
    condition     = output.starter_pack_url == null
    error_message = "Infrastructure-only mode should not output starter_pack_url"
  }

  assert {
    condition     = output.corrino_api_url == null
    error_message = "Infrastructure-only mode should not output corrino_api_url"
  }

  assert {
    condition     = output.blueprints_portal_url == null
    error_message = "Infrastructure-only mode should not output blueprints_portal_url"
  }
}
