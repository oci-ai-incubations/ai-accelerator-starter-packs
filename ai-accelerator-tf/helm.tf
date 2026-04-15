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

## NVIDIA DCGM Exporter - Commented out temporarily due to chart not found
resource "helm_release" "nvidia-gpu-operator" {
  count            = local.deploy_application ? 1 : 0
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

# Reserve the first GPU node (sorted by name) exclusively for the nim-llm pod.
# The taint (workload=nim-llm:NoSchedule) prevents 1-GPU inference pods from
# scheduling there; nim-llm's nodeSelector + toleration ensure it lands on it.
resource "terraform_data" "label_nim_llm_node" {
  count = local.deploy_app_rag && !local.readiness_via_operator ? 1 : 0

  input = {
    kubeconfig = local_sensitive_file.kubeconfig_patch[0].filename
  }

  triggers_replace = [
    local.cluster_id,
    "label_nim_llm_node_v2"
  ]

  depends_on = [
    oci_core_instance_pool.worker_nodes_pool,
    oci_core_cluster_network.worker_nodes_cluster_network,
    kubernetes_job_v1.configure_oke_for_blueprint_deployment_job,
    local_sensitive_file.kubeconfig_patch
  ]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${local_sensitive_file.kubeconfig_patch[0].filename}
      NODE=$(kubectl get nodes -l 'nvidia.com/gpu.present=true' --sort-by=.metadata.name -o jsonpath='{.items[0].metadata.name}')
      kubectl label node "$NODE" workload=nim-llm --overwrite
      kubectl taint node "$NODE" workload=nim-llm:NoSchedule --overwrite
    EOT
  }

  # Clean up taints on app stack destroy so the two-stack model starts with
  # clean node state for the next app deployment. (BUG-009)
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      export KUBECONFIG=${self.output.kubeconfig}
      echo "Cleaning up nim-llm taints from all GPU nodes..."
      for NODE in $(kubectl get nodes -l 'nvidia.com/gpu.present=true' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        kubectl taint node "$NODE" workload=nim-llm:NoSchedule- 2>/dev/null && echo "  Removed taint from $NODE" || true
        kubectl label node "$NODE" workload- 2>/dev/null || true
      done
      echo "Taint cleanup complete."
    EOT
  }
}

resource "terraform_data" "label_nim_llm_node_via_operator" {
  count = local.deploy_app_rag && local.readiness_via_operator ? 1 : 0

  input = {
    operator_ip     = oci_core_instance.operator[0].private_ip
    bastion_ip      = oci_core_instance.bastion[0].public_ip
    ssh_private_key = tls_private_key.oke_ssh_key[0].private_key_pem
  }

  triggers_replace = [
    local.cluster_id,
    "label_nim_llm_node_v2"
  ]

  # No resource-level connection block — Terraform validates it against destroy
  # provisioner rules when any destroy provisioner exists on the resource.
  # Both provisioners define their own connection instead.

  provisioner "remote-exec" {
    connection {
      type                = "ssh"
      user                = "opc"
      host                = self.output.operator_ip
      private_key         = self.output.ssh_private_key
      bastion_host        = self.output.bastion_ip
      bastion_user        = "opc"
      bastion_private_key = self.output.ssh_private_key
      timeout             = "30m"
    }
    inline = [
      "NODE=$(kubectl get nodes -l 'nvidia.com/gpu.present=true' --sort-by=.metadata.name -o jsonpath='{.items[0].metadata.name}')",
      "kubectl label node \"$NODE\" workload=nim-llm --overwrite",
      "kubectl taint node \"$NODE\" workload=nim-llm:NoSchedule --overwrite"
    ]
  }

  # Clean up taints on app stack destroy (BUG-009)
  provisioner "remote-exec" {
    when = destroy
    connection {
      type                = "ssh"
      user                = "opc"
      host                = self.output.operator_ip
      private_key         = self.output.ssh_private_key
      bastion_host        = self.output.bastion_ip
      bastion_user        = "opc"
      bastion_private_key = self.output.ssh_private_key
      timeout             = "30m"
    }
    inline = [
      "echo 'Cleaning up nim-llm taints from all GPU nodes...'",
      "for NODE in $(kubectl get nodes -l 'nvidia.com/gpu.present=true' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do kubectl taint node \"$NODE\" workload=nim-llm:NoSchedule- 2>/dev/null && echo \"  Removed taint from $NODE\" || true; kubectl label node \"$NODE\" workload- 2>/dev/null || true; done",
      "echo 'Taint cleanup complete.'"
    ]
  }

  depends_on = [
    null_resource.operator_ready,
    oci_core_instance_pool.worker_nodes_pool,
    oci_core_cluster_network.worker_nodes_cluster_network,
    kubernetes_job_v1.configure_oke_for_blueprint_deployment_job,
  ]
}

# Read the NGC API key created by configure_oke.py to authenticate with NGC helm registry
data "kubernetes_secret_v1" "ngc_api_secret" {
  metadata {
    name      = "ngc-api-secret"
    namespace = local.starter_pack_config.app_namespace
  }
  count      = local.deploy_app_rag ? 1 : 0
  depends_on = [kubernetes_job_v1.configure_oke_for_blueprint_deployment_job]
}

