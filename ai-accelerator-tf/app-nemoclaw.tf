# =============================================================================
# NemoClaw — DinD Sandbox + Dashboard Ingress + Web Terminal
# =============================================================================
# Architecture:
#   1. NIM inference (self_hosted only): Deployed via Corrino blueprint (blueprint_files.tf)
#      - Service DNS: recipe-{deployment_name} within the cluster
#      - API providers (openai/anthropic) skip this entirely
#   2. DinD pod: Runs NemoClaw installer + OpenShell sandbox isolation
#      - For self_hosted: socat bridges the blueprint NIM service -> host.openshell.internal:8000
#      - For API providers: NemoClaw connects directly to cloud API (no socat)
#      - socat bridges the dashboard (18789) from DinD to the pod network
#   3. Dashboard service + ingress: Exposes NemoClaw UI at starter_pack_url
#   4. Web terminal (optional): ttyd exposes a browser terminal on port 7681
#
# NIM follows the same blueprint pattern as cuopt/vss.
# DinD must remain as kubernetes_pod_v1 because blueprints don't support
# privileged containers, init containers, or multi-container pods.

locals {
  # Corrino creates K8s services as recipe-{canonical_name}
  # For single deployments, canonical_name = deployment_name (sanitized)
  # Only relevant for self_hosted provider
  nemoclaw_nim_service_name = "recipe-${local.starter_pack_deployment_name}"

  # Provider-specific configuration
  nemoclaw_provider_env = var.nemoclaw_provider == "self_hosted" ? "custom" : var.nemoclaw_provider
  nemoclaw_endpoint_url = (
    var.nemoclaw_provider == "self_hosted" ? "http://host.openshell.internal:8000/v1" :
    var.nemoclaw_provider == "openai" ? "https://api.openai.com/v1" :
    "https://api.anthropic.com/v1"
  )
  # Model: always user-configurable via nemoclaw_model variable
  nemoclaw_model_id = var.nemoclaw_model
}

# =============================================================================
# NemoClaw DinD Pod
# =============================================================================
# Deployed directly via Kubernetes provider (not Corrino blueprints).
# Follows NVIDIA's official K8s DinD reference:
#   https://github.com/NVIDIA/NemoClaw/tree/main/k8s
#
# Architecture:
#   Single pod with Docker-in-Docker for OpenShell sandbox isolation.
#   OpenShell creates a nested k3s cluster inside DinD for sandboxing.
#   For self_hosted: socat proxy bridges K8s DNS to the nested environment
#   so the sandbox can reach the inference endpoint via host.openshell.internal.
#   For API providers: NemoClaw connects directly to cloud API endpoints.
#
#   InitContainer (init-docker-config): cgroup v2 daemon config
#   Container 1 (dind): Docker daemon -- privileged for sandbox isolation
#   Container 2 (workspace): Runs official NemoClaw installer + optional socat proxy

