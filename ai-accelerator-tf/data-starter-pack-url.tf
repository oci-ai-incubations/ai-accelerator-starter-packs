# HTTP-based data sources to dynamically fetch the starter pack URL from workspace API
# This is only used for vss starter pack to get the correct public endpoint

# Step 1: Wait for the VSS deployment to become available (polls the API)
resource "null_resource" "wait_for_vss_deployment" {
  count = var.starter_pack_category == "vss" ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Waiting for VSS deployment to become available..."
      API_URL="${local.public_endpoint.api_origin_secure}"
      USERNAME="${var.corrino_admin_username}"
      PASSWORD="${var.corrino_admin_password}"
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

        # Check workspace for vss-deployment-group recipe
        WORKSPACE=$(curl -sk -X GET "$API_URL/workspace/" \
          -H "Authorization: Token $TOKEN" \
          -H "Content-Type: application/json" 2>/dev/null)

        if echo "$WORKSPACE" | grep -q '"vss-deployment-group.*"type":"Ingress"'; then
          echo "VSS deployment found! Deployment is ready."
          exit 0
        fi

        echo "VSS deployment not ready yet, waiting 30 seconds..."
        sleep 30
      done

      echo "Timeout waiting for VSS deployment after $MAX_ATTEMPTS attempts"
      exit 1
    EOT
  }

  depends_on = [kubernetes_job_v1.blueprint_deployment_job]
}

# Step 2: Authenticate with the Corrino API to get a token
data "http" "vss_auth" {
  count  = var.starter_pack_category == "vss" ? 1 : 0
  url    = "${local.public_endpoint.api_origin_secure}/login/"
  method = "POST"

  request_headers = {
    Content-Type = "application/x-www-form-urlencoded"
  }

  request_body = "username=${urlencode(var.corrino_admin_username)}&password=${urlencode(var.corrino_admin_password)}"

  insecure = true # Allow self-signed certificates

  depends_on = [null_resource.wait_for_vss_deployment]
}

# Step 3: Fetch workspace info using the authentication token
data "http" "vss_workspace" {
  count  = var.starter_pack_category == "vss" ? 1 : 0
  url    = "${local.public_endpoint.api_origin_secure}/workspace/"
  method = "GET"

  request_headers = {
    Authorization = "Token ${jsondecode(data.http.vss_auth[0].response_body).token}"
    Content-Type  = "application/json"
  }

  insecure = true # Allow self-signed certificates

  depends_on = [data.http.vss_auth]
}

# Local to extract the VSS deployment URL from the workspace response
locals {
  # Parse workspace response - it's a single object with recipes directly at root level
  vss_workspace_data = var.starter_pack_category == "vss" ? (
    try(jsondecode(data.http.vss_workspace[0].response_body), null)
  ) : null

  # Get recipes from the workspace data (directly at root, not nested under digest)
  vss_recipes = local.vss_workspace_data != null ? try(local.vss_workspace_data.recipes, {}) : {}

  # Find the first recipe that starts with "vss-deployment-group" and has type "Ingress"
  vss_matching_recipes = [
    for name, info in local.vss_recipes :
    info.public_endpoint
    if startswith(name, "vss-deployment-group") && try(info.type, "") == "Ingress" && try(info.public_endpoint, "") != ""
  ]

  # Get the URL or fall back to the static URL
  vss_dynamic_url = length(local.vss_matching_recipes) > 0 ? local.vss_matching_recipes[0] : ""
}
