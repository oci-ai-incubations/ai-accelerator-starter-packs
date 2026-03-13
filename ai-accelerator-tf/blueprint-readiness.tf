# Blueprint deployment readiness gate for starter packs
# Polls the Corrino API to verify deployment health, then fetches workspace data

# =============================================================================
# Configuration locals
# =============================================================================
locals {
  # Whether this starter pack deploys via a blueprint and needs readiness polling
  uses_blueprint_deployment = local.starter_pack_config.blueprint_file != ""
}

# =============================================================================
# Step 1: Wait for the deployment to become available (polls the API)
# =============================================================================
resource "null_resource" "wait_for_deployment" {
  count = local.uses_blueprint_deployment ? 1 : 0

  triggers = {
    blueprint_deploy_id = random_id.blueprint_deploy_id[0].hex
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Waiting for ${var.starter_pack_category} deployment to become available..."
      API_URL="${local.public_endpoint.api_origin_secure}"
      USERNAME="${var.corrino_admin_username}"
      PASSWORD="${var.corrino_admin_password}"
      DEPLOYMENT_FOR_URL="${local.starter_pack_config.deployment_name}"
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

        # Filter by deployment_name-derived canonical prefix
        # For single deployments, DEPLOYMENT_FOR_URL="cuopt" matches "cuopt-<uuid>"
        # For deployment groups, it matches "<sub_deployment>-<group>-<uuid>" names generated from deployment_name
        DEPLOYMENT_UUID=$(echo "$WORKSPACE" | jq -r --arg dn "$DEPLOYMENT_FOR_URL" '.recipes | to_entries[] | select(.key | test("(^|-)"+$dn+"-")) | select(.value.type == "Ingress") | .value["deployment-uuid"]' 2>/dev/null | head -1)

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
          echo "searching for deployment name: $DEPLOYMENT_FOR_URL in workspace."
          echo "Workspace: $WORKSPACE"
          echo "${var.starter_pack_category} Ingress not found for deployment. Sleeping 30 seconds..."
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
  count  = local.uses_blueprint_deployment ? 1 : 0
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
  count  = local.uses_blueprint_deployment ? 1 : 0
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
# Extract recipe data from the workspace response
# =============================================================================
locals {
  # Parse workspace response - it's a single object with recipes directly at root level
  workspace_data = local.uses_blueprint_deployment ? (
    try(jsondecode(data.http.starter_pack_workspace[0].response_body), null)
  ) : null

  # Get recipes from the workspace data (directly at root, not nested under digest)
  recipes = local.workspace_data != null ? try(local.workspace_data.recipes, {}) : {}

}