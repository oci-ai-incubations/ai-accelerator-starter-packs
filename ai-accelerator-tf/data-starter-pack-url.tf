# HTTP-based data sources to dynamically fetch the starter pack URL from workspace API
# Used for starter packs that need dynamic URL lookup (all blueprint-based packs)

# =============================================================================
# Configuration locals
# =============================================================================
locals {
  # Whether this starter pack uses dynamic URL lookup (from config)
  needs_dynamic_url = local.starter_pack_config.use_dynamic_url

  # Parse blueprint to extract deployment_group.name
  blueprint_json = local.needs_dynamic_url ? (
    try(jsondecode(local.starter_pack_blueprint_content), null)
  ) : null

  deployment_group_name = local.blueprint_json != null ? (
    try(local.blueprint_json.deployment_group.name, "")
  ) : ""
}

# =============================================================================
# Step 1: Wait for the deployment to become available (polls the API)
# =============================================================================
resource "null_resource" "wait_for_deployment" {
  count = local.needs_dynamic_url ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Waiting for ${var.starter_pack_category} deployment to become available..."
      API_URL="${local.public_endpoint.api_origin_secure}"
      USERNAME="${var.corrino_admin_username}"
      PASSWORD="${var.corrino_admin_password}"
      DEPLOYMENT_PREFIX="${local.deployment_group_name}"
      MAX_ATTEMPTS=40  # 40 attempts * 30 seconds = 20 minutes max wait
      ATTEMPT=0

      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT + 1))
        echo "Attempt $ATTEMPT of $MAX_ATTEMPTS..."

        # Get auth token
        TOKEN=$(curl -sk -X POST "$API_URL/login/" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "username=$USERNAME&password=$PASSWORD" 2>/dev/null | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

        if [ -z "$TOKEN" ]; then
          echo "Failed to get auth token, retrying in 30 seconds..."
          sleep 30
          continue
        fi

        # Check workspace for deployment group recipe with Ingress type
        WORKSPACE=$(curl -sk -X GET "$API_URL/workspace/" \
          -H "Authorization: Token $TOKEN" \
          -H "Content-Type: application/json" 2>/dev/null)

        if echo "$WORKSPACE" | grep -q "\"$DEPLOYMENT_PREFIX.*\"type\":\"Ingress\""; then
          echo "${var.starter_pack_category} deployment found! Deployment is ready."
          exit 0
        fi

        echo "${var.starter_pack_category} deployment not ready yet, waiting 30 seconds..."
        sleep 30
      done

      echo "Timeout waiting for ${var.starter_pack_category} deployment after $MAX_ATTEMPTS attempts"
      exit 1
    EOT
  }

  depends_on = [kubernetes_job_v1.blueprint_deployment_job]
}

# =============================================================================
# Step 2: Authenticate with the Corrino API to get a token
# =============================================================================
data "http" "starter_pack_auth" {
  count  = local.needs_dynamic_url ? 1 : 0
  url    = "${local.public_endpoint.api_origin_secure}/login/"
  method = "POST"

  request_headers = {
    Content-Type = "application/x-www-form-urlencoded"
  }

  request_body = "username=${urlencode(var.corrino_admin_username)}&password=${urlencode(var.corrino_admin_password)}"

  insecure = true # Allow self-signed certificates

  depends_on = [null_resource.wait_for_deployment]
}

# =============================================================================
# Step 3: Fetch workspace info using the authentication token
# =============================================================================
data "http" "starter_pack_workspace" {
  count  = local.needs_dynamic_url ? 1 : 0
  url    = "${local.public_endpoint.api_origin_secure}/workspace/"
  method = "GET"

  request_headers = {
    Authorization = "Token ${jsondecode(data.http.starter_pack_auth[0].response_body).token}"
    Content-Type  = "application/json"
  }

  insecure = true # Allow self-signed certificates

  depends_on = [data.http.starter_pack_auth]
}

# =============================================================================
# Extract the deployment URL from the workspace response
# =============================================================================
locals {
  # Parse workspace response - it's a single object with recipes directly at root level
  workspace_data = local.needs_dynamic_url ? (
    try(jsondecode(data.http.starter_pack_workspace[0].response_body), null)
  ) : null

  # Get recipes from the workspace data (directly at root, not nested under digest)
  recipes = local.workspace_data != null ? try(local.workspace_data.recipes, {}) : {}

  # Find matching recipes using the deployment group name from blueprint
  matching_recipes = local.needs_dynamic_url ? [
    for name, info in local.recipes :
    info.public_endpoint
    if startswith(name, local.deployment_group_name) && try(info.type, "") == "Ingress" && try(info.public_endpoint, "") != ""
  ] : []

  # Single dynamic URL that works for all categories
  dynamic_url = length(local.matching_recipes) > 0 ? local.matching_recipes[0] : ""
}

# =============================================================================
# Static URL patterns for secondary outputs
# =============================================================================
locals {
  cuopt_url           = var.cuopt_marketing_enabled ? "cuopt-cuopt.${local.fqdn.name}" : local.public_endpoint.starter_pack
  cuopt_marketing_url = var.cuopt_marketing_enabled ? "demo-cuopt.${local.fqdn.name}" : "#Marketing Disabled"
}
