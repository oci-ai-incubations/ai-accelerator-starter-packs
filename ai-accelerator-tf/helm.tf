## Ingress Nginx
resource "helm_release" "ingress_nginx" {
  name          = "ingress-nginx"
  repository    = "https://kubernetes.github.io/ingress-nginx"
  chart         = "ingress-nginx"
  version       = "4.13.3"
  namespace     = kubernetes_namespace.cluster_tools.id
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
  ], var.cluster_load_balancer_visibility == "Private" ? [
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-internal"
      value = "true"
      type  = "string"
    }
  ] : [])

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
}

## Cert Manager
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "1.19.1"
  namespace  = kubernetes_namespace.cluster_tools.id
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

}

## Prometheus
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = "27.42.2"
  namespace  = kubernetes_namespace.cluster_tools.id
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
    }
  ]
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "10.1.4"
  namespace  = kubernetes_namespace.cluster_tools.id
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
      url: http://prometheus-server.${kubernetes_namespace.cluster_tools.id}.svc.cluster.local
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

resource "kubernetes_config_map" "vllm_dashboard" {
  metadata {
    name      = "vllm-custom-dashboard"
    namespace = kubernetes_namespace.cluster_tools.id
    labels = {
      grafana_dashboard = "true"
    }
  }

  data = {
    "vllm-dashboard.json" = file("${path.module}/dashboards/vllm-dashboard.json")
  }
}

resource "kubernetes_persistent_volume_claim_v1" "grafana" {
  metadata {
    name      = "grafana-pvc"
    namespace = kubernetes_namespace.cluster_tools.id
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

  depends_on = [kubernetes_namespace.cluster_tools]
}

## Kubernetes Secret: Grafana Admin Password
data "kubernetes_secret" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.cluster_tools.id
  }
  depends_on = [helm_release.grafana]
}

locals {
  grafana_admin_password = data.kubernetes_secret.grafana.data.admin-password
}

output "grafana_admin_password" {
  value     = nonsensitive(local.grafana_admin_password)
}