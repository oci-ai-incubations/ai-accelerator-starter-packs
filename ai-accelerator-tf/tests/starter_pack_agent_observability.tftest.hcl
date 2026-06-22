# Agent Observability (Langfuse) starter pack test
# Dynamic URL path (blueprint_file != ""). Blueprint-based pack with managed
# OCI backing services (Postgres, Redis, Object Storage) and in-cluster ClickHouse.

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
  starter_pack_category           = "agent_observability"
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
}

# Test: agent_observability plans successfully (existing GenAI mode, no SSO)
run "plan_agent_observability_small" {
  command = plan

  # Config deployment name should be the base name
  assert {
    condition     = local.starter_pack_config.deployment_name == "agent-observability"
    error_message = "agent_observability config deployment name should be 'agent-observability'"
  }

  # Gating local should be true for this category
  assert {
    condition     = local.deploy_app_agent_obs == true
    error_message = "deploy_app_agent_obs should be true for agent_observability"
  }

  # Default GenAI mode references an existing endpoint (no DAC creation)
  assert {
    condition     = local.agent_obs_create_genai == false
    error_message = "default agent_obs_genai_mode should be 'existing' (no DAC creation)"
  }

  # Inference URL is built from the existing endpoint OCID
  assert {
    condition     = can(regex("inference.generativeai", local.agent_obs_inference_url))
    error_message = "agent_obs_inference_url should be an OCI GenAI inference URL"
  }

  # Postflight registration trigger should record the selected starter pack category
  assert {
    condition     = null_resource.postflight_registration[0].triggers.starter_pack_category == "agent_observability"
    error_message = "postflight trigger should capture starter pack category"
  }

  # Postflight registration trigger should record the deployment region
  assert {
    condition     = null_resource.postflight_registration[0].triggers.region == "us-ashburn-1"
    error_message = "postflight trigger should capture region"
  }

  # SSO disabled by default -> blueprint web env must not contain AUTH_CUSTOM_ISSUER
  assert {
    condition     = local._langfuse_oidc_enabled == false
    error_message = "OIDC should be disabled when agent_obs_oidc_issuer is empty"
  }

  # Langfuse secret must carry the connection material the blueprint references
  assert {
    condition = alltrue([
      for k in ["DATABASE_URL", "REDIS_CONNECTION_STRING", "CLICKHOUSE_URL", "ENCRYPTION_KEY", "NEXTAUTH_SECRET", "SALT"] :
      contains(keys(kubernetes_secret_v1.langfuse_secrets[0].data), k)
    ])
    error_message = "langfuse-secrets must contain DB/Redis/ClickHouse/app-secret keys"
  }
}

# Test: create mode requires billing acknowledgement
run "plan_agent_observability_create_requires_ack" {
  command = plan

  variables {
    agent_obs_genai_mode              = "create"
    agent_obs_billing_acknowledgement = false
  }

  expect_failures = [
    oci_generative_ai_dedicated_ai_cluster.agent_obs_dac,
  ]
}
