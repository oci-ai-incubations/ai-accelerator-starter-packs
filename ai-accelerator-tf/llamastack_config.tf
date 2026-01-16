# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Secret for llamastack configuration

resource "kubernetes_secret_v1" "llamastack_config" {
  metadata {
    name      = "llamastack-config"
    namespace = "default"
  }

  data = {
    "config.yaml" = filebase64("${path.module}/files/llamastack_config.yaml")
  }

  type = "Opaque"
}
