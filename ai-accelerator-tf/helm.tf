## Ingress Nginx
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.13.3"
  namespace  = kubernetes_namespace_v1.cluster_tools.id
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

## NVIDIA DCGM Exporter - Commented out temporarily due to chart not found
resource "helm_release" "nvidia-gpu-operator" {
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
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "1.19.1"
  namespace  = kubernetes_namespace_v1.cluster_tools.id
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
  name      = "cert-manager-issuers"
  chart     = "${path.module}/helm-values/issuers"
  namespace = kubernetes_namespace_v1.cluster_tools.id
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
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = "27.42.2"
  namespace  = kubernetes_namespace_v1.cluster_tools.id
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
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "10.1.4"
  namespace  = kubernetes_namespace_v1.cluster_tools.id
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
      url: http://prometheus-server.${kubernetes_namespace_v1.cluster_tools.id}.svc.cluster.local
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
  metadata {
    name      = "vllm-custom-dashboard"
    namespace = kubernetes_namespace_v1.cluster_tools.id
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
  metadata {
    name      = "grafana-pvc"
    namespace = kubernetes_namespace_v1.cluster_tools.id
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
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.cluster_tools.id
  }
  depends_on = [helm_release.grafana]
}

locals {
  grafana_admin_password = data.kubernetes_secret_v1.grafana.data.admin-password
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
  count      = var.starter_pack_category == "vss" ? 1 : 0
  depends_on = [oci_containerengine_node_pool.worker_cpu_pool]
}

resource "helm_release" "rag" {
  name             = "rag"
  namespace        = local.starter_pack_config.app_namespace
  create_namespace = true

  chart = "https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz"

  repository_username = "$oauthtoken"

  timeout = 5400 # Increase timeout to 90 minutes

  values = [
    file("${path.module}/helm-values/enterprise-rag-values.yaml")
  ]

  set_sensitive = [
    {
      name  = "envVars.MINIO_ACCESSKEY"
      value = random_string.minio_access_key.result
    },
    {
      name  = "envVars.MINIO_SECRETKEY"
      value = random_password.minio_secret_key.result
    },
    {
      name  = "ingestor-server.envVars.MINIO_ACCESSKEY"
      value = random_string.minio_access_key.result
    },
    {
      name  = "ingestor-server.envVars.MINIO_SECRETKEY"
      value = random_password.minio_secret_key.result
    },
    {
      name  = "nv-ingest.milvus.minio.accessKey"
      value = random_string.minio_access_key.result
    },
    {
      name  = "nv-ingest.milvus.minio.secretKey"
      value = random_password.minio_secret_key.result
    }
  ]

  set = [
    {
      name  = "imagePullSecret.create"
      value = "false"
    },
    {
      name  = "ngcApiSecret.create"
      value = "false"
    },
    {
      name  = "milvus.standalone.resources.limits.nvidia\\.com/gpu"
      value = "0"
    },
    {
      name  = "milvus.standalone.resources.limits.cpu"
      value = "8"
    },
    {
      name  = "milvus.standalone.resources.limits.memory"
      value = "24Gi"
    },
    {
      name  = "milvus.app_vectorstore_enablegpusearch"
      value = "False"
    },
    {
      name  = "nim-llm.image.repository"
      value = "nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5"
    },
    {
      name  = "nim-llm.image.tag"
      value = "1.14.0"
    }
  ]
  count      = var.starter_pack_category == "enterprise_rag" ? 1 : 0
  depends_on = [oci_core_instance_pool.worker_nodes_pool, oci_core_cluster_network.worker_nodes_cluster_network, kubernetes_job_v1.configure_oke_for_blueprint_deployment_job]
}

resource "local_sensitive_file" "kubeconfig_patch" {
  count    = var.starter_pack_category == "enterprise_rag" ? 1 : 0
  content  = data.oci_containerengine_cluster_kube_config.oke.content
  filename = "${path.module}/kubeconfig_patch"
}

resource "terraform_data" "patch_nim_llm_service_selector" {
  count = var.starter_pack_category == "enterprise_rag" ? 1 : 0

  triggers_replace = [
    local.cluster_id,
    "patch_nim_llm_service_selector_v1"
  ]

  depends_on = [
    helm_release.rag,
    local_sensitive_file.kubeconfig_patch
  ]

  provisioner "local-exec" {
    command = "export KUBECONFIG=${local_sensitive_file.kubeconfig_patch[0].filename} && kubectl patch service nim-llm -n ${local.starter_pack_config.app_namespace} --type=merge -p '{\"spec\":{\"selector\":{\"statefulset.kubernetes.io/pod-name\":\"rag-nim-llm-0\"}}}'"
  }
}
