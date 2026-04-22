## Grafana Ingress
resource "kubernetes_ingress_v1" "grafana_ingress" {
  count                  = local.deploy_application ? 1 : 0
  wait_for_load_balancer = true
  metadata {
    name      = "grafana-ingress"
    namespace = "cluster-tools"
    annotations = {
      "cert-manager.io/cluster-issuer"             = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [local.public_endpoint.grafana]
      secret_name = "grafana-tls"
    }
    rule {
      host = local.public_endpoint.grafana
      http {
        path {
          path = "/"
          backend {
            service {
              name = "grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.ingress_nginx, helm_release.grafana]
}

resource "kubernetes_ingress_v1" "prometheus_ingress" {
  count                  = local.deploy_application ? 1 : 0
  wait_for_load_balancer = true
  metadata {
    name      = "prometheus-ingress"
    namespace = "cluster-tools"
    annotations = {
      "cert-manager.io/cluster-issuer"             = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [local.public_endpoint.prometheus]
      secret_name = "prometheus-tls"
    }
    rule {
      host = local.public_endpoint.prometheus
      http {
        path {
          path = "/"
          backend {
            service {
              name = "prometheus-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.ingress_nginx, helm_release.prometheus]
}

resource "kubernetes_ingress_v1" "corrino_cp_ingress" {
  wait_for_load_balancer = true
  metadata {
    name = "corrino-cp-ingress"
    annotations = {
      "cert-manager.io/cluster-issuer"             = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [local.public_endpoint.api]
      secret_name = "corrino-cp-tls"
    }
    rule {
      host = local.public_endpoint.api
      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service_v1.corrino_cp_service[0].metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.ingress_nginx]
  count      = local.deploy_application && var.ingress_nginx_enabled ? 1 : 0
}

resource "kubernetes_ingress_v1" "oci_ai_blueprints_portal_ingress" {
  wait_for_load_balancer = true
  metadata {
    name = "oci-ai-blueprints-portal-ingress"
    annotations = {
      "cert-manager.io/cluster-issuer"             = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [local.public_endpoint.blueprint_portal]
      secret_name = "oci-ai-blueprints-portal-tls"
    }
    rule {
      host = local.public_endpoint.blueprint_portal
      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service_v1.oci_ai_blueprints_portal_service[0].metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.ingress_nginx]
  count      = local.deploy_application && var.ingress_nginx_enabled ? 1 : 0
}

## Enterprise RAG Frontend Ingress
## Only created when starter_pack_category is enterprise_rag
resource "kubernetes_ingress_v1" "enterprise_rag_frontend_ingress" {
  count = local.deploy_application && var.starter_pack_category == "enterprise_rag" ? 1 : 0

  wait_for_load_balancer = true
  metadata {
    name      = "enterprise-rag-frontend-ingress"
    namespace = local.starter_pack_config.app_namespace
    annotations = {
      "cert-manager.io/cluster-issuer"                    = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target"        = "/"
      "nginx.ingress.kubernetes.io/proxy-body-size"       = "2g"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "600"
      "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "600"
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [local.public_endpoint.starter_pack]
      secret_name = "enterprise-rag-frontend-tls"
    }
    rule {
      host = local.public_endpoint.starter_pack
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "rag-frontend"
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.ingress_nginx, helm_release.rag, terraform_data.patch_nim_operator_resources]
}

resource "kubernetes_ingress_v1" "enterprise_rag_aiq_frontend_ingress" {
  count = local.deploy_app_rag_aiq ? 1 : 0

  wait_for_load_balancer = true
  metadata {
    name      = "aiq-frontend-ingress"
    namespace = coalesce(local.starter_pack_config.aiq_namespace, "aiq")
    annotations = {
      "cert-manager.io/cluster-issuer"                    = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target"        = "/"
      "nginx.ingress.kubernetes.io/proxy-body-size"       = "2g"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "600"
      "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "600"
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [local.public_endpoint.starter_pack]
      secret_name = "aiq-frontend-tls"
    }
    rule {
      host = local.public_endpoint.starter_pack
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "aiq-aira-aira-frontend"
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.ingress_nginx, helm_release.aiq]
}

## Data source for ingress controller service
data "kubernetes_service_v1" "ingress" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name      = "ingress-nginx-controller"
    namespace = kubernetes_namespace_v1.cluster_tools[0].id
  }
  depends_on = [helm_release.ingress_nginx]
}

locals {
  ingress_controller_load_balancer_ip = local.deploy_application ? try(data.kubernetes_service_v1.ingress[0].status[0].load_balancer[0].ingress[0].ip, "") : ""
}
