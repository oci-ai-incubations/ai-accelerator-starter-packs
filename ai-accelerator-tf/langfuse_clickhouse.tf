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
  langfuse_clickhouse_cluster_enabled = local.agent_obs_size.ch_replicas > 1 ? "true" : "false"

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
              shardsCount: ${local.agent_obs_size.ch_shards}
              replicasCount: ${local.agent_obs_size.ch_replicas}
      templates:
        podTemplates:
          - name: clickhouse-pod
            spec:
              containers:
                - name: clickhouse
                  image: clickhouse/clickhouse-server:24.3
                  resources:
                    requests:
                      cpu: "1"
                      memory: 4Gi
                    limits:
                      memory: 8Gi
        volumeClaimTemplates:
          - name: data-volume
            spec:
              storageClassName: oci-bv
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 100Gi
  YAML

  # ClickHouseKeeperInstallation manifest (coordination for replication).
  langfuse_chk_manifest = <<-YAML
    apiVersion: "clickhouse-keeper.altinity.com/v1"
    kind: "ClickHouseKeeperInstallation"
    metadata:
      name: langfuse
      namespace: ${local.langfuse_ch_namespace}
    spec:
      configuration:
        clusters:
          - name: keeper
            layout:
              replicasCount: ${local.agent_obs_size.ch_replicas > 1 ? 3 : 1}
      templates:
        volumeClaimTemplates:
          - name: data-volume
            spec:
              storageClassName: oci-bv
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 10Gi
        podTemplates:
          - name: default
            spec:
              containers:
                - name: clickhouse-keeper
                  image: clickhouse/clickhouse-keeper:24.3-alpine
  YAML
}

resource "kubernetes_namespace_v1" "clickhouse" {
  count = local.deploy_app_agent_obs ? 1 : 0
  metadata {
    name = local.langfuse_ch_namespace
  }
}

# Altinity clickhouse-operator (cluster-scoped; watches all namespaces).
resource "helm_release" "clickhouse_operator" {
  count            = local.deploy_app_agent_obs ? 1 : 0
  name             = "clickhouse-operator"
  namespace        = "clickhouse-operator"
  create_namespace = true

  repository = "https://docs.altinity.com/clickhouse-operator/"
  chart      = "altinity-clickhouse-operator"
  version    = "0.24.5"

  timeout         = 600
  cleanup_on_fail = true
  wait            = true

  depends_on = [oci_containerengine_node_pool.oke_node_pool]
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
          image   = "docker.io/bitnami/kubectl:1.30"
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
