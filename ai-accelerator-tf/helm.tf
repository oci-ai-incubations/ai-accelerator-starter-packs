## Ingress Nginx
resource "helm_release" "ingress_nginx" {
  count      = local.deploy_application ? 1 : 0
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.13.3"
  namespace  = kubernetes_namespace_v1.cluster_tools[0].id
  # Need to wait for webhooks so we don't hit timing issues.
  wait          = true
  wait_for_jobs = true

  set = concat([
    {
      name  = "controller.metrics.enabled"
      value = "true"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-shape"
      value = var.ingress_load_balancer_shape
      type  = "string"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-shape-flex-min"
      value = var.ingress_load_balancer_shape_flex_min
      type  = "string"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-shape-flex-max"
      value = var.ingress_load_balancer_shape_flex_max
      type  = "string"
    }
    ], var.blueprints_endpoint_visibility == "Private" ? [
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-internal"
      value = "true"
      type  = "string"
    }
  ] : [])
  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

## NVIDIA GPU Operator — owned by the infra stack so its lifecycle is decoupled
## from per-pack app redeploys. App-stack destroy+reapply previously left GPU
## nodes in a bad state (capacity=0, nvidia.com/gpu.present=false); see BUG-018.
resource "helm_release" "nvidia-gpu-operator" {
  count            = local.deploy_infrastructure && local.uses_gpu ? 1 : 0
  name             = "gpu-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "gpu-operator"
  namespace        = "gpu-operator"
  create_namespace = true
  wait             = false
  version          = "v25.10.0"

  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

## Cert Manager
resource "helm_release" "cert_manager" {
  count      = local.deploy_application ? 1 : 0
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "1.19.1"
  namespace  = kubernetes_namespace_v1.cluster_tools[0].id
  wait       = true # wait to allow the webhook be properly configured

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "webhook.timeoutSeconds"
      value = "30"
    }
  ]

  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}


## Cert Manager Issuers
resource "helm_release" "cert_manager_issuers" {
  count     = local.deploy_application ? 1 : 0
  name      = "cert-manager-issuers"
  chart     = "${path.module}/helm-values/issuers"
  namespace = kubernetes_namespace_v1.cluster_tools[0].id
  wait      = true

  set = [
    {
      name  = "issuer.email"
      value = var.corrino_admin_email
    }
  ]
  depends_on = [
    helm_release.cert_manager
  ]
}

