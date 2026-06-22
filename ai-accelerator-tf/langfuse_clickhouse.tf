# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# ClickHouse (OLAP store for Langfuse) deployed in-cluster via the Altinity
# clickhouse-operator. OCI has no managed ClickHouse, and Corrino blueprints
# cannot express StatefulSets, so the operator manages the ClickHouse
# StatefulSets/PVCs and gives a clear path to sharding + replication.
#
# CRs (ClickHouseInstallation / ClickHouseKeeperInstallation) are applied by a
# kubectl Job sourced from a ConfigMap rather than kubernetes_manifest, so there
# is no plan-time CRD dependency (ORM-safe).

locals {
  langfuse_ch_namespace               = "clickhouse"
  langfuse_ch_chi_name                = "langfuse"
  langfuse_clickhouse_user            = "langfuse"
  langfuse_clickhouse_host            = "clickhouse-${local.langfuse_ch_chi_name}.${local.langfuse_ch_namespace}.svc.cluster.local"
  langfuse_clickhouse_url             = "http://${local.langfuse_clickhouse_host}:8123"
  langfuse_clickhouse_migration_url   = "clickhouse://${local.langfuse_clickhouse_host}:9000"
  langfuse_clickhouse_cluster_enabled = local.agent_obs_size.ch_replica_count > 1 ? "true" : "false"

  # ClickHouse server/keeper images. Fully-qualified (docker.io/) because OKE
  # cri-o enforces short-name resolution. Pinned to 25.8 (not 24.8): the Altinity
  # operator 0.27.1 generates a Keeper config using the `use_xid_64` coordination
  # setting, which 24.8 rejects ("Unknown setting 'use_xid_64'") — 25.8 is the
  # operator-certified line and Langfuse supports >= 24.3.
  langfuse_ch_image        = "docker.io/clickhouse/clickhouse-server:25.8"
  langfuse_ch_keeper_image = "docker.io/clickhouse/clickhouse-keeper:25.8-alpine"

  # ClickHouse stores a SHA-256 hex of the password, never the plaintext.
  langfuse_ch_password_sha256 = local.deploy_app_agent_obs ? sha256(random_password.langfuse_clickhouse_password[0].result) : ""

  # ClickHouseInstallation manifest (rendered with sizing + password hash).
  langfuse_chi_manifest = <<-YAML
    apiVersion: "clickhouse.altinity.com/v1"
    kind: "ClickHouseInstallation"
    metadata:
      name: ${local.langfuse_ch_chi_name}
      namespace: ${local.langfuse_ch_namespace}
    spec:
      defaults:
        templates:
          # Pin the CHI root Service name + ports deterministically rather than
          # relying on the operator's default generateName. langfuse_clickhouse_host
          # below must match generateName ("clickhouse-{chi}" -> clickhouse-langfuse).
          serviceTemplate: chi-service
          dataVolumeClaimTemplate: data-volume
          podTemplate: clickhouse-pod
      configuration:
        zookeeper:
          nodes:
            - host: keeper-langfuse.${local.langfuse_ch_namespace}.svc.cluster.local
              port: 2181
        users:
          ${local.langfuse_clickhouse_user}/password_sha256_hex: ${local.langfuse_ch_password_sha256}
          ${local.langfuse_clickhouse_user}/networks/ip: "::/0"
          ${local.langfuse_clickhouse_user}/profile: default
          ${local.langfuse_clickhouse_user}/quota: default
          ${local.langfuse_clickhouse_user}/access_management: 1
        clusters:
          - name: default
            layout:
              # Langfuse supports single-shard only; HA comes from replicas.
              shardsCount: 1
              replicasCount: ${local.agent_obs_size.ch_replica_count}
      templates:
        serviceTemplates:
          - name: chi-service
            generateName: "clickhouse-{chi}"
            spec:
              type: ClusterIP
              ports:
                - name: http
                  port: 8123
                - name: client
                  port: 9000
        podTemplates:
          - name: clickhouse-pod
            spec:
              containers:
                - name: clickhouse
                  image: ${local.langfuse_ch_image}
                  resources:
                    requests:
                      cpu: "${local.agent_obs_size.ch_cpu_count}"
                      memory: ${local.agent_obs_size.ch_memory_request_gbs}Gi
                    limits:
                      memory: ${local.agent_obs_size.ch_memory_limit_gbs}Gi
        volumeClaimTemplates:
          - name: data-volume
            spec:
              storageClassName: oci-bv
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: ${local.agent_obs_size.ch_storage_gi}Gi
  YAML

  # ClickHouseKeeperInstallation manifest (coordination for replication).
  # The podTemplate/serviceTemplate MUST be referenced under defaults.templates,
  # otherwise the operator ignores them and falls back to its built-in keeper
  # image (clickhouse/clickhouse-keeper:latest, short-named → fails on cri-o).
  # The serviceTemplate pins the keeper service to "keeper-langfuse" (port 2181),
  # which the CHI's zookeeper.nodes host references.
  langfuse_chk_manifest = <<-YAML
    apiVersion: "clickhouse-keeper.altinity.com/v1"
    kind: "ClickHouseKeeperInstallation"
    metadata:
      name: ${local.langfuse_ch_chi_name}
      namespace: ${local.langfuse_ch_namespace}
    spec:
      defaults:
        templates:
          podTemplate: keeper-pod
          dataVolumeClaimTemplate: keeper-data
          serviceTemplate: keeper-service
      configuration:
        clusters:
          - name: keeper
            layout:
              replicasCount: ${local.agent_obs_size.ch_replica_count > 1 ? 3 : 1}
      templates:
        serviceTemplates:
          - name: keeper-service
            generateName: "keeper-{chk}"
            spec:
              type: ClusterIP
              ports:
                - name: client
                  port: 2181
        podTemplates:
          - name: keeper-pod
            spec:
              containers:
                - name: clickhouse-keeper
                  image: ${local.langfuse_ch_keeper_image}
        volumeClaimTemplates:
          - name: keeper-data
            spec:
              storageClassName: oci-bv
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 10Gi
  YAML
}

