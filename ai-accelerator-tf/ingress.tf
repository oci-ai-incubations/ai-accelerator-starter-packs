## Gateway API Gateway
# Create a Gateway resource that replaces the ingress controller concept
# 
# This Gateway uses Envoy Gateway as the implementation, which supports:
# - Standard Gateway API features (HTTP routing, TLS termination, etc.)
# - Future: Gateway API Inference Extension for AI/LLM workloads
#   See: https://kubernetes.io/blog/2025/06/05/introducing-gateway-api-inference-extension/
#   The Inference Extension adds InferencePool and InferenceModel CRDs for
#   model-aware routing and optimized load balancing for AI workloads.
#
# Note: cert-manager Gateway shim will automatically create Certificate resources
# for hostnames defined in HTTPRoutes when they have cert-manager annotations
resource "kubernetes_manifest" "main_gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "main-gateway"
      namespace = kubernetes_namespace_v1.cluster_tools.id
      annotations = var.ingress_tls ? {
        "cert-manager.io/cluster-issuer" = var.ingress_cluster_issuer
      } : {}
    }
    spec = {
      gatewayClassName = "envoy"
      listeners = [
        {
          name     = "http"
          port     = 80
          protocol = "HTTP"
          hostname = "*"
          # Redirect HTTP to HTTPS if TLS is enabled
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "https"
          port     = 443
          protocol = "HTTPS"
          hostname = "*"
          tls = {
            mode = "Terminate"
            # Certificates will be managed per HTTPRoute via cert-manager
            # For Gateway API, cert-manager creates certificates automatically
            # when HTTPRoutes have the cert-manager annotations
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        }
      ]
    }
  }

  depends_on = [
    helm_release.envoy_gateway,
    helm_release.cert_manager
  ]
}

## Grafana HTTPRoute
resource "kubernetes_manifest" "grafana_httproute" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "grafana-httproute"
      namespace = kubernetes_namespace_v1.cluster_tools.id
      annotations = var.ingress_tls ? {
        "cert-manager.io/cluster-issuer" = var.ingress_cluster_issuer
      } : {}
    }
    spec = {
      parentRefs = [
        {
          name      = "main-gateway"
          namespace = kubernetes_namespace_v1.cluster_tools.id
          sectionName = "https"
        }
      ]
      hostnames = [local.public_endpoint.grafana]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              name = "grafana"
              port = 80
            }
          ]
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.main_gateway,
    helm_release.grafana
  ]
}

## Prometheus HTTPRoute
resource "kubernetes_manifest" "prometheus_httproute" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "prometheus-httproute"
      namespace = kubernetes_namespace_v1.cluster_tools.id
      annotations = var.ingress_tls ? {
        "cert-manager.io/cluster-issuer" = var.ingress_cluster_issuer
      } : {}
    }
    spec = {
      parentRefs = [
        {
          name      = "main-gateway"
          namespace = kubernetes_namespace_v1.cluster_tools.id
          sectionName = "https"
        }
      ]
      hostnames = [local.public_endpoint.prometheus]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              name = "prometheus-server"
              port = 80
            }
          ]
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.main_gateway,
    helm_release.prometheus
  ]
}

## Corrino CP HTTPRoute
resource "kubernetes_manifest" "corrino_cp_httproute" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name = "corrino-cp-httproute"
      annotations = var.ingress_tls ? {
        "cert-manager.io/cluster-issuer" = var.ingress_cluster_issuer
      } : {}
    }
    spec = {
      parentRefs = [
        {
          name      = "main-gateway"
          namespace = kubernetes_namespace_v1.cluster_tools.id
          sectionName = "https"
        }
      ]
      hostnames = [local.public_endpoint.api]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              name = kubernetes_service_v1.corrino_cp_service.metadata[0].name
              port = 80
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.main_gateway]
  count      = var.ingress_envoy_gateway_enabled ? 1 : 0
}

## OCI AI Blueprints Portal HTTPRoute
resource "kubernetes_manifest" "oci_ai_blueprints_portal_httproute" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name = "oci-ai-blueprints-portal-httproute"
      annotations = var.ingress_tls ? {
        "cert-manager.io/cluster-issuer" = var.ingress_cluster_issuer
      } : {}
    }
    spec = {
      parentRefs = [
        {
          name      = "main-gateway"
          namespace = kubernetes_namespace_v1.cluster_tools.id
          sectionName = "https"
        }
      ]
      hostnames = [local.public_endpoint.blueprint_portal]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              name = kubernetes_service_v1.oci_ai_blueprints_portal_service.metadata[0].name
              port = 80
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.main_gateway]
  count      = var.ingress_envoy_gateway_enabled ? 1 : 0
}

## Data source for Gateway service
data "kubernetes_service_v1" "gateway" {
  metadata {
    name      = "envoy-gateway"
    namespace = "envoy-gateway-system"
  }
  depends_on = [helm_release.envoy_gateway]
}

locals {
  gateway_load_balancer_ip     = try(data.kubernetes_service_v1.gateway.status[0].load_balancer[0].ingress[0].ip, "")
  gateway_load_balancer_ip_hex = join("", formatlist("%02x", split(".", local.gateway_load_balancer_ip)))
  gateway_load_balancer_hostname = (
  var.ingress_hosts != "" ? local.ingress_hosts[0] : (var.ingress_hosts_include_nip_io ? local.app_nip_io_domain : local.gateway_load_balancer_ip))

  ingress_hosts     = compact(concat(split(",", var.ingress_hosts), [local.app_nip_io_domain]))
  app_name_for_dns  = substr(lower(replace(local.app_name, "/\\W|_|\\s/", "")), 0, 6)
  app_nip_io_domain = (var.ingress_envoy_gateway_enabled && var.ingress_hosts_include_nip_io) ? format("${local.app_name_for_dns}.%s.${var.nip_io_domain}", local.gateway_load_balancer_ip_hex) : ""

}