## Prometheus
resource "helm_release" "prometheus" {
  count      = local.deploy_application ? 1 : 0
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = "27.42.2"
  namespace  = kubernetes_namespace_v1.cluster_tools[0].id
  wait       = true

  set = [
    {
      name  = "server.persistentVolume.enabled"
      value = "true"
    },
    {
      name  = "server.persistentVolume.size"
      value = "100Gi"
    },
    {
      name  = "server.persistentVolume.storageClass"
      value = "oci-bv"
    },
    {
      name  = "alertmanager.persistentVolume.enabled"
      value = "true"
    },
    {
      name  = "alertmanager.persistentVolume.size"
      value = "20Gi"
    },
    {
      name  = "alertmanager.persistentVolume.storageClass"
      value = "oci-bv"
    },
    {
      name  = "server.service.type"
      value = "ClusterIP"
    },
    {
      name  = "pushgateway.enabled"
      value = "true"
    },
    {
      name  = "nodeExporter.enabled"
      value = "true"
    },
    {
      name  = "kubeStateMetrics.enabled"
      value = "true"
    },
    # Add docker.io registry prefix for Prometheus component images
    # Note: alertmanager.image.registry is not supported in chart version 27.42.2
    {
      name  = "server.image.registry"
      value = "docker.io"
    },
    {
      name  = "pushgateway.image.registry"
      value = "docker.io"
    },
    {
      name  = "nodeExporter.image.registry"
      value = "docker.io"
    },
    {
      name  = "kubeStateMetrics.image.registry"
      value = "docker.io"
    }
  ]

  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

resource "helm_release" "grafana" {
  count      = local.deploy_application ? 1 : 0
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "10.1.4"
  namespace  = kubernetes_namespace_v1.cluster_tools[0].id
  wait       = false

  set = [
    {
      name  = "grafana\\.ini.server.root_url"
      value = "%(protocol)s://%(domain)s:%(http_port)s/"
      type  = "string"
    },
    {
      name  = "grafana\\.ini.server.serve_from_sub_path"
      value = "false"
    },
    # Add docker.io registry prefix for Grafana image
    {
      name  = "image.registry"
      value = "docker.io"
    }
  ]

  values = [
    <<EOF
dashboards:
  default:
    k8s-cluster:
      gnetId: 7249
      revision: 1
      datasource: Prometheus
    k8s-cluster-metrics:
      gnetId: 11663
      revision: 1
      datasource: Prometheus
    k8s-cluster-metrics-simple:
      gnetId: 6417
      revision: 1
      datasource: Prometheus
    k8s-pods-monitoring:
      gnetId: 13498
      revision: 1
      datasource: Prometheus
    k8s-memory:
      gnetId: 13421
      revision: 1
      datasource: Prometheus
    k8s-networking:
      gnetId: 12658
      revision: 1
      datasource: Prometheus
    k8s-cluster-autoscaler:
      gnetId: 3831
      revision: 1
      datasource: Prometheus
    k8s-hpa:
      gnetId: 10257
      revision: 1
      datasource: Prometheus
    k8s-pods:
      gnetId: 6336
      revision: 1
      datasource: Prometheus
    spring-boot:
      gnetId: 12464
      revision: 2
      datasource: Prometheus
    nginx-ingress-controller:
      gnetId: 9614
      revision: 1
      datasource: Prometheus
    oci-compute:
      gnetId: 13596
      revision: 1
      datasource: Oracle Cloud Infrastructure Metrics
    oci-oke:
      gnetId: 13594
      revision: 1
      datasource: Oracle Cloud Infrastructure Metrics
    nvidia-dcgm:
      gnetId: 12239
      revision: 2
      datasource: Prometheus
dashboardProviders:
   dashboardproviders.yaml:
     apiVersion: 1
     providers:
     - name: 'default'
       orgId: 1
       folder: ''
       type: file
       disableDeletion: true
       editable: true
       options:
         path: /var/lib/grafana/dashboards/default
sidecar:
  datasources:
    enabled: true
    label: grafana_datasource
  dashboards:
    enabled: true
    label: grafana_dashboard
persistence:
  enabled: true
  existingClaim: grafana-pvc
plugins:
  - oci-logs-datasource
  - oci-metrics-datasource
  - grafana-kubernetes-app
  - grafana-worldmap-panel
  - grafana-piechart-panel
  - btplc-status-dot-panel
datasources: 
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.${kubernetes_namespace_v1.cluster_tools[0].id}.svc.cluster.local
      access: proxy
      isDefault: true
      disableDeletion: true
      editable: false
    - name: Oracle Cloud Infrastructure Metrics
      type: oci-metrics-datasource
      access: proxy
      disableDeletion: true
      editable: true
      jsonData:
        tenancyOCID: ${var.tenancy_ocid}
        defaultRegion: ${var.region}
        environment: "OCI Instance"
    - name: Oracle Cloud Infrastructure Logs
      type: oci-logs-datasource
      access: proxy
      disableDeletion: true
      editable: true
      jsonData:
        tenancyOCID: ${var.tenancy_ocid}
        defaultRegion: ${var.region}
        environment: "OCI Instance"
EOF
  ]

  depends_on = [kubernetes_persistent_volume_claim_v1.grafana, helm_release.prometheus]
}

resource "kubernetes_config_map_v1" "vllm_dashboard" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name      = "vllm-custom-dashboard"
    namespace = kubernetes_namespace_v1.cluster_tools[0].id
    labels = {
      grafana_dashboard = "true"
    }
  }

  data = {
    "vllm-dashboard.json" = file("${path.module}/dashboards/vllm-dashboard.json")
  }

  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

resource "kubernetes_persistent_volume_claim_v1" "grafana" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name      = "grafana-pvc"
    namespace = kubernetes_namespace_v1.cluster_tools[0].id
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "50Gi"
      }
    }

    storage_class_name = "oci-bv"
  }

  wait_until_bound = false

  timeouts {
    create = "5m"
  }

  depends_on = [oci_containerengine_node_pool.oke_node_pool, kubernetes_namespace_v1.cluster_tools]
}
## Kubernetes Secret: Grafana Admin Password
data "kubernetes_secret_v1" "grafana" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.cluster_tools[0].id
  }
  depends_on = [helm_release.grafana]
}

locals {
  grafana_admin_password = local.deploy_application ? data.kubernetes_secret_v1.grafana[0].data.admin-password : "not-deployed"
}

resource "helm_release" "milvus" {
  name       = "milvus"
  repository = "https://zilliztech.github.io/milvus-helm/"
  chart      = "milvus"
  version    = "5.0.10"
  namespace  = kubernetes_namespace_v1.milvus[0].id
  wait       = false

  set = [
    {
      name  = "image.all.tag"
      value = "v2.6.7"
    },
    {
      name  = "cluster.enabled",
      value = "false"
    },
    {
      name  = "pulsarv3.enabled"
      value = "false"
    },
    {
      name  = "standalone.messageQueue"
      value = "woodpecker"
    },
    {
      name  = "woodpecker.enabled"
      value = "true"
    },
    {
      name  = "streaming.enabled"
      value = "true"
    },
    {
      name  = "minio.mode"
      value = "standalone"
    },
    {
      name  = "etcd.replicaCount"
      value = "1"
    },
    {
      name  = "minio.image.repository"
      value = "quay.io/minio/minio"
    },
    {
      name  = "minio.image.tag"
      value = "RELEASE.2024-12-18T13-15-44Z"
    },
    {
      name  = "image.all.repository"
      value = "docker.io/milvusdb/milvus"
    }
  ]
  count      = local.deploy_app_vss ? 1 : 0
  depends_on = [oci_containerengine_node_pool.worker_cpu_pool]
}

