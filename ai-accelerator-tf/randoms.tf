resource "random_string" "deploy_id" {
  length  = 6
  special = false
}

resource "random_string" "app_name_autogen" {
  length  = 8
  special = false
  upper   = false
}

resource "random_string" "generated_workspace_name" {
  length    = 6
  special   = false
  min_upper = 3
  min_lower = 3
}

resource "random_string" "generated_deployment_name" {
  length    = 6
  special   = false
  min_upper = 3
  min_lower = 3
}

resource "random_string" "corrino_django_secret" {
  count            = local.deploy_application ? 1 : 0
  length           = 32
  special          = true
  min_upper        = 3
  min_lower        = 3
  min_numeric      = 3
  min_special      = 3
  override_special = "{}#^*<>[]%~"
}

resource "random_string" "postgres_db_password" {
  count            = local.deploy_application ? 1 : 0
  length           = 16
  special          = true
  min_upper        = 3
  min_lower        = 3
  min_numeric      = 3
  min_special      = 3
  override_special = "{}#^*<>[]%~"
}

resource "random_string" "postgres_db_username" {
  count     = local.deploy_application ? 1 : 0
  length    = 8
  special   = false
  min_upper = 2
  min_lower = 2
}

resource "random_string" "postgres_db_name" {
  count     = local.deploy_application ? 1 : 0
  length    = 4
  special   = false
  min_upper = 2
  min_lower = 2
}

# VSS Oracle UX dedicated Postgres
resource "random_string" "vss_postgres_db_password" {
  count       = local.deploy_application ? 1 : 0
  length      = 24
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

resource "random_string" "vss_postgres_db_username" {
  count     = local.deploy_application ? 1 : 0
  length    = 8
  special   = false
  min_upper = 2
  min_lower = 2
}

resource "random_string" "vss_postgres_db_name" {
  count     = local.deploy_application ? 1 : 0
  length    = 4
  special   = false
  min_upper = 2
  min_lower = 2
}

# resource "random_string" "autonomous_database_admin_password" {
#   length           = 16
#   special          = true
#   min_upper        = 3
#   min_lower        = 3
#   min_numeric      = 3
#   min_special      = 3
#   override_special = "{}#^*<>[]%~"
# }

resource "random_string" "subdomain" {
  length  = 6
  special = false
  upper   = false
}

resource "random_uuid" "registration_id" {
}

#resource "random_string" "registration_id" {
#  length  = 8
#  special = false
#  upper   = false
#}

resource "random_string" "minio_access_key" {
  length  = 20
  special = false
}

resource "random_password" "minio_secret_key" {
  length  = 40
  special = false
}

resource "random_password" "ingress_api_key" {
  count   = var.add_api_key_to_ingress && var.ingress_api_key == "" ? 1 : 0
  length  = 48
  special = false
}
