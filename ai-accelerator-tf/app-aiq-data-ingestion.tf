# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Pre-load AIQ default document collections (Biomedical + Financial datasets)
# into the RAG ingestor after deployment. Uses the official NVIDIA loader image
# which contains both ZIP datasets and runs zip_to_collection.py automatically.
# Ingestion takes approximately 20-30 minutes.

resource "kubernetes_job_v1" "aiq_load_files" {
  metadata {
    name      = "aiq-load-files"
    namespace = coalesce(local.starter_pack_config.aiq_namespace, "aiq")
  }

  spec {
    template {
      metadata {}
      spec {
        container {
          name  = "aiq-load-files"
          image = "nvcr.io/nvidia/blueprint/aira-load-files:v1.2.0"

          env {
            name  = "RAG_INGEST_URL"
            value = "http://ingestor-server.${local.starter_pack_config.app_namespace}.svc.cluster.local:8082/v1"
          }
          env {
            name  = "PYTHONUNBUFFERED"
            value = "1"
          }
        }

        restart_policy = "OnFailure"

        image_pull_secrets {
          name = "ngc-secret"
        }
      }
    }

    backoff_limit = 3
  }

  wait_for_completion = true

  timeouts {
    create = "60m"
    update = "60m"
  }

  count = local.deploy_app_rag_aiq ? 1 : 0

  depends_on = [
    helm_release.aiq,
    helm_release.rag,
  ]
}