resource "kubernetes_namespace_v1" "app_namespace" {
  count = local.deploy_application && local.starter_pack_config.app_namespace != "default" ? 1 : 0
  metadata {
    name = local.starter_pack_config.app_namespace
  }
}

# Create the AIQ namespace before the configure_oke_for_aiq_namespace job runs.
# The job creates NGC secrets in this namespace, and the AIQ Helm release deploys into it.
# Without this, the job fails because the namespace doesn't exist yet. (BUG-010)
resource "kubernetes_namespace_v1" "aiq_namespace" {
  count = local.deploy_app_rag_aiq ? 1 : 0
  metadata {
    name = coalesce(local.starter_pack_config.aiq_namespace, "aiq")
  }
}

# NIM Operator handles GPU node scheduling via NIMCache/NIMService CRs.
# The workload=nim-llm taint is no longer applied — the nvidia.com/gpu taint
# from GPU Feature Discovery is sufficient, and NIMCache CRs include tolerations.

# Read the NGC API key created by configure_oke.py to authenticate with NGC helm registry
data "kubernetes_secret_v1" "ngc_api_secret" {
  metadata {
    name      = "ngc-api-secret"
    namespace = local.starter_pack_config.app_namespace
  }
  count      = local.deploy_app_rag ? 1 : 0
  depends_on = [kubernetes_job_v1.configure_oke_for_blueprint_deployment_job]
}

resource "helm_release" "nim_operator" {
  count            = local.deploy_app_rag ? 1 : 0
  name             = "nim-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "k8s-nim-operator"
  version          = "3.1.0"
  namespace        = "nim-operator"
  create_namespace = true
  wait             = true
  timeout          = 600

  repository_username = "$oauthtoken"
  repository_password = data.kubernetes_secret_v1.ngc_api_secret[0].data["NGC_API_KEY"]

  depends_on = [helm_release.nvidia-gpu-operator, kubernetes_job_v1.configure_oke_for_blueprint_deployment_job]
}

resource "helm_release" "rag" {
  name             = "rag"
  namespace        = local.starter_pack_config.app_namespace
  create_namespace = true

  chart = "https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.5.0.tgz"

  repository_username = "$oauthtoken"
  repository_password = data.kubernetes_secret_v1.ngc_api_secret[0].data["NGC_API_KEY"]

  timeout         = 5400 # Increase timeout to 90 minutes
  cleanup_on_fail = true

  # wait=false so Terraform returns as soon as Helm dispatches the release,
  # unblocking terraform_data.patch_nim_operator_resources which patches the
  # NIMCache/NIMService CRs with GPU tolerations and deletes stuck cache pods
  # so they reschedule on GPU nodes. With the default wait=true, Helm blocks
  # waiting for pods to become Ready, but pods can't schedule until the
  # post-install patch runs — deadlock past the 90-minute timeout.
  # The patch hook itself blocks until NIMCache/NIMService report Ready, so
  # apply still gates on actual workload readiness despite wait=false.
  wait = false

  values = [
    {
      enterprise_rag     = file("${path.module}/helm-values/enterprise-rag-values.yaml")
      enterprise_rag_aiq = file("${path.module}/helm-values/enterprise-rag-aiq-values.yaml")
    }[var.starter_pack_category]
  ]

  set_sensitive = concat(
    [
      {
        name  = "imagePullSecret.password"
        value = data.kubernetes_secret_v1.ngc_api_secret[0].data["NGC_API_KEY"]
      },
      {
        name  = "ngcApiSecret.password"
        value = data.kubernetes_secret_v1.ngc_api_secret[0].data["NGC_API_KEY"]
      }
    ],
    # Oracle 26ai credentials needed for both enterprise_rag and enterprise_rag_aiq
    [
      {
        name  = "envVars.ORACLE_USER"
        value = var.db_username
      },
      {
        name  = "envVars.ORACLE_PASSWORD"
        value = var.db_password
      },
      {
        name  = "ingestor-server.envVars.ORACLE_USER"
        value = var.db_username
      },
      {
        name  = "ingestor-server.envVars.ORACLE_PASSWORD"
        value = var.db_password
      }
    ]
  )

  set = concat(
    [
      {
        name  = "global.ngcApiKey"
        value = data.kubernetes_secret_v1.ngc_api_secret[0].data["NGC_API_KEY"]
      },
      {
        name  = "frontend.image.repository"
        value = split(":", local.frontend_skin_image_uri)[0]
      },
      {
        name  = "frontend.image.tag"
        value = split(":", local.frontend_skin_image_uri)[1]
      }
    ],
    # Oracle 26ai connection string needed for both enterprise_rag and enterprise_rag_aiq
    [
      {
        name  = "envVars.ORACLE_CS"
        value = local.oracle26ai_high_connection_string
      },
      {
        name  = "ingestor-server.envVars.ORACLE_CS"
        value = local.oracle26ai_high_connection_string
      }
    ]
  )
  count = local.deploy_app_rag ? 1 : 0
  depends_on = [
    oci_core_instance_pool.worker_nodes_pool, oci_core_cluster_network.worker_nodes_cluster_network, kubernetes_job_v1.configure_oke_for_blueprint_deployment_job,
    oci_database_autonomous_database.oracle_26ai, kubernetes_secret_v1.oci_config_secret,
    helm_release.nim_operator
  ]
}

