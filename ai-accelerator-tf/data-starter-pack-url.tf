# HTTP-based data sources to dynamically fetch the starter pack URL from workspace API
# Used for starter packs that need dynamic URL lookup (all blueprint-based packs)

# =============================================================================
# Configuration locals
# =============================================================================
locals {
  # Whether this starter pack uses dynamic URL lookup (from config)
  needs_dynamic_url = local.starter_pack_config.use_dynamic_url
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
      DEPLOYMENT_FOR_URL="${local.starter_pack_url_deployment}"
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

        # Filter by specific sub-deployment name (e.g., "frontend-paas-*")
        # For single deployments (cuopt without frontend), DEPLOYMENT_FOR_URL="cuopt" matches "cuopt-<uuid>"
        # For deployment groups, it matches "<sub_deployment>-<group>-<uuid>" pattern
        DEPLOYMENT_UUID=$(echo "$WORKSPACE" | jq -r ".recipes | to_entries[] | select(.key | startswith(\"$DEPLOYMENT_FOR_URL-\")) | select(.value.type == \"Ingress\") | .value[\"deployment-uuid\"]" 2>/dev/null | head -1)

        if [ -n "$DEPLOYMENT_UUID" ] && [ "$DEPLOYMENT_UUID" != "null" ]; then
          echo "Ingress found for ${var.starter_pack_category}. Checking deployment status for UUID: $DEPLOYMENT_UUID..."

          # Get deployment status via /deployment/<uuid> API
          DEPLOYMENT_STATUS=$(curl -sk -X GET "$API_URL/deployment/$DEPLOYMENT_UUID/" \
            -H "Authorization: Token $TOKEN" \
            -H "Content-Type: application/json" 2>/dev/null | jq -r '.deployment_status' 2>/dev/null)

          if [ "$DEPLOYMENT_STATUS" = "active" ] || [ "$DEPLOYMENT_STATUS" = "monitoring" ]; then
            echo "${var.starter_pack_category} deployment is ready and healthy! Status: $DEPLOYMENT_STATUS"
            exit 0
          else
            echo "Deployment status is '$DEPLOYMENT_STATUS', waiting for 'active' or 'monitoring'..."
          fi
        else
          echo "${var.starter_pack_category} Ingress not ready yet, waiting 30 seconds..."
        fi

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
# Expected response format from /workspace/ API:
# {
#   "env": { "tenancy_id": "...", "compartment_id": "...", ... },
#   "system": { ... },
#   "add_ons": { ... },
#   "recipes": {
#     "frontend-paas-13db8ce5": {
#       "type": "Ingress",
#       "name": "recipe-frontend-paas-13db8ce5-ingress",
#       "public_endpoint": "frontend-paas.example.com",
#       "canonical-name": "frontend-paas-13db8ce5",
#       "deployment-uuid": "f593b84c9a1ed4ec5db2afe598a87a03"
#     },
#     ...
#   }
# }
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

  # Find matching recipe and extract deployment-uuid
  # Filter by starter_pack_url_deployment (e.g., "frontend" for paas_rag, "cuopt" for cuopt without frontend)
  matching_recipe_info = local.needs_dynamic_url ? [
    for name, info in local.recipes :
    {
      name            = name
      public_endpoint = info.public_endpoint
      deployment_uuid = try(info["deployment-uuid"], "")
    }
    if(
      # Match recipe name pattern: starts with "<starter_pack_url_deployment>-"
      startswith(name, "${local.starter_pack_url_deployment}-") &&
      try(info.type, "") == "Ingress" &&
      try(info.public_endpoint, "") != ""
    )
  ] : []

  # Get the first matching recipe's info
  first_matching_recipe = length(local.matching_recipe_info) > 0 ? local.matching_recipe_info[0] : null

  # Extract deployment UUID for status check
  deployment_uuid_to_check = local.first_matching_recipe != null ? local.first_matching_recipe.deployment_uuid : ""

  # Find frontend recipe (for cuopt frontend URL)
  # Filter by frontend_starter_pack_url_deployment (e.g., "demo-cuopt" for cuopt with frontend)
  frontend_recipe_info = local.needs_dynamic_url && local.frontend_starter_pack_url_deployment != "" ? [
    for name, info in local.recipes :
    {
      name            = name
      public_endpoint = info.public_endpoint
      deployment_uuid = try(info["deployment-uuid"], "")
    }
    if(
      # Match recipe name pattern: starts with "<frontend_starter_pack_url_deployment>-"
      startswith(name, "${local.frontend_starter_pack_url_deployment}-") &&
      try(info.type, "") == "Ingress" &&
      try(info.public_endpoint, "") != ""
    )
  ] : []

  # Get the first frontend recipe's info
  first_frontend_recipe = length(local.frontend_recipe_info) > 0 ? local.frontend_recipe_info[0] : null
}

# =============================================================================
# Step 3b: Verify deployment health via deployment API
# =============================================================================
# Expected response format from /deployment/<uuid>/ API:
# {
#   "mode": "service",
#   "recipe_id": "frontend",
#   "deployment_uuid": "f593b84c9a1ed4ec5db2afe598a87a03",
#   "deployment_name": "frontend-paas",
#   "deployment_status": "monitoring",  # Can be: "creating", "scheduled", "active", "monitoring"
#   "deployment_directive": "commission",
#   "creation_date": "2026-01-27 06:52 PM UTC"
# }
data "http" "starter_pack_deployment_status" {
  count  = local.needs_dynamic_url ? 1 : 0
  url    = "${local.public_endpoint.api_origin_secure}/deployment/${local.deployment_uuid_to_check}/"
  method = "GET"

  request_headers = {
    Authorization = "Token ${jsondecode(data.http.starter_pack_auth[0].response_body).token}"
    Content-Type  = "application/json"
  }

  insecure = true # Allow self-signed certificates

  depends_on = [data.http.starter_pack_workspace]
}

# =============================================================================
# Parse deployment status and determine final URL
# =============================================================================
locals {
  # Parse deployment status response
  deployment_status_response = local.needs_dynamic_url && length(data.http.starter_pack_deployment_status) > 0 ? (
    try(jsondecode(data.http.starter_pack_deployment_status[0].response_body), null)
  ) : null

  # Check if deployment is healthy (active or monitoring)
  deployment_is_healthy = local.deployment_status_response != null ? (
    contains(["active", "monitoring"], try(local.deployment_status_response.deployment_status, ""))
  ) : false

  # Only use dynamic URL if deployment is healthy
  dynamic_url = local.first_matching_recipe != null && local.deployment_is_healthy ? local.first_matching_recipe.public_endpoint : ""
}

# =============================================================================
# frontend URL (dynamically fetched for cuopt with frontend)
# =============================================================================
locals {
  # frontend URL - use dynamically fetched value when available, otherwise disabled
  cuopt_frontend_url = local.first_frontend_recipe != null ? local.first_frontend_recipe.public_endpoint : "#Frontend Disabled"
}

# =============================================================================
# Final computed URLs for outputs
# =============================================================================
locals {
  # Final starter pack URL - uses dynamic URL if available, falls back to static
  starter_pack_url_output = local.needs_dynamic_url ? (
    local.dynamic_url != "" ? local.dynamic_url : local.public_endpoint.starter_pack
  ) : local.public_endpoint.starter_pack

  # Final frontend URL - only for cuopt with frontend enabled
  starter_pack_frontend_url_output = var.starter_pack_category == "cuopt" ? (
    var.cuopt_frontend_enabled ? local.cuopt_frontend_url : "#Frontend Disabled"
  ) : "#Frontend Disabled"
}