resource "kubernetes_namespace_v1" "clickhouse" {
  count = local.deploy_app_agent_obs ? 1 : 0
  metadata {
    name = local.langfuse_ch_namespace
  }
}

# Altinity clickhouse-operator. By default the operator watches ONLY its own
# namespace (it watches all namespaces only when running in kube-system). So it
# MUST run in the same namespace as the CHI/CHK (clickhouse) or it silently
# never reconciles them.
resource "helm_release" "clickhouse_operator" {
  count            = local.deploy_app_agent_obs ? 1 : 0
  name             = "clickhouse-operator"
  namespace        = local.langfuse_ch_namespace
  create_namespace = false

  repository = "https://helm.altinity.com"
  chart      = "altinity-clickhouse-operator"
  version    = "0.27.1"

  timeout         = 600
  cleanup_on_fail = true
  wait            = true

  # OKE worker nodes run cri-o with short-name enforcement, which rejects the
  # chart's default unqualified images. Fully qualify all three (CRD-install hook,
  # operator, metrics exporter). NOTE: bitnami/kubectl no longer publishes version
  # tags (Bitnami 2025 catalog change), so use alpine/kubectl for the CRD hook.
  set = [
    { name = "crdHook.image.repository", value = "docker.io/alpine/kubectl" },
    { name = "crdHook.image.tag", value = "1.35.4" },
    { name = "operator.image.registry", value = "docker.io" },
    { name = "metrics.image.registry", value = "docker.io" },
  ]

  depends_on = [
    oci_containerengine_node_pool.oke_node_pool,
    kubernetes_namespace_v1.clickhouse,
  ]
}

# RBAC for the kubectl Job that applies the ClickHouse CRs.
resource "kubernetes_service_account_v1" "clickhouse_applier" {
  count = local.deploy_app_agent_obs ? 1 : 0
  metadata {
    name      = "clickhouse-applier"
    namespace = local.langfuse_ch_namespace
  }
}

resource "kubernetes_cluster_role_v1" "clickhouse_applier" {
  count = local.deploy_app_agent_obs ? 1 : 0
  metadata {
    name = "clickhouse-applier"
  }
  rule {
    api_groups = ["clickhouse.altinity.com", "clickhouse-keeper.altinity.com"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources  = ["customresourcedefinitions"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "clickhouse_applier" {
  count = local.deploy_app_agent_obs ? 1 : 0
  metadata {
    name = "clickhouse-applier"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.clickhouse_applier[0].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.clickhouse_applier[0].metadata[0].name
    namespace = local.langfuse_ch_namespace
  }
}

resource "kubernetes_config_map_v1" "clickhouse_manifests" {
  count = local.deploy_app_agent_obs ? 1 : 0
  metadata {
    name      = "clickhouse-manifests"
    namespace = local.langfuse_ch_namespace
  }
  data = {
    "00-keeper.yaml" = local.langfuse_chk_manifest
    "01-chi.yaml"    = local.langfuse_chi_manifest
  }
}

resource "kubernetes_job_v1" "clickhouse_apply" {
  count = local.deploy_app_agent_obs ? 1 : 0
  metadata {
    name      = "clickhouse-apply"
    namespace = local.langfuse_ch_namespace
  }
  spec {
    backoff_limit = 6
    template {
      metadata {
        labels = { app = "clickhouse-apply" }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.clickhouse_applier[0].metadata[0].name
        restart_policy       = "OnFailure"
        container {
          name    = "kubectl"
          image   = "docker.io/alpine/kubectl:1.35.4"
          command = ["/bin/sh", "-c"]
          args    = ["kubectl apply -f /manifests/00-keeper.yaml && kubectl apply -f /manifests/01-chi.yaml"]
          volume_mount {
            name       = "manifests"
            mount_path = "/manifests"
          }
        }
        volume {
          name = "manifests"
          config_map {
            name = kubernetes_config_map_v1.clickhouse_manifests[0].metadata[0].name
          }
        }
      }
    }
  }
  wait_for_completion = false
  depends_on          = [helm_release.clickhouse_operator]
}