resource "local_sensitive_file" "kubeconfig_patch" {
  count    = local.deploy_app_rag ? 1 : 0
  content  = data.oci_containerengine_cluster_kube_config.oke.content
  filename = "${path.module}/kubeconfig_patch"
}

resource "terraform_data" "patch_nim_operator_resources" {
  count = local.deploy_app_rag && !local.readiness_via_operator ? 1 : 0

  triggers_replace = [
    local.cluster_id,
    "patch_nim_operator_resources_v3"
  ]

  depends_on = [
    helm_release.rag,
    local_sensitive_file.kubeconfig_patch,
    kubernetes_secret_v1.oci_config_secret,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${local_sensitive_file.kubeconfig_patch[0].filename}
      NS=${local.starter_pack_config.app_namespace}

      echo "Patching NIMCache CRs with GPU tolerations..."
      for cache in nim-llm-cache nemotron-embedding-ms-cache nemotron-ranking-ms-cache \
        nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
        nemoretriever-page-elements-v3 nemoretriever-table-structure-v1; do
        kubectl patch nimcache "$cache" -n "$NS" --type=merge \
          -p '{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}]}}' 2>/dev/null && \
          echo "  Patched nimcache/$cache" || echo "  Skipped nimcache/$cache (not found yet)"
      done

      echo "Patching LLM NIMCache with vllm/fp8/TP8 engine..."
      kubectl patch nimcache nim-llm-cache -n "$NS" --type=merge \
        -p '{"spec":{"source":{"ngc":{"model":{"engine":"vllm","precision":"fp8","tensorParallelism":"8"}}}}}' 2>/dev/null || true

      echo "Patching NIMService CRs with GPU tolerations..."
      for svc in nim-llm nemotron-embedding-ms nemotron-ranking-ms \
        nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
        nemoretriever-page-elements-v3 nemoretriever-table-structure-v1; do
        kubectl patch nimservice "$svc" -n "$NS" --type=merge \
          -p '{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}]}}' 2>/dev/null && \
          echo "  Patched nimservice/$svc" || echo "  Skipped nimservice/$svc (not found yet)"
      done

      echo "Fixing nim-llm service selector (remove stale statefulset selector)..."
      kubectl patch service nim-llm -n "$NS" --type=json \
        -p '[{"op":"remove","path":"/spec/selector/statefulset.kubernetes.io~1pod-name"}]' 2>/dev/null && \
        echo "  Fixed nim-llm service selector" || echo "  nim-llm service selector already correct"

      echo "Deleting NIMCache pods to trigger recreation with tolerations..."
      for cache in nim-llm-cache nemotron-embedding-ms-cache nemotron-ranking-ms-cache \
        nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
        nemoretriever-page-elements-v3 nemoretriever-table-structure-v1; do
        kubectl delete pod "$${cache}-pod" -n "$NS" 2>/dev/null || true
      done

      NON_LLM_CACHES="nemotron-embedding-ms-cache nemotron-ranking-ms-cache \
        nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
        nemoretriever-page-elements-v3 nemoretriever-table-structure-v1"
      NON_LLM_SERVICES="nemotron-embedding-ms nemotron-ranking-ms \
        nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
        nemoretriever-page-elements-v3 nemoretriever-table-structure-v1"
      LLM_SERVICE="nim-llm"

      llm_runtime_ready() {
        echo "Waiting for runtime readiness: $LLM_SERVICE Deployment Available + model API..."

        for i in $(seq 1 540); do
          if kubectl get deployment "$LLM_SERVICE" -n "$NS" >/dev/null 2>&1; then
            break
          fi

          echo "  Waiting for deployment/$LLM_SERVICE to be created ($i/540)..."
          sleep 10
        done

        kubectl get deployment "$LLM_SERVICE" -n "$NS" >/dev/null 2>&1 || return 1

        kubectl wait deployment/"$LLM_SERVICE" -n "$NS" \
          --for=condition=Available --timeout=30m || return 1

        for i in $(seq 1 60); do
          if kubectl exec -n "$NS" deploy/"$LLM_SERVICE" -- \
              curl -fsS http://localhost:8000/v1/health/ready >/dev/null && \
             kubectl exec -n "$NS" deploy/"$LLM_SERVICE" -- \
              curl -fsS http://localhost:8000/v1/models >/dev/null; then
            echo "  Ready: runtime/$LLM_SERVICE"
            return 0
          fi

          echo "  Waiting for runtime/$LLM_SERVICE ($i/60)..."
          sleep 10
        done

        echo "  TIMED OUT: runtime/$LLM_SERVICE"
        return 1
      }

      # Block until the patched NIM resources actually reach Ready. The six
      # non-LLM services continue to use operator CR readiness. nim-llm is
      # checked by runtime health because nim-operator can leave its CR stale
      # after the model is already serving.
      echo "Waiting for non-LLM NIMCache CRs to be Ready (up to 90m)..."
      pids=""
      for cache in $NON_LLM_CACHES; do
        ( kubectl wait nimcache "$cache" -n "$NS" \
            --for=jsonpath='{.status.state}=Ready' --timeout=90m \
            && echo "  Ready: nimcache/$cache" \
            || echo "  TIMED OUT: nimcache/$cache" ) &
        pids="$pids $!"
      done
      wait $pids

      not_ready_caches=""
      for cache in $NON_LLM_CACHES; do
        state=$(kubectl get nimcache "$cache" -n "$NS" \
          -o jsonpath='{.status.state}' 2>/dev/null || true)
        if [ "$state" != "Ready" ]; then
          display_state="$state"
          if [ -z "$display_state" ]; then
            display_state="MISSING"
          fi
          not_ready_caches="$not_ready_caches
  - $cache state=$display_state"
        fi
      done
      if [ -n "$not_ready_caches" ]; then
        echo "ERROR: the following non-LLM NIMCache CRs are not Ready:"
        echo "$not_ready_caches"
        exit 1
      fi

      echo "Waiting for non-LLM NIMService CRs to be Ready (up to 30m)..."
      pids=""
      for svc in $NON_LLM_SERVICES; do
        ( kubectl wait nimservice "$svc" -n "$NS" \
            --for=condition=Ready --timeout=30m \
            && echo "  Ready: nimservice/$svc" \
            || echo "  TIMED OUT: nimservice/$svc" ) &
        pids="$pids $!"
      done
      wait $pids

      not_ready_services=""
      for svc in $NON_LLM_SERVICES; do
        state=$(kubectl get nimservice "$svc" -n "$NS" \
          -o jsonpath='{.status.state}' 2>/dev/null || true)
        ready=$(kubectl get nimservice "$svc" -n "$NS" \
          -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)
        if [ "$state" != "Ready" ] || [ "$ready" != "True" ]; then
          display_state="$state"
          display_ready="$ready"
          if [ -z "$display_state" ]; then
            display_state="MISSING"
          fi
          if [ -z "$display_ready" ]; then
            display_ready="MISSING"
          fi
          not_ready_services="$not_ready_services
  - $svc state=$display_state ready=$display_ready"
        fi
      done
      if [ -n "$not_ready_services" ]; then
        echo "ERROR: the following non-LLM NIMService CRs are not Ready:"
        echo "$not_ready_services"
        exit 1
      fi

      if ! llm_runtime_ready; then
        echo "ERROR: nim-llm runtime health check failed."
        kubectl get nimcache nim-llm-cache -n "$NS" -o wide 2>/dev/null || true
        kubectl get nimservice "$LLM_SERVICE" -n "$NS" -o wide 2>/dev/null || true
        exit 1
      fi

      echo "NIM Operator post-deploy patches complete."
    EOT
  }
}

