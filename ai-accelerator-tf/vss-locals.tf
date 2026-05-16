# VSS pack-specific Corrino recipes — vss-oracle-ux (FE), vss-download-service
# (Python downloader), vss-postgres (Prisma DB).
#
# These three deployments used to live in dedicated native-TF files
# (app-vss-oracle-ux.tf, app-vss-download-service.tf, vss_postgres_db.tf).
# Moving them under Corrino lets the vss-oracle-ux skin's ingress splice in
# `/auth/*` via local.auth_service_ingress_route (same mechanism used by the
# cuopt skin) — Corrino's `$${name.service_name}` placeholder resolver is the
# part that native-TF ingress couldn't match.
#
# app-vss-fss.tf retains the OCI FSS resources (file system, mount target,
# export) because those are cloud-side, not k8s. The kubernetes PV/PVC that
# previously bridged them are gone — recipes here mount FSS directly via
# `input_file_system`.

locals {
  # -------------------------------------------------------------------------
  # Postgres (for the Next.js Prisma client)
  # -------------------------------------------------------------------------
  # Connection info. db_name / user / password come from random_strings in
  # randoms.tf. Host is resolved at deploy time by Corrino — the recipe
  # exports service_name, and the FE recipe references it as
  # `$${vss-postgres.service_name}` in the DATABASE_URL it stamps into env.
  vss_postgres_creds = local.deploy_app_vss ? {
    db_name  = format("%s_db", random_string.vss_postgres_db_name[0].result)
    user     = format("%s_user", random_string.vss_postgres_db_username[0].result)
    password = random_string.vss_postgres_db_password[0].result
    } : {
    db_name  = ""
    user     = ""
    password = ""
  }

  # start.sh wrapper: handles the pgdata directory init the old k8s
  # init-container did (mkdir + chown 999:999). Runs as root (postgres:14
  # image has no USER), then exec's the official entrypoint which steps down
  # to the postgres user via gosu. recipe_container_command_args replaces
  # the image's CMD+ENTRYPOINT, so we have to exec docker-entrypoint.sh
  # explicitly to restore normal startup.
  _vss_postgres_start_sh = "#!/bin/bash\nset -e\nmkdir -p /var/lib/postgresql/data/pgdata\nchown -R 999:999 /var/lib/postgresql/data\nexec /usr/local/bin/docker-entrypoint.sh postgres\n"

  vss_postgres_recipe = local.deploy_app_vss ? [{
    name       = "vss-postgres"
    exports    = ["service_name"]
    depends_on = []
    recipe = {
      recipe_id       = "vss-postgres"
      deployment_name = "vss-postgres"
      recipe_mode     = "service"
      # Cluster-internal only: the vss-oracle-ux FE connects via the
      # corrino-managed Service (resolved as $${vss-postgres.service_name}).
      # No external client should reach the DB directly.
      recipe_disable_ingress               = true
      recipe_image_uri                     = "docker.io/library/postgres:14"
      recipe_replica_count                 = 1
      recipe_flex_shape_ocpu_count         = 1
      recipe_flex_shape_memory_size_in_gbs = 4
      recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
      recipe_use_shared_node_pool          = true
      recipe_container_port                = "5432"
      # Without recipe_host_port Corrino defaults the Service port to 80 and
      # routes 80 → recipe_container_port. The vss-oracle-ux DATABASE_URL
      # connects literally on :5432, so we set recipe_host_port to match —
      # Service exposes 5432 → 5432 directly.
      recipe_host_port              = "5432"
      recipe_container_command_args = ["/opt/scripts/start.sh"]
      pvcs = {
        volumes = [
          { name = "vss-postgresdata", mount_location = "/var/lib/postgresql/data", volume_size_in_gbs = 20 }
        ]
        retain_after_undeploy = false
      }
      recipe_container_env = [
        { key = "POSTGRES_DB", value = local.vss_postgres_creds.db_name },
        { key = "POSTGRES_USER", value = local.vss_postgres_creds.user },
        { key = "POSTGRES_PASSWORD", value = local.vss_postgres_creds.password },
        { key = "PGDATA", value = "/var/lib/postgresql/data/pgdata" },
      ]
      recipe_configmaps = [
        {
          name           = "scripts"
          default_mode   = 493 # 0755
          mount_location = "/opt/scripts"
          data = {
            "start.sh" = local._vss_postgres_start_sh
          }
        }
      ]
    }
  }] : []

  # -------------------------------------------------------------------------
  # Download service (async OCI Object Storage → FSS downloader)
  # -------------------------------------------------------------------------
  # The download-service image runs as USER downloader (uid 1001) per its
  # Dockerfile, so this container can't chmod a root-owned cache dir. Cache-
  # dir init is delegated to the vss recipe's start.sh (which runs as root,
  # mounts the same FSS, and pre-creates /mnt/fss/cache). depends_on = ["vss"]
  # enforces the ordering — the download-service only starts after VSS has
  # successfully run its init.
  vss_download_service_image_uri = "${local.ocir.base_uri}:vss-download-service-4f7d584"

  vss_download_service_recipe = local.deploy_app_vss ? [{
    name       = "vss-download-service"
    exports    = ["service_name"]
    depends_on = ["vss"]
    recipe = {
      recipe_id       = "vss-download-service"
      deployment_name = "vss-download-service"
      recipe_mode     = "service"
      # Cluster-internal only: the FE talks to it as
      # $${vss-download-service.service_name}:8080 via cluster DNS, and the
      # downloader calls back to the FE via cluster DNS. No external client
      # has business hitting this Python downloader directly.
      recipe_disable_ingress               = true
      recipe_image_uri                     = local.vss_download_service_image_uri
      recipe_replica_count                 = 1
      recipe_flex_shape_ocpu_count         = 1
      recipe_flex_shape_memory_size_in_gbs = 2
      recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
      recipe_use_shared_node_pool          = true
      recipe_container_port                = "8080"
      # Without recipe_host_port Corrino defaults the Service to expose 80
      # and routes 80 -> recipe_container_port. The vss-oracle-ux skin's
      # DOWNLOAD_SERVICE_URL connects literally on :8080, so we set
      # recipe_host_port to match -- Service exposes 8080 -> 8080 directly.
      # (Same fix as vss-postgres recipe_host_port = 5432.)
      recipe_host_port = "8080"
      input_file_system = [
        {
          file_system_ocid   = oci_file_storage_file_system.vss_fss[0].id
          mount_target_ocid  = oci_file_storage_mount_target.vss_mount_target[0].id
          mount_location     = "/mnt/fss"
          volume_size_in_gbs = 1000
        }
      ]
      recipe_container_env = [
        { key = "FILE_STORAGE_PATH", value = "/mnt/fss/cache" },
        { key = "MAX_CONCURRENT_DOWNLOADS", value = "3" },
        { key = "REGION_NAME", value = var.region },
        # Used by the downloader to poke the FE's /api/jobs/process-next when
        # a download completes. The default-skin service is the only valid
        # target (other skins share the same Postgres + queue, but only one
        # process-next driver is needed).
        { key = "VSS_ORACLE_UX_URL", value = "http://$${skin_vss_core.service_name}" },
      ]
      recipe_liveness_probe_params = {
        port                  = 8080
        scheme                = "HTTP"
        endpoint_path         = "/health"
        period_seconds        = 30
        timeout_seconds       = 5
        failure_threshold     = 3
        success_threshold     = 1
        initial_delay_seconds = 10
      }
      recipe_readiness_probe_params = {
        port                  = 8080
        scheme                = "HTTP"
        endpoint_path         = "/health"
        period_seconds        = 10
        timeout_seconds       = 3
        success_threshold     = 1
        initial_delay_seconds = 5
      }
    }
  }] : []

  # -------------------------------------------------------------------------
  # VSS Oracle UX (Next.js frontend, multi-skin)
  # -------------------------------------------------------------------------
  # Mirrors the _cuopt_frontend_deployments pattern. One recipe per enabled
  # vss frontend skin. Each gets its own subdomain via
  # `service_endpoint_subdomain` and a Corrino-managed ingress with /auth/*
  # spliced in (when auth-service is on) via auth_service_ingress_route.
  #
  # The native-TF version pulled REGION_NAME / COMPARTMENT_ID / TENANCY_ID /
  # TENANCY_NAMESPACE from corrino-configmap via config_map_key_ref. That
  # configmap is k8s-only and would require recipe_container_env_from
  # support which Corrino doesn't expose; passing the values literally
  # from TF is functionally equivalent for cluster-lifetime stability.
  _vss_oracle_ux_recipes = local.deploy_app_vss ? [
    for skin in local.enabled_frontend_skins : {
      name    = skin.variable_name
      exports = ["service_name"]
      depends_on = concat(
        ["vss", "vss-postgres", "vss-download-service"],
        var.enable_auth_service ? ["auth-service"] : [],
      )
      recipe = merge(
        {
          recipe_id                            = replace(skin.variable_name, "_", "-")
          deployment_name                      = replace(skin.variable_name, "_", "-")
          recipe_mode                          = "service"
          recipe_image_uri                     = skin.image_uri
          recipe_replica_count                 = 1
          recipe_flex_shape_ocpu_count         = 1
          recipe_flex_shape_memory_size_in_gbs = 4
          recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
          recipe_use_shared_node_pool          = true
          recipe_container_port                = skin.container_port
          service_endpoint_subdomain           = skin.subdomain
          input_file_system = [
            {
              file_system_ocid   = oci_file_storage_file_system.vss_fss[0].id
              mount_target_ocid  = oci_file_storage_mount_target.vss_mount_target[0].id
              mount_location     = "/mnt/fss"
              volume_size_in_gbs = 1000
            }
          ]
          # Long-running video summarization streams responses for many
          # minutes; nginx-ingress defaults of 60s would disconnect clients.
          # Same values the pre-Corrino kubernetes_ingress_v1 used.
          recipe_additional_ingress_annotations = [
            { key = "nginx.ingress.kubernetes.io/proxy-read-timeout", value = "1800" },
            { key = "nginx.ingress.kubernetes.io/proxy-send-timeout", value = "1800" },
          ]
          recipe_container_env = [
            { key = "LOCAL", value = "false" },
            { key = "REGION_NAME", value = var.region },
            { key = "COMPARTMENT_ID", value = var.compartment_ocid },
            { key = "TENANCY_ID", value = var.tenancy_ocid },
            { key = "VSS_API_BASE_URL", value = "http://$${vss.service_name}:8000/" },
            { key = "FILE_STORAGE_PATH", value = "/mnt/fss/cache" },
            { key = "DOWNLOAD_SERVICE_URL", value = "http://$${vss-download-service.service_name}:8080" },
            # DATABASE_URL — password lands in the pod env. Same posture as
            # the pre-Corrino k8s ConfigMap (vss-postgres-config) it
            # replaces; pod env is no worse than a configmap-mounted file.
            # Corrino substitutes $${vss-postgres.service_name} at deploy
            # time so the host portion picks up whatever canonical suffix
            # the deployment group ends up with.
            { key = "DATABASE_URL", value = "postgresql://${local.vss_postgres_creds.user}:${local.vss_postgres_creds.password}@$${vss-postgres.service_name}:5432/${local.vss_postgres_creds.db_name}?schema=public" },
          ]
          recipe_additional_ingress_ports = local.auth_service_ingress_route
          recipe_liveness_probe_params = {
            port                  = tonumber(skin.container_port)
            scheme                = "HTTP"
            endpoint_path         = "/"
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
            success_threshold     = 1
            initial_delay_seconds = 30
          }
          recipe_readiness_probe_params = {
            port                  = tonumber(skin.container_port)
            scheme                = "HTTP"
            endpoint_path         = "/"
            period_seconds        = 5
            timeout_seconds       = 3
            success_threshold     = 1
            initial_delay_seconds = 10
          }
        },
        var.use_custom_dns ? { service_endpoint_domain = local.public_endpoint.starter_pack } : {}
      )
    }
    if try(skin.variable_name, "") != ""
  ] : []

  vss_oracle_ux_recipes = local._vss_oracle_ux_recipes
}
