## Grafana Ingress
resource "kubernetes_ingress_v1" "grafana_ingress" {
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
              name = kubernetes_service_v1.corrino_cp_service.metadata[0].name
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
  count      = var.ingress_nginx_enabled ? 1 : 0
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
              name = kubernetes_service_v1.oci_ai_blueprints_portal_service.metadata[0].name
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
  count      = var.ingress_nginx_enabled ? 1 : 0
}

## Enterprise RAG Frontend Ingress
## Only created when starter_pack_category is enterprise_rag
resource "kubernetes_ingress_v1" "enterprise_rag_frontend_ingress" {
  count = var.starter_pack_category == "enterprise_rag" ? 1 : 0

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
  depends_on = [helm_release.ingress_nginx, helm_release.rag, terraform_data.patch_nim_llm_service_selector]
}

## Data source for ingress controller service
data "kubernetes_service_v1" "ingress" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = kubernetes_namespace_v1.cluster_tools.id
  }
  depends_on = [helm_release.ingress_nginx]
}

locals {
  ingress_controller_load_balancer_ip     = try(data.kubernetes_service_v1.ingress.status[0].load_balancer[0].ingress[0].ip, "")
  ingress_controller_load_balancer_ip_hex = join("", formatlist("%02x", split(".", local.ingress_controller_load_balancer_ip)))
  ingress_controller_load_balancer_hostname = (
  var.ingress_hosts != "" ? local.ingress_hosts[0] : (var.ingress_hosts_include_nip_io ? local.app_nip_io_domain : local.ingress_controller_load_balancer_ip))

  ingress_nginx_annotations_basic = {
    "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
  }
  ingress_nginx_annotations_tls = {
    "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
  }
  ingress_nginx_annotations_cert_manager = {
    "cert-manager.io/cluster-issuer"      = "letsencrypt-prod"
    "cert-manager.io/acme-challenge-type" = "http01"
  }
  ingress_nginx_annotations = merge(local.ingress_nginx_annotations_basic,
    var.ingress_tls ? local.ingress_nginx_annotations_tls : {},
    var.ingress_tls ? local.ingress_nginx_annotations_cert_manager : {}
  )
  ingress_hosts     = compact(concat(split(",", var.ingress_hosts), [local.app_nip_io_domain]))
  app_name_for_dns  = substr(lower(replace(local.app_name, "/\\W|_|\\s/", "")), 0, 6)
  app_nip_io_domain = (var.ingress_nginx_enabled && var.ingress_hosts_include_nip_io) ? format("${local.app_name_for_dns}.%s.${var.nip_io_domain}", local.ingress_controller_load_balancer_ip_hex) : ""

}