# Destroy-time cleanup: clears NIMCache/NIMService finalizers so the rag
# namespace can be torn down cleanly. Without this, terraform destroys the
# nim-operator helm release first (it's an explicit dependency of rag),
# leaving NIMCache CRs in the namespace with `finalizer.nimcache.apps.nvidia.com`
# attached and no controller alive to release them — namespace stays in
# Terminating forever and the destroy job fails with "context deadline
# exceeded". Symmetric to the apply-time patch hook above.
resource "terraform_data" "nim_operator_destroy_cleanup" {
  count = local.deploy_app_rag && !local.readiness_via_operator ? 1 : 0

  triggers_replace = {
    cluster_id    = local.cluster_id
    region        = var.region
    app_namespace = local.starter_pack_config.app_namespace
    nim_op_ns     = "nim-operator"
  }

  depends_on = [
    helm_release.rag,
    helm_release.nim_operator,
    local_sensitive_file.kubeconfig_patch,
  ]

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = <<-EOT
      # Generate a fresh kubeconfig at destroy time. The apply-time
      # local_sensitive_file.kubeconfig_patch embeds an OKE token that expires
      # in ~5 minutes; on destroy it's almost always stale, which silently
      # turns kubectl calls into empty-list/no-auth no-ops and the cleanup
      # accomplishes nothing. Always re-issue from cluster_id.
      KCFG=$(mktemp -d)/kubeconfig
      oci ce cluster create-kubeconfig \
        --cluster-id ${self.triggers_replace.cluster_id} \
        --region ${self.triggers_replace.region} \
        --token-version 2.0.0 \
        --kube-endpoint PUBLIC_ENDPOINT \
        --file "$KCFG" >/dev/null 2>&1
      export KUBECONFIG="$KCFG"
      NS=${self.triggers_replace.app_namespace}
      OP_NS=${self.triggers_replace.nim_op_ns}

      echo "Scaling all deployments in $OP_NS to 0 (stop the operator processing finalizers)..."
      kubectl scale deploy -n "$OP_NS" --all --replicas=0 2>/dev/null || true

      echo "Clearing NIMCache finalizers in $NS..."
      for cr in $(kubectl get nimcache -n "$NS" -o name 2>/dev/null); do
        kubectl patch "$cr" -n "$NS" --type=merge \
          -p '{"metadata":{"finalizers":null}}' 2>/dev/null \
          && echo "  Cleared $cr" || true
      done

      echo "Clearing NIMService finalizers in $NS..."
      for cr in $(kubectl get nimservice -n "$NS" -o name 2>/dev/null); do
        kubectl patch "$cr" -n "$NS" --type=merge \
          -p '{"metadata":{"finalizers":null}}' 2>/dev/null \
          && echo "  Cleared $cr" || true
      done

      echo "NIM Operator destroy cleanup complete."
    EOT
  }
}