resource "helm_release" "rag" {
  name             = "rag"
  namespace        = local.starter_pack_config.app_namespace
  create_namespace = true

  chart = "https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz"

  repository_username = "$oauthtoken"
  repository_password = data.kubernetes_secret_v1.ngc_api_secret[0].data["NGC_API_KEY"]

  timeout         = 5400 # Increase timeout to 90 minutes
  cleanup_on_fail = true

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
    # Oracle 26ai credentials are only needed for enterprise_rag (not enterprise_rag_aiq)
    var.starter_pack_category == "enterprise_rag" ? [
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
    ] : []
  )

  set = concat(
    [
      {
        name  = "global.ngcApiKey"
        value = data.kubernetes_secret_v1.ngc_api_secret[0].data["NGC_API_KEY"]
      },
      {
        name  = "nim-llm.image.repository"
        value = "nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5"
      },
      {
        name  = "nim-llm.image.tag"
        value = "1.14.0"
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
    # Oracle 26ai connection string is only needed for enterprise_rag (not enterprise_rag_aiq)
    var.starter_pack_category == "enterprise_rag" ? [
      {
        name  = "envVars.ORACLE_CS"
        value = local.oracle26ai_high_connection_string
      },
      {
        name  = "ingestor-server.envVars.ORACLE_CS"
        value = local.oracle26ai_high_connection_string
      }
    ] : []
  )
  count = local.deploy_app_rag ? 1 : 0
  depends_on = [
    oci_core_instance_pool.worker_nodes_pool, oci_core_cluster_network.worker_nodes_cluster_network, kubernetes_job_v1.configure_oke_for_blueprint_deployment_job,
    oci_database_autonomous_database.oracle_26ai, kubernetes_secret_v1.oci_config_secret, terraform_data.label_nim_llm_node, terraform_data.label_nim_llm_node_via_operator
  ]
}

resource "local_sensitive_file" "kubeconfig_patch" {
  count    = local.deploy_app_rag ? 1 : 0
  content  = data.oci_containerengine_cluster_kube_config.oke.content
  filename = "${path.module}/kubeconfig_patch"
}

resource "terraform_data" "patch_nim_llm_service_selector" {
  count = local.deploy_app_rag && !local.readiness_via_operator ? 1 : 0

  triggers_replace = [
    local.cluster_id,
    "patch_nim_llm_service_selector_v1"
  ]

  depends_on = [
    helm_release.rag,
    local_sensitive_file.kubeconfig_patch,
    kubernetes_secret_v1.oci_config_secret,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${local_sensitive_file.kubeconfig_patch[0].filename}
      kubectl patch service nim-llm -n ${local.starter_pack_config.app_namespace} --type=merge -p '{"spec":{"selector":{"statefulset.kubernetes.io/pod-name":"rag-nim-llm-0","app.kubernetes.io/name":null}}}'
    EOT
  }
}

resource "terraform_data" "patch_nim_llm_service_selector_via_operator" {
  count = local.deploy_app_rag && local.readiness_via_operator ? 1 : 0

  triggers_replace = [
    local.cluster_id,
    "patch_nim_llm_service_selector_v1"
  ]

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
      "kubectl patch service nim-llm -n ${local.starter_pack_config.app_namespace} --type=merge -p '{\"spec\":{\"selector\":{\"statefulset.kubernetes.io/pod-name\":\"rag-nim-llm-0\",\"app.kubernetes.io/name\":null}}}'"
    ]
  }

  depends_on = [
    null_resource.operator_ready,
    helm_release.rag,
    kubernetes_secret_v1.oci_config_secret,
  ]
}


resource "helm_release" "aiq" {
  name             = "aiq-aira"
  namespace        = coalesce(local.starter_pack_config.aiq_namespace, "aiq")
  create_namespace = true

  chart = "https://helm.ngc.nvidia.com/nvidia/blueprint/charts/aiq-aira-v1.2.1.tgz"

  repository_username = "$oauthtoken"
  repository_password = data.kubernetes_secret_v1.ngc_api_secret[0].data["NGC_API_KEY"]

  timeout         = 3600
  cleanup_on_fail = true

  values = [
    file("${path.module}/helm-values/aiq-aira-values.yaml")
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
    var.tavily_api_key != "" ? [
      {
        name  = "tavilyApiSecret.password"
        value = var.tavily_api_key
      }
    ] : []
  )
  set = [
    {
      name  = "backendEnvVars.RAG_SERVER_URL"
      value = "http://rag-server.${local.starter_pack_config.app_namespace}.svc.cluster.local:8081"
    },
    {
      name  = "backendEnvVars.RAG_INGEST_URL"
      value = "http://ingestor-server.${local.starter_pack_config.app_namespace}.svc.cluster.local:8082"
    },
    {
      name  = "backendEnvVars.NEMOTRON_BASE_URL"
      value = "http://nim-llm.${local.starter_pack_config.app_namespace}.svc.cluster.local:8000"
    }
  ]

  count = local.deploy_app_rag_aiq ? 1 : 0

  # The aiq stack depends on the rag stack deployment to complete and
  # the AIQ namespace secrets to be created by configure_oke.
  depends_on = [
    helm_release.rag,
    terraform_data.patch_nim_llm_service_selector,
    terraform_data.patch_nim_llm_service_selector_via_operator,
    kubernetes_job_v1.configure_oke_for_aiq_namespace,
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
