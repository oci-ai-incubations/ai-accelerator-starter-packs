# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#

# Autonomous Database
resource "oci_database_autonomous_database" "oracle_26ai" {
  compartment_id                              = var.compartment_ocid
  db_name                                     = var.db_name
  display_name                                = var.db_display_name
  admin_password                              = var.db_password
  compute_count                               = var.db_compute_count
  compute_model                               = "ECPU"
  data_storage_size_in_tbs                    = var.db_data_storage_size_in_tbs
  db_workload                                 = var.db_workload_type
  license_model                               = var.db_license_model
  is_auto_scaling_enabled                     = true
  is_auto_scaling_for_storage_enabled         = false
  is_dedicated                                = false
  is_free_tier                                = false
  is_mtls_connection_required                 = true
  is_preview_version_with_service_terms_accepted = false
  autonomous_maintenance_schedule_type        = "REGULAR"
  backup_retention_period_in_days             = 60
  character_set                               = "AL32UTF8"
  ncharacter_set                              = "AL16UTF16"
  whitelisted_ips                             = []
  subnet_id                                   = local.db_subnet_id

  count = local.needs_26ai ? 1 : 0

  depends_on = [
    oci_core_subnet.oke_db_subnet
  ]
}

resource "oci_database_autonomous_database_wallet" "oracle_26ai_wallet" {
  autonomous_database_id = oci_database_autonomous_database.oracle_26ai[0].id
  password = var.db_password
  generate_type = "SINGLE"
  base64_encode_content = true
  depends_on = [
    oci_database_autonomous_database.oracle_26ai
  ]
  count = local.needs_26ai ? 1 : 0
}

resource "kubernetes_secret_v1" "oadb-admin" {
  metadata {
    name      = "oadb-admin"
    namespace = "default"
  }
  data = {
    oadb_admin_pw = var.db_password
  }
  type = "Opaque"

  count = local.needs_26ai ? 1 : 0
  depends_on = [oci_database_autonomous_database.oracle_26ai]
}

resource "kubernetes_secret_v1" "oadb-connection" {
  metadata {
    name      = "oadb-connection"
    namespace = "default"
  }
  data = {
    oadb_wallet_pw = var.db_password
    oadb_service   = "${var.db_name}_TP"
  }
  type = "Opaque"

  count = local.needs_26ai ? 1 : 0
  depends_on = [oci_database_autonomous_database.oracle_26ai]
}

# ### OADB Wallet extraction <>
resource "kubernetes_secret_v1" "oadb_wallet_zip" {
  metadata {
    name      = "oadb-wallet-zip"
    namespace = "default"
  }
  data = {
    wallet = oci_database_autonomous_database_wallet.oracle_26ai_wallet[0].content
  }
  type = "Opaque"

  count = local.needs_26ai ? 1 : 0
  depends_on = [oci_database_autonomous_database.oracle_26ai, oci_database_autonomous_database_wallet.oracle_26ai_wallet]
}

resource "kubernetes_cluster_role_v1" "secret_creator" {
  metadata {
    name = "secret-creator"
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "delete"]
  }

  count = local.needs_26ai ? 1 : 0
}

resource "kubernetes_cluster_role_binding_v1" "wallet_extractor_crb" {
  metadata {
    name = "wallet-extractor-crb"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.secret_creator[0].metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.wallet_extractor_sa[0].metadata.0.name
    namespace = kubernetes_service_account_v1.wallet_extractor_sa[0].metadata[0].namespace
  }

  count = local.needs_26ai ? 1 : 0
}

resource "kubernetes_service_account_v1" "wallet_extractor_sa" {
  metadata {
    name      = "wallet-extractor-sa"
    namespace = "default"
  }

  count = local.needs_26ai ? 1 : 0
}

# Service account tokens are automatically created by Kubernetes
# No need to manually create the token secret

resource "kubernetes_job_v1" "wallet_extractor_job" {
  metadata {
    name      = "wallet-extractor-job"
    namespace = "default"
  }
  spec {
    template {
      metadata {}
      spec {
        init_container {
          name    = "wallet-extractor"
          image   = "docker.io/library/busybox:latest"
          command = ["/bin/sh", "-c"]
          args    = ["base64 -d /tmp/zip/wallet > /tmp/wallet.zip && unzip -o /tmp/wallet.zip -d /wallet"]
          volume_mount {
            mount_path = "/tmp/zip"
            name       = "wallet-zip"
            read_only  = true
          }
          volume_mount {
            mount_path = "/wallet"
            name       = "wallet"
          }
        }
        container {
          name    = "wallet-binding"
          image   = "docker.io/bitnami/kubectl:latest"
          command = ["/bin/sh", "-c"]
          args    = ["kubectl delete secret oadb-wallet --namespace=default --ignore-not-found=true && kubectl create secret generic oadb-wallet --namespace=default --from-file=/wallet"]
          volume_mount {
            mount_path = "/wallet"
            name       = "wallet"
            read_only  = true
          }
        }
        volume {
          name = "wallet-zip"
          secret {
            secret_name = kubernetes_secret_v1.oadb_wallet_zip[0].metadata[0].name
          }
        }
        volume {
          name = "wallet"
          empty_dir {}
        }
        restart_policy       = "Never"
        service_account_name = "wallet-extractor-sa"
        # Service account token is automatically mounted at /var/run/secrets/kubernetes.io/serviceaccount
      }
    }
    backoff_limit              = 1
    ttl_seconds_after_finished = 120
  }

  wait_for_completion = true
  timeouts {
    create = "20m"
    update = "20m"
  }

  depends_on = [
    oci_database_autonomous_database_wallet.oracle_26ai_wallet,
    kubernetes_service_account_v1.wallet_extractor_sa,
    kubernetes_cluster_role_binding_v1.wallet_extractor_crb
  ]
  count = local.needs_26ai ? 1 : 0
}