resource "terraform_data" "patch_nim_operator_resources_via_operator" {
  count = local.deploy_app_rag && local.readiness_via_operator ? 1 : 0

  triggers_replace = [
    local.cluster_id,
    "patch_nim_operator_resources_v3"
  ]

  depends_on = [
    helm_release.rag,
    kubernetes_secret_v1.oci_config_secret,
  ]

  provisioner "remote-exec" {
    connection {
      type                = "ssh"
      user                = "opc"
      host                = oci_core_instance.operator[0].private_ip
      private_key         = tls_private_key.oke_ssh_key[0].private_key_pem
      bastion_host        = oci_core_instance.bastion[0].public_ip
      bastion_user        = "opc"
      bastion_private_key = tls_private_key.oke_ssh_key[0].private_key_pem
      timeout             = "30m"
    }
    inline = [
      <<-EOT
        NS=${local.starter_pack_config.app_namespace}

        echo "Patching NIMCache CRs with GPU tolerations..."
        for cache in nim-llm-cache nemotron-embedding-ms-cache nemotron-ranking-ms-cache \
          nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
          nemoretriever-page-elements-v3 nemoretriever-table-structure-v1; do
          kubectl patch nimcache "$cache" -n "$NS" --type=merge \
            -p '{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}]}}' 2>/dev/null && \
            echo "  Patched nimcache/$cache" || echo "  Skipped nimcache/$cache (not found yet)"
        done

        echo "Patching LLM NIMCache with vllm/fp8/TP8 engine..."
        kubectl patch nimcache nim-llm-cache -n "$NS" --type=merge \
          -p '{"spec":{"source":{"ngc":{"model":{"engine":"vllm","precision":"fp8","tensorParallelism":"8"}}}}}' 2>/dev/null || true

        echo "Patching NIMService CRs with GPU tolerations..."
        for svc in nim-llm nemotron-embedding-ms nemotron-ranking-ms \
          nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
          nemoretriever-page-elements-v3 nemoretriever-table-structure-v1; do
          kubectl patch nimservice "$svc" -n "$NS" --type=merge \
            -p '{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}]}}' 2>/dev/null && \
            echo "  Patched nimservice/$svc" || echo "  Skipped nimservice/$svc (not found yet)"
        done

        echo "Fixing nim-llm service selector (remove stale statefulset selector)..."
        kubectl patch service nim-llm -n "$NS" --type=json \
          -p '[{"op":"remove","path":"/spec/selector/statefulset.kubernetes.io~1pod-name"}]' 2>/dev/null && \
          echo "  Fixed nim-llm service selector" || echo "  nim-llm service selector already correct"

        echo "Deleting NIMCache pods to trigger recreation with tolerations..."
        for cache in nim-llm-cache nemotron-embedding-ms-cache nemotron-ranking-ms-cache \
          nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
          nemoretriever-page-elements-v3 nemoretriever-table-structure-v1; do
          kubectl delete pod "$cache-pod" -n "$NS" 2>/dev/null || true
        done

        NON_LLM_CACHES="nemotron-embedding-ms-cache nemotron-ranking-ms-cache \
          nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
          nemoretriever-page-elements-v3 nemoretriever-table-structure-v1"
        NON_LLM_SERVICES="nemotron-embedding-ms nemotron-ranking-ms \
          nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
          nemoretriever-page-elements-v3 nemoretriever-table-structure-v1"
        LLM_SERVICE="nim-llm"

        llm_runtime_ready() {
          echo "Waiting for runtime readiness: $LLM_SERVICE Deployment Available + model API..."

          for i in $(seq 1 540); do
            if kubectl get deployment "$LLM_SERVICE" -n "$NS" >/dev/null 2>&1; then
              break
            fi

            echo "  Waiting for deployment/$LLM_SERVICE to be created ($i/540)..."
            sleep 10
          done

          kubectl get deployment "$LLM_SERVICE" -n "$NS" >/dev/null 2>&1 || return 1

          kubectl wait deployment/"$LLM_SERVICE" -n "$NS" \
            --for=condition=Available --timeout=30m || return 1

          for i in $(seq 1 60); do
            if kubectl exec -n "$NS" deploy/"$LLM_SERVICE" -- \
                curl -fsS http://localhost:8000/v1/health/ready >/dev/null && \
               kubectl exec -n "$NS" deploy/"$LLM_SERVICE" -- \
                curl -fsS http://localhost:8000/v1/models >/dev/null; then
              echo "  Ready: runtime/$LLM_SERVICE"
              return 0
            fi

            echo "  Waiting for runtime/$LLM_SERVICE ($i/60)..."
            sleep 10
          done

          echo "  TIMED OUT: runtime/$LLM_SERVICE"
          return 1
        }

        echo "Waiting for non-LLM NIMCache CRs to be Ready (up to 90m)..."
        pids=""
        for cache in $NON_LLM_CACHES; do
          ( kubectl wait nimcache "$cache" -n "$NS" \
              --for=jsonpath='{.status.state}=Ready' --timeout=90m \
              && echo "  Ready: nimcache/$cache" \
              || echo "  TIMED OUT: nimcache/$cache" ) &
          pids="$pids $!"
        done
        wait $pids

        not_ready_caches=""
        for cache in $NON_LLM_CACHES; do
          state=$(kubectl get nimcache "$cache" -n "$NS" \
            -o jsonpath='{.status.state}' 2>/dev/null || true)
          if [ "$state" != "Ready" ]; then
            display_state="$state"
            if [ -z "$display_state" ]; then
              display_state="MISSING"
            fi
            not_ready_caches="$not_ready_caches
        - $cache state=$display_state"
          fi
        done
        if [ -n "$not_ready_caches" ]; then
          echo "ERROR: the following non-LLM NIMCache CRs are not Ready:"
          echo "$not_ready_caches"
          exit 1
        fi

        echo "Waiting for non-LLM NIMService CRs to be Ready (up to 30m)..."
        pids=""
        for svc in $NON_LLM_SERVICES; do
          ( kubectl wait nimservice "$svc" -n "$NS" \
              --for=condition=Ready --timeout=30m \
              && echo "  Ready: nimservice/$svc" \
              || echo "  TIMED OUT: nimservice/$svc" ) &
          pids="$pids $!"
        done
        wait $pids

        not_ready_services=""
        for svc in $NON_LLM_SERVICES; do
          state=$(kubectl get nimservice "$svc" -n "$NS" \
            -o jsonpath='{.status.state}' 2>/dev/null || true)
          ready=$(kubectl get nimservice "$svc" -n "$NS" \
            -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)
          if [ "$state" != "Ready" ] || [ "$ready" != "True" ]; then
            display_state="$state"
            display_ready="$ready"
            if [ -z "$display_state" ]; then
              display_state="MISSING"
            fi
            if [ -z "$display_ready" ]; then
              display_ready="MISSING"
            fi
            not_ready_services="$not_ready_services
        - $svc state=$display_state ready=$display_ready"
          fi
        done
        if [ -n "$not_ready_services" ]; then
          echo "ERROR: the following non-LLM NIMService CRs are not Ready:"
          echo "$not_ready_services"
          exit 1
        fi

        if ! llm_runtime_ready; then
          echo "ERROR: nim-llm runtime health check failed."
          kubectl get nimcache nim-llm-cache -n "$NS" -o wide 2>/dev/null || true
          kubectl get nimservice "$LLM_SERVICE" -n "$NS" -o wide 2>/dev/null || true
          exit 1
        fi

        echo "NIM Operator post-deploy patches complete."
      EOT
    ]
  }
}



