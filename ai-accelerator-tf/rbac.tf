resource "kubernetes_cluster_role_v1" "corrino_cluster_role" {
  metadata {
    name = "corrino-rbac"
  }
  rule {
    api_groups = [""]
    resources  = ["*"]
    verbs      = ["*"]
  }

  count = local.create_infrastructure ? 1 : 0
}

resource "kubernetes_cluster_role_binding_v1" "corrino_cluster_role_binding" {
  metadata {
    name = "corrino-rbac"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "default"
  }
  role_ref {
    kind      = "ClusterRole"
    name      = "cluster-admin"
    api_group = "rbac.authorization.k8s.io"
  }

  count = local.create_infrastructure ? 1 : 0
}
