# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Secret for llamastack configuration

resource "kubernetes_secret_v1" "llamastack_paas_config" {
  metadata {
    name      = "llamastack-paas-config"
    namespace = "default"
  }

  data = {
    "config.yaml" = file("${path.module}/files/llamastack_paas_config.yaml")
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "llamastack_inference_config" {
  metadata {
    name      = "llamastack-inference-config"
    namespace = "default"
  }

  data = {
    "config.yaml" = file("${path.module}/files/llamastack_inference_config.yaml")
  }

  type = "Opaque"
}