# Pre-create the aiq-credentials secret required by the v2.0.0 chart.
# The chart's sharedSecrets.autoMount wires these into env via envFrom.
resource "kubernetes_secret_v1" "aiq_credentials" {
  count = local.deploy_app_rag_aiq ? 1 : 0
  metadata {
    name      = "aiq-credentials"
    namespace = coalesce(local.starter_pack_config.aiq_namespace, "aiq")
  }
  data = {
    NVIDIA_API_KEY   = data.kubernetes_secret_v1.ngc_api_secret[0].data["NGC_API_KEY"]
    TAVILY_API_KEY   = var.tavily_api_key
    DB_USER_NAME     = "aiq"
    DB_USER_PASSWORD = random_password.aiq_db_password[0].result
  }
  type       = "Opaque"
  depends_on = [kubernetes_job_v1.configure_oke_for_aiq_namespace, kubernetes_namespace_v1.aiq_namespace]
}

resource "random_password" "aiq_db_password" {
  count   = local.deploy_app_rag_aiq ? 1 : 0
  length  = 24
  special = false
}

resource "helm_release" "aiq" {
  name             = "aiq"
  namespace        = coalesce(local.starter_pack_config.aiq_namespace, "aiq")
  create_namespace = true

  # AIQ v2.0.0 — renamed chart (aiq-aira → aiq2-web). Breaking changes:
  # - Values structure rewritten from flat to nested under aiq.apps.<component>
  # - Backend image: aira-backend → aiq-agent, Frontend: aira-frontend → aiq-frontend
  # - Requires aiq-credentials secret (NVIDIA_API_KEY, TAVILY_API_KEY, DB_USER_NAME, DB_USER_PASSWORD)
  # - Bundled Postgres (no more Phoenix, no more bundled NIM)
  # - RAG URLs require /v1 suffix
  chart = "https://helm.ngc.nvidia.com/nvidia/blueprint/charts/aiq2-web-2.0.0.tgz"

  repository_username = "$oauthtoken"
  repository_password = data.kubernetes_secret_v1.ngc_api_secret[0].data["NGC_API_KEY"]

  timeout         = 3600
  cleanup_on_fail = true

  values = [
    file("${path.module}/helm-values/aiq-aira-values.yaml")
  ]

  set = [
    # Point AIQ at our enterprise_rag v2.5.0 services in the rag namespace.
    # v2.0.0 requires /v1 suffix on both RAG URLs.
    {
      name  = "aiq.apps.backend.env.RAG_SERVER_URL"
      value = "http://rag-server.${local.starter_pack_config.app_namespace}.svc.cluster.local:8081/v1"
    },
    {
      name  = "aiq.apps.backend.env.RAG_INGEST_URL"
      value = "http://ingestor-server.${local.starter_pack_config.app_namespace}.svc.cluster.local:8082/v1"
    },
    # BUG-020 fix: enterprise_rag_aiq's user-facing frontend is aiq-frontend
    # (from this `aiq` Helm release). The skin_enterprise_rag_aiq enum dropdown
    # must override THIS release's frontend image for the selection to take effect.
    {
      name  = "aiq.apps.frontend.image.repository"
      value = split(":", local.frontend_skin_image_uri)[0]
    },
    {
      name  = "aiq.apps.frontend.image.tag"
      value = split(":", local.frontend_skin_image_uri)[1]
    }
  ]

  count = local.deploy_app_rag_aiq ? 1 : 0

  # The aiq stack depends on the rag stack deployment to complete and
  # the AIQ namespace secrets to be created by configure_oke.
  depends_on = [
    helm_release.rag,
    terraform_data.patch_nim_operator_resources,
    terraform_data.patch_nim_operator_resources_via_operator,
    kubernetes_job_v1.configure_oke_for_aiq_namespace,
    kubernetes_secret_v1.aiq_credentials,
  ]
}