resource "kubernetes_pod_v1" "nemoclaw" {
  count = local.deploy_app_nemoclaw ? 1 : 0

  metadata {
    name      = "nemoclaw"
    namespace = local.starter_pack_config.app_namespace
    labels = {
      app = "nemoclaw"
    }
  }

  spec {
    service_account_name = kubernetes_service_account_v1.nemoclaw[0].metadata[0].name

    # GPU node scheduling only for self_hosted provider
    node_selector = var.nemoclaw_provider == "self_hosted" ? {
      "corrino/pool-shared-any" = "true"
    } : {}

    dynamic "toleration" {
      for_each = var.nemoclaw_provider == "self_hosted" ? [1] : []
      content {
        key      = "nvidia.com/gpu"
        operator = "Exists"
        effect   = "NoSchedule"
      }
    }

    # InitContainer: configure Docker daemon for cgroup v2
    init_container {
      name    = "init-docker-config"
      image   = "docker.io/busybox:latest"
      command = ["sh", "-c", "echo '{\"default-cgroupns-mode\":\"host\"}' > /etc/docker/daemon.json"]

      volume_mount {
        name       = "docker-config"
        mount_path = "/etc/docker"
      }

      resources {
        requests = {
          memory = "32Mi"
          cpu    = "50m"
        }
      }
    }

    # Docker daemon (DinD) -- privileged for OpenShell sandbox isolation
    container {
      name  = "dind"
      image = "docker.io/docker:24-dind"

      security_context {
        privileged = true
      }

      env {
        name  = "DOCKER_TLS_CERTDIR"
        value = ""
      }

      command = ["dockerd", "--host=unix:///var/run/docker.sock"]

      volume_mount {
        name       = "docker-storage"
        mount_path = "/var/lib/docker"
      }
      volume_mount {
        name       = "docker-socket"
        mount_path = "/var/run"
      }
      volume_mount {
        name       = "docker-config"
        mount_path = "/etc/docker"
      }

      resources {
        requests = {
          memory = "8Gi"
          cpu    = "2"
        }
      }
    }

    # Workspace -- installs NemoClaw, optionally runs socat proxy to NIM inference endpoint
    container {
      name  = "workspace"
      image = "docker.io/node:22"

      command = ["bash", "-c", <<-SCRIPT
        set -eo pipefail

        # Install packages
        echo "[1/7] Installing packages..."
        apt-get update -qq
        apt-get install -y -qq docker.io socat curl >/dev/null 2>&1

%{if var.nemoclaw_provider == "self_hosted"~}
        # Start socat proxy to NIM service (deployed via blueprint)
        echo "[2/7] Configuring inference endpoint (self-hosted NIM)..."
        socat TCP-LISTEN:8000,fork,reuseaddr TCP:$${NIM_SERVICE_NAME}.$${NEMOCLAW_NAMESPACE}.svc.cluster.local:8000 &
        echo "127.0.0.1 host.openshell.internal" >> /etc/hosts
        sleep 1

        # Wait for NIM to be ready (model loading can take 10-20 min)
        echo "[3/7] Waiting for NIM inference to be ready..."
        NIM_ENDPOINT="http://$${NIM_SERVICE_NAME}.$${NEMOCLAW_NAMESPACE}.svc.cluster.local:8000/v1/models"
        NIM_ATTEMPTS=0
        NIM_MAX=300  # 300 * 15s = 75 min (TRT-LLM engine build + GPU load can take 70+ min)
        while [ $NIM_ATTEMPTS -lt $NIM_MAX ]; do
          NIM_ATTEMPTS=$((NIM_ATTEMPTS + 1))
          if curl -sf "$NIM_ENDPOINT" >/dev/null 2>&1; then
            echo "NIM is ready (attempt $NIM_ATTEMPTS)"
            break
          fi
          echo "NIM not ready yet (attempt $NIM_ATTEMPTS/$NIM_MAX), retrying in 15s..."
          sleep 15
        done
        curl -sf "$NIM_ENDPOINT" >/dev/null 2>&1 || { echo "FATAL: NIM not ready after 75 minutes"; exit 1; }
%{else~}
        # API provider (${var.nemoclaw_provider}) -- no local NIM, connecting to cloud API
        echo "[2/7] Using ${var.nemoclaw_provider} cloud API -- no local inference setup needed"
        echo "[3/7] Skipping NIM wait (API provider)"
%{endif~}

        # Wait for Docker
        echo "[4/7] Waiting for Docker daemon..."
        for i in $(seq 1 30); do
          if docker info >/dev/null 2>&1; then break; fi
          sleep 2
        done
        docker info >/dev/null 2>&1 || { echo "Docker not ready"; exit 1; }
        echo "Docker ready"

        # Pre-install OpenShell CLI at a known-good version so the NemoClaw
        # installer's preflight skips the auto-upgrade to latest (which may
        # have regressions -- e.g. v0.0.33 ciao/networkInterfaces crash).
        echo "[5/7] Installing OpenShell CLI..."
        OPENSHELL_VERSION=0.0.32
        curl -fsSL "https://github.com/NVIDIA/OpenShell/releases/download/v$${OPENSHELL_VERSION}/openshell-x86_64-unknown-linux-musl.tar.gz" \
          -o /tmp/openshell.tar.gz
        tar -xzf /tmp/openshell.tar.gz -C /usr/local/bin/ openshell
        chmod +x /usr/local/bin/openshell
        rm /tmp/openshell.tar.gz
        echo "OpenShell v$${OPENSHELL_VERSION} installed"

        # Run official NemoClaw installer (pinned to stable version)
        # Tee output to a log file so we can extract the gateway token afterward
        echo "[6/7] Running NemoClaw installer..."
        export NEMOCLAW_INSTALL_TAG=v0.0.9
        curl -fsSL https://nvidia.com/nemoclaw.sh | bash 2>&1 | tee /tmp/nemoclaw-install.log

        # Expose OpenClaw dashboard on all interfaces for K8s service/ingress
        # The installer starts a forward on 127.0.0.1:18789 -- stop it and rebind to 0.0.0.0
        echo "[7/7] Exposing dashboard..."
        source /root/.bashrc
        openshell forward stop 18789 2>/dev/null || true
        sleep 1
        openshell forward start -d 0.0.0.0:18789 $${NEMOCLAW_SANDBOX_NAME}
        echo "Dashboard exposed on 0.0.0.0:18789"

        # Extract gateway token from installer output and write to K8s ConfigMap
        # The installer prints: http://127.0.0.1:18789/#token=<hex>
        DASHBOARD_TOKEN=$(grep -o 'token=[a-f0-9]*' /tmp/nemoclaw-install.log 2>/dev/null | head -1 | cut -d= -f2 || echo "")
        if [ -n "$DASHBOARD_TOKEN" ]; then
          SA_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null)
          NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null)
          KUBE_API="https://kubernetes.default.svc"
          curl -sk -X PATCH "$KUBE_API/api/v1/namespaces/$NAMESPACE/configmaps/nemoclaw-dashboard-token" \
            -H "Authorization: Bearer $SA_TOKEN" \
            -H "Content-Type: application/strategic-merge-patch+json" \
            -d "{\"data\":{\"token\":\"$DASHBOARD_TOKEN\"}}" >/dev/null 2>&1 \
            && echo "Dashboard token written to configmap" \
            || echo "Warning: Could not write token to configmap"
        else
          echo "Warning: Could not extract dashboard token from installer output"
        fi

        # Install ttyd for browser-based terminal access (if enabled)
        if [ "$${ENABLE_TERMINAL}" = "true" ]; then
          echo "Installing ttyd for web terminal..."
          curl -fsSL https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 -o /usr/local/bin/ttyd
          chmod +x /usr/local/bin/ttyd
          source /root/.bashrc
          ttyd -p 7681 -W bash &
          echo "Web terminal available on port 7681"
        fi

        # Watchdog: monitor openshell forward and restart if it dies.
        # The forward is an SSH tunnel into the Landlock-isolated sandbox --
        # it's the only path to port 18789, so we must keep it alive.
        echo "Onboard complete. Starting forward watchdog..."
        while true; do
          if ! openshell forward list 2>/dev/null | grep -q "running"; then
            echo "$(date): Forward dead, restarting..." >> /tmp/forward-watchdog.log
            openshell forward stop 18789 2>/dev/null || true
            sleep 1
            openshell forward start -d 0.0.0.0:18789 $${NEMOCLAW_SANDBOX_NAME} 2>&1 >> /tmp/forward-watchdog.log
          fi
          sleep 10
        done
      SCRIPT
      ]

      env {
        name  = "DOCKER_HOST"
        value = "unix:///var/run/docker.sock"
      }
      env {
        name  = "NIM_SERVICE_NAME"
        value = local.nemoclaw_nim_service_name
      }
      env {
        name  = "NEMOCLAW_NAMESPACE"
        value = local.starter_pack_config.app_namespace
      }
      env {
        name  = "NEMOCLAW_NON_INTERACTIVE"
        value = "1"
      }
      env {
        name  = "NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE"
        value = "1"
      }
      env {
        name  = "NEMOCLAW_DISABLE_DEVICE_AUTH"
        value = "1"
      }
      env {
        name  = "NEMOCLAW_PROVIDER"
        value = local.nemoclaw_provider_env
      }
      env {
        name  = "NEMOCLAW_ENDPOINT_URL"
        value = local.nemoclaw_endpoint_url
      }
      # Provider-specific API key env vars
      # NemoClaw installer expects: COMPATIBLE_API_KEY (self_hosted/custom),
      # OPENAI_API_KEY (openai), ANTHROPIC_API_KEY (anthropic)
      dynamic "env" {
        for_each = var.nemoclaw_provider == "self_hosted" ? [1] : []
        content {
          name = "COMPATIBLE_API_KEY"
          value_from {
            secret_key_ref {
              name = local.ngc_secrets.nvidia_api_key_secret_name
              key  = local.ngc_secrets.nvidia_api_key_secret_key
            }
          }
        }
      }
      dynamic "env" {
        for_each = var.nemoclaw_provider == "openai" ? [1] : []
        content {
          name  = "OPENAI_API_KEY"
          value = var.openai_api_key
        }
      }
      dynamic "env" {
        for_each = var.nemoclaw_provider == "anthropic" ? [1] : []
        content {
          name  = "ANTHROPIC_API_KEY"
          value = var.anthropic_api_key
        }
      }
      env {
        name  = "NEMOCLAW_MODEL"
        value = local.nemoclaw_model_id
      }
      env {
        name  = "NEMOCLAW_SANDBOX_NAME"
        value = var.nemoclaw_sandbox_name
      }
      env {
        name  = "NEMOCLAW_POLICY_TIER"
        value = var.nemoclaw_security_tier
      }
      env {
        name  = "CHAT_UI_URL"
        value = "https://${local.public_endpoint.starter_pack}"
      }
      env {
        name  = "ENABLE_TERMINAL"
        value = tostring(var.nemoclaw_enable_terminal)
      }

      volume_mount {
        name       = "docker-socket"
        mount_path = "/var/run"
      }
      volume_mount {
        name       = "docker-config"
        mount_path = "/etc/docker"
      }

      port {
        container_port = 18789
        name           = "dashboard"
      }
      port {
        container_port = 7681
        name           = "terminal"
      }

      resources {
        requests = {
          memory = "4Gi"
          cpu    = "2"
        }
      }
    }

    volume {
      name = "docker-storage"
      empty_dir {}
    }
    volume {
      name = "docker-socket"
      empty_dir {}
    }
    volume {
      name = "docker-config"
      empty_dir {}
    }

    restart_policy = "Never"
  }

  timeouts {
    create = var.nemoclaw_provider == "self_hosted" ? "90m" : "30m"
  }

  depends_on = [
    oci_containerengine_node_pool.oke_node_pool,
    kubernetes_job_v1.blueprint_deployment_job,
  ]
}

