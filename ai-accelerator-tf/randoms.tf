resource "random_string" "deploy_id" {
  length  = 6
  special = false
}

resource "random_string" "app_name_autogen" {
  length  = 8
  special = false
  upper   = false
}
