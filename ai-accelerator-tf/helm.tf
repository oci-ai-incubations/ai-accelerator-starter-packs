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
        tenancyOCID: ${local.tenancy_ocid}
        defaultRegion: ${local.region}
        environment: "OCI Instance"
    - name: Oracle Cloud Infrastructure Logs
      type: oci-logs-datasource
      access: proxy
      disableDeletion: true
      editable: true
      jsonData:
        tenancyOCID: ${local.tenancy_ocid}
        defaultRegion: ${local.region}
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