# =============================================================================
# NemoClaw Dashboard Service
# =============================================================================
resource "kubernetes_service_v1" "nemoclaw_dashboard" {
  count = local.deploy_app_nemoclaw ? 1 : 0

  metadata {
    name      = "nemoclaw-dashboard"
    namespace = local.starter_pack_config.app_namespace
    labels = {
      app = "nemoclaw"
    }
  }

  spec {
    selector = {
      app = "nemoclaw"
    }

    port {
      port        = 18789
      target_port = 18789
      protocol    = "TCP"
      name        = "dashboard"
    }

    type = "ClusterIP"
  }
}

# =============================================================================
# NemoClaw Dashboard Ingress
# =============================================================================
resource "kubernetes_ingress_v1" "nemoclaw_dashboard_ingress" {
  count = local.deploy_app_nemoclaw ? 1 : 0

  wait_for_load_balancer = true
  metadata {
    name      = "nemoclaw-dashboard-ingress"
    namespace = local.starter_pack_config.app_namespace
    annotations = {
      "cert-manager.io/cluster-issuer"                    = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target"        = "/"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "600"
      "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "600"
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [local.public_endpoint.starter_pack]
      secret_name = "nemoclaw-dashboard-tls"
    }
    rule {
      host = local.public_endpoint.starter_pack
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "nemoclaw-dashboard"
              port {
                number = 18789
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.ingress_nginx, kubernetes_pod_v1.nemoclaw]
}

# =============================================================================
# NemoClaw Web Terminal Service + Ingress (ttyd)
# =============================================================================
resource "kubernetes_service_v1" "nemoclaw_terminal" {
  count = local.deploy_app_nemoclaw && var.nemoclaw_enable_terminal ? 1 : 0

  metadata {
    name      = "nemoclaw-terminal"
    namespace = local.starter_pack_config.app_namespace
    labels = {
      app = "nemoclaw"
    }
  }

  spec {
    selector = {
      app = "nemoclaw"
    }

    port {
      port        = 7681
      target_port = 7681
      protocol    = "TCP"
      name        = "terminal"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "nemoclaw_terminal_ingress" {
  count = local.deploy_app_nemoclaw && var.nemoclaw_enable_terminal ? 1 : 0

  wait_for_load_balancer = true
  metadata {
    name      = "nemoclaw-terminal-ingress"
    namespace = local.starter_pack_config.app_namespace
    annotations = {
      "cert-manager.io/cluster-issuer"                    = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "3600"
      "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "600"
      "nginx.ingress.kubernetes.io/websocket-services"    = "nemoclaw-terminal"
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [local.public_endpoint.nemoclaw_terminal]
      secret_name = "nemoclaw-terminal-tls"
    }
    rule {
      host = local.public_endpoint.nemoclaw_terminal
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "nemoclaw-terminal"
              port {
                number = 7681
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.ingress_nginx, kubernetes_pod_v1.nemoclaw]
}

# =============================================================================
# NemoClaw Dashboard Token -- ConfigMap + RBAC
# =============================================================================
# The gateway token is generated at sandbox image build time (secrets.token_hex).
# The startup script extracts it and patches this ConfigMap so Terraform can
# output the full tokenized dashboard URL.

resource "kubernetes_config_map_v1" "nemoclaw_dashboard_token" {
  count = local.deploy_app_nemoclaw ? 1 : 0

  metadata {
    name      = "nemoclaw-dashboard-token"
    namespace = local.starter_pack_config.app_namespace
  }

  data = {
    token = ""
  }
}

resource "kubernetes_service_account_v1" "nemoclaw" {
  count = local.deploy_app_nemoclaw ? 1 : 0

  metadata {
    name      = "nemoclaw"
    namespace = local.starter_pack_config.app_namespace
  }
}

resource "kubernetes_role_v1" "nemoclaw_token_writer" {
  count = local.deploy_app_nemoclaw ? 1 : 0

  metadata {
    name      = "nemoclaw-token-writer"
    namespace = local.starter_pack_config.app_namespace
  }

  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["nemoclaw-dashboard-token"]
    verbs          = ["get", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "nemoclaw_token_writer" {
  count = local.deploy_app_nemoclaw ? 1 : 0

  metadata {
    name      = "nemoclaw-token-writer"
    namespace = local.starter_pack_config.app_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "nemoclaw-token-writer"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "nemoclaw"
    namespace = local.starter_pack_config.app_namespace
  }
}

# =============================================================================
# NemoClaw Dashboard Readiness -- wait for token
# =============================================================================
# The gateway token is generated asynchronously by the pod (~12 min after start).
# The pod extracts the token from the installer logs and patches the ConfigMap
# via the K8s API. We poll the ConfigMap via the Kubernetes Terraform provider
# using a local-exec that reads the ConfigMap directly -- this works in ORM
# (unlike curling the external dashboard URL which ORM can't reach).

resource "null_resource" "wait_for_nemoclaw_dashboard" {
  count = local.deploy_app_nemoclaw ? 1 : 0

  triggers = {
    pod_uid = kubernetes_pod_v1.nemoclaw[0].metadata[0].uid
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Waiting for NemoClaw dashboard to become ready..."
      DASHBOARD_URL="https://${local.public_endpoint.starter_pack}/health"
      MAX_ATTEMPTS=400  # 400 * 15s = 100 min
      ATTEMPT=0

      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT + 1))
        HTTP_CODE=$(curl -sk -o /dev/null -w "%%{http_code}" "$DASHBOARD_URL" 2>/dev/null || echo "000")

        if [ "$HTTP_CODE" = "200" ]; then
          echo "NemoClaw dashboard is ready (attempt $ATTEMPT)"
          echo "Waiting 30s for token to be written to ConfigMap..."
          sleep 30
          exit 0
        fi

        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS -- HTTP $HTTP_CODE, retrying in 15s..."
        sleep 15
      done

      echo "NemoClaw dashboard not ready after 100 minutes. Still waiting for the installer to complete."
    EOT
  }

  depends_on = [
    kubernetes_pod_v1.nemoclaw,
  ]
}

data "kubernetes_config_map_v1" "nemoclaw_dashboard_token" {
  count = local.deploy_app_nemoclaw ? 1 : 0

  metadata {
    name      = "nemoclaw-dashboard-token"
    namespace = local.starter_pack_config.app_namespace
  }

  depends_on = [null_resource.wait_for_nemoclaw_dashboard]
}

