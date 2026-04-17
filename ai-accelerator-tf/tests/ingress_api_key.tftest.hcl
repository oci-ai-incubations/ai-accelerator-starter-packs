# Tests for the optional nginx ingress API key auth feature.
# Validates var plumbing, key generation, and blueprint annotation threading
# for both the default-off and opt-in states.

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
  db_password                     = "TestDBP@ssw0rd123!"
}

# Default: flag off => no API key output, no auth annotations in blueprints.
run "plan_default_no_auth" {
  command = plan

  assert {
    condition     = output.ingress_api_key == ""
    error_message = "ingress_api_key output should be empty when add_api_key_to_ingress is false"
  }

  assert {
    condition     = output.ingress_api_key_curl_example == "Ingress API key auth is disabled."
    error_message = "curl example should indicate disabled state"
  }

  assert {
    condition     = length(local.backend_ingress_annotations) == 0
    error_message = "backend_ingress_annotations should be empty when flag is off"
  }
}

# Flag on with BYO key: key flows through to output unchanged.
run "plan_enabled_byo_key" {
  command = plan

  variables {
    add_api_key_to_ingress = true
    ingress_api_key        = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKL"
  }

  assert {
    condition     = output.ingress_api_key == "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKL"
    error_message = "BYO ingress_api_key should pass through to output"
  }

  assert {
    condition     = local.backend_ingress_annotations["nginx.ingress.kubernetes.io/auth-url"] == local.ingress_api_key_validator_url
    error_message = "auth-url annotation should point at the validator service"
  }

  assert {
    condition     = length(local.backend_ingress_annotations_corrino) == 2
    error_message = "corrino annotations list should contain auth-url and auth-method"
  }
}

# Validation: a BYO key shorter than 32 chars is rejected.
run "rejects_short_ingress_api_key" {
  command = plan

  variables {
    add_api_key_to_ingress = true
    ingress_api_key        = "tooshort"
  }

  expect_failures = [var.ingress_api_key]
}
