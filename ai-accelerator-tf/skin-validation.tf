# At-least-one-skin precondition. Fails plan for blueprint packs if no skin is enabled.
# Skipped for Helm packs and for deploy_application=false (infra-only) stacks.

resource "terraform_data" "skin_validation" {
  count = local.deploy_application ? 1 : 0

  input = {
    category = var.starter_pack_category
    enabled  = [for s in local.enabled_frontend_skins : s.variable_name]
  }

  lifecycle {
    precondition {
      condition     = length(local.enabled_frontend_skins) > 0
      error_message = "At least one cuopt frontend skin must be enabled. Set skin_cuopt_core or skin_cuopt_partner to true."
    }
  }
}