# Restart AIQ backend pods whenever the Tavily key changes so they pick up the
# updated secret. Helm upgrades the secret but running pods don't restart
# automatically when only a Secret value changes.
resource "terraform_data" "aiq_restart_on_tavily_change" {
  triggers_replace = [var.tavily_api_key]

  provisioner "local-exec" {
    command = "export KUBECONFIG=${local_sensitive_file.kubeconfig_patch[0].filename} && kubectl rollout restart deployment -n ${coalesce(local.starter_pack_config.aiq_namespace, "aiq")} && kubectl rollout status deployment -n ${coalesce(local.starter_pack_config.aiq_namespace, "aiq")} --timeout=300s"
  }

  depends_on = [helm_release.aiq]
  count      = local.deploy_app_rag_aiq && !local.readiness_via_operator ? 1 : 0
}

resource "terraform_data" "aiq_restart_on_tavily_change_via_operator" {
  triggers_replace = [var.tavily_api_key]

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.operator[0].private_ip
    private_key         = tls_private_key.oke_ssh_key[0].private_key_pem
    bastion_host        = oci_core_instance.bastion[0].public_ip
    bastion_user        = "opc"
    bastion_private_key = tls_private_key.oke_ssh_key[0].private_key_pem
    timeout             = "30m"
  }

  provisioner "remote-exec" {
    inline = [
      "kubectl rollout restart deployment -n ${coalesce(local.starter_pack_config.aiq_namespace, "aiq")}",
      "kubectl rollout status deployment -n ${coalesce(local.starter_pack_config.aiq_namespace, "aiq")} --timeout=300s"
    ]
  }

  depends_on = [null_resource.operator_ready, helm_release.aiq]
  count      = local.deploy_app_rag_aiq && local.readiness_via_operator ? 1 : 0
}
