# Only create registration file when deploying a Corrino blueprint (not for Helm-based deployments)
resource "local_file" "registration" {
  count    = local.starter_pack_config.blueprint_file != "" ? 1 : 0
  content  = local.registration.object_content
  filename = local.registration.object_filepath
}

# curl -X PUT --data-binary '@local_filename' unique_PAR_URL
# Only run registration when deploying a Corrino blueprint (not for Helm-based deployments like enterprise_rag_medium)
resource "null_resource" "registration" {
    count      = local.starter_pack_config.blueprint_file != "" ? 1 : 0
    depends_on = [kubernetes_deployment_v1.corrino_cp_deployment, local_file.registration]
    triggers   = {
        always_run = timestamp()
    }
    provisioner "local-exec" {
        command = <<-EOT
        if [ "${var.share_data_with_corrino_team_enabled}" = "true" ]; then
            curl -X PUT --data-binary '@${local.registration.object_filepath}' ${local.registration.upload_path}${local.registration.object_filename}
        else
            echo "1" > /tmp/opted_out && curl -X PUT --data-binary '@/tmp/opted_out' ${local.registration.upload_path}opted_out
        fi
	      EOT
    }
}
