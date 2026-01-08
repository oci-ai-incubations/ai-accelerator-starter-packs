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
#
# Using kubectl apply via null_resource instead of kubernetes_manifest to avoid
# Terraform provider configuration issues (see: https://medium.com/@danieljimgarcia/dont-use-the-terraform-kubernetes-manifest-resource-6c7ff4fe629a)
resource "local_file" "main_gateway_yaml" {
  content = yamlencode({
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
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        }
      ]
    }
  })
  filename = "${path.module}/.terraform/main-gateway.yaml"
}

resource "null_resource" "main_gateway" {
  triggers = {
    gateway_yaml = local_file.main_gateway_yaml.content
    cluster_id   = local.oke_cluster.id
    region       = var.region
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Configure kubectl with OCI
      oci ce cluster create-kubeconfig --cluster-id ${local.oke_cluster.id} --region ${var.region} --file $HOME/.kube/config --kubeconfig-token-version 2.0.0 2>/dev/null || true
      
      # Apply the Gateway resource
      kubectl apply -f ${local_file.main_gateway_yaml.filename}
    EOT
  }

  depends_on = [
    kubernetes_namespace_v1.cluster_tools,
    helm_release.envoy_gateway,
    helm_release.cert_manager,
    local_file.main_gateway_yaml
  ]
}

## Grafana HTTPRoute
# Using kubectl apply via null_resource instead of kubernetes_manifest
resource "local_file" "grafana_httproute_yaml" {
  content = yamlencode({
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
          name        = "main-gateway"
          namespace   = kubernetes_namespace_v1.cluster_tools.id
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
  })
  filename = "${path.module}/.terraform/grafana-httproute.yaml"
}

resource "null_resource" "grafana_httproute" {
  triggers = {
    httproute_yaml = local_file.grafana_httproute_yaml.content
    cluster_id     = local.oke_cluster.id
    region         = var.region
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Configure kubectl with OCI
      oci ce cluster create-kubeconfig --cluster-id ${local.oke_cluster.id} --region ${var.region} --file $HOME/.kube/config --kubeconfig-token-version 2.0.0 2>/dev/null || true
      
      # Apply the HTTPRoute resource
      kubectl apply -f ${local_file.grafana_httproute_yaml.filename}
    EOT
  }

  depends_on = [
    null_resource.main_gateway,
    helm_release.grafana,
    local_file.grafana_httproute_yaml
  ]
}

## Prometheus HTTPRoute
# Using kubectl apply via null_resource instead of kubernetes_manifest
resource "local_file" "prometheus_httproute_yaml" {
  content = yamlencode({
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
          name        = "main-gateway"
          namespace   = kubernetes_namespace_v1.cluster_tools.id
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
  })
  filename = "${path.module}/.terraform/prometheus-httproute.yaml"
}

resource "null_resource" "prometheus_httproute" {
  triggers = {
    httproute_yaml = local_file.prometheus_httproute_yaml.content
    cluster_id     = local.oke_cluster.id
    region         = var.region
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Configure kubectl with OCI
      oci ce cluster create-kubeconfig --cluster-id ${local.oke_cluster.id} --region ${var.region} --file $HOME/.kube/config --kubeconfig-token-version 2.0.0 2>/dev/null || true
      
      # Apply the HTTPRoute resource
      kubectl apply -f ${local_file.prometheus_httproute_yaml.filename}
    EOT
  }

  depends_on = [
    null_resource.main_gateway,
    helm_release.prometheus,
    local_file.prometheus_httproute_yaml
  ]
}

## Corrino CP HTTPRoute
# Using kubectl apply via null_resource instead of kubernetes_manifest
resource "local_file" "corrino_cp_httproute_yaml" {
  count = var.ingress_envoy_gateway_enabled ? 1 : 0

  content = yamlencode({
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
          name        = "main-gateway"
          namespace   = kubernetes_namespace_v1.cluster_tools.id
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
  })
  filename = "${path.module}/.terraform/corrino-cp-httproute.yaml"
}

resource "null_resource" "corrino_cp_httproute" {
  count = var.ingress_envoy_gateway_enabled ? 1 : 0

  triggers = {
    httproute_yaml = local_file.corrino_cp_httproute_yaml[0].content
    cluster_id     = local.oke_cluster.id
    region         = var.region
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Configure kubectl with OCI
      oci ce cluster create-kubeconfig --cluster-id ${local.oke_cluster.id} --region ${var.region} --file $HOME/.kube/config --kubeconfig-token-version 2.0.0 2>/dev/null || true
      
      # Apply the HTTPRoute resource
      kubectl apply -f ${local_file.corrino_cp_httproute_yaml[0].filename}
    EOT
  }

  depends_on = [
    null_resource.main_gateway,
    kubernetes_service_v1.corrino_cp_service,
    local_file.corrino_cp_httproute_yaml
  ]
}

## OCI AI Blueprints Portal HTTPRoute
# Using kubectl apply via null_resource instead of kubernetes_manifest
resource "local_file" "oci_ai_blueprints_portal_httproute_yaml" {
  count = var.ingress_envoy_gateway_enabled ? 1 : 0

  content = yamlencode({
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
          name        = "main-gateway"
          namespace   = kubernetes_namespace_v1.cluster_tools.id
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
  })
  filename = "${path.module}/.terraform/oci-ai-blueprints-portal-httproute.yaml"
}

resource "null_resource" "oci_ai_blueprints_portal_httproute" {
  count = var.ingress_envoy_gateway_enabled ? 1 : 0

  triggers = {
    httproute_yaml = local_file.oci_ai_blueprints_portal_httproute_yaml[0].content
    cluster_id     = local.oke_cluster.id
    region         = var.region
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Configure kubectl with OCI
      oci ce cluster create-kubeconfig --cluster-id ${local.oke_cluster.id} --region ${var.region} --file $HOME/.kube/config --kubeconfig-token-version 2.0.0 2>/dev/null || true
      
      # Apply the HTTPRoute resource
      kubectl apply -f ${local_file.oci_ai_blueprints_portal_httproute_yaml[0].filename}
    EOT
  }

  depends_on = [
    null_resource.main_gateway,
    kubernetes_service_v1.oci_ai_blueprints_portal_service,
    local_file.oci_ai_blueprints_portal_httproute_yaml
  ]
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
  gateway_load_balancer_ip = try(data.kubernetes_service_v1.gateway.status[0].load_balancer[0].ingress[0].ip, "")
  # Only compute hex if IP is not empty to avoid formatlist errors
  gateway_load_balancer_ip_hex = local.gateway_load_balancer_ip != "" ? join("", formatlist("%02x", [for octet in split(".", local.gateway_load_balancer_ip) : tonumber(octet)])) : ""
  gateway_load_balancer_hostname = (
  var.ingress_hosts != "" ? local.ingress_hosts[0] : (var.ingress_hosts_include_nip_io ? local.app_nip_io_domain : local.gateway_load_balancer_ip))

  ingress_hosts     = compact(concat(split(",", var.ingress_hosts), [local.app_nip_io_domain]))
  app_name_for_dns  = substr(lower(replace(local.app_name, "/\\W|_|\\s/", "")), 0, 6)
  app_nip_io_domain = (var.ingress_envoy_gateway_enabled && var.ingress_hosts_include_nip_io && local.gateway_load_balancer_ip != "") ? format("${local.app_name_for_dns}.%s.${var.nip_io_domain}", local.gateway_load_balancer_ip_hex) : ""

}