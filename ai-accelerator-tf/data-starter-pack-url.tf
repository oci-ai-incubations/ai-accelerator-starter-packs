# External data source to dynamically fetch the starter pack URL from workspace API
# This is only used for vss_medium starter pack to get the correct public endpoint

data "external" "vss_starter_pack_url" {
  count   = var.starter_pack_choice == "vss_medium" ? 1 : 0
  program = ["python3", "${path.module}/../corrino_deployment_scripts/get_workspace_info.py", "--terraform"]

  query = {
    api_url       = local.public_endpoint.api_origin_secure
    username      = var.corrino_admin_username
    password      = var.corrino_admin_password
    recipe_prefix = "vss-deployment-group"
  }

  depends_on = [kubernetes_job_v1.blueprint_deployment_job]
}

