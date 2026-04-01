# Error Catalog

Known error patterns for AI Accelerator ORM stack deployments. Each entry maps a log pattern to its root cause and recommended fix.

This catalog is extensible — add new patterns as they are discovered.

---

## Helm Lifecycle Errors

| Pattern | Root Cause | Recommended Fix |
|---------|-----------|-----------------|
| `cannot re-use a name that is still in use` | A previous Terraform apply left an orphaned Helm release (failed or still installed). Terraform tries to `helm install` but the release name already exists. | `helm uninstall <release-name> -n <namespace>` then re-run ORM apply. Check `helm list -A --all` for releases in `failed` or `deployed` state. |
| `context deadline exceeded` | Helm timed out waiting for the release to become ready. Usually means pods did not reach Running state within the timeout window. | Check pod status: `kubectl get pods -n <namespace>`. Look at pod events: `kubectl describe pod <pod> -n <namespace>`. Common sub-causes: image pull failures, scheduling failures, crashloops. |
| `installation failed` | Helm install completed but reported failure. The release may be in `failed` state. | Check `helm status <release> -n <namespace>` and pod logs. If the release is in `failed` state, `helm uninstall` it before retrying. |
| `upgrade failed: another operation .* is in progress` | A previous Helm operation was interrupted (e.g., ORM job cancelled mid-apply). The release is stuck in `pending-install` or `pending-upgrade`. | `helm rollback <release> 0 -n <namespace>` or `helm uninstall <release> -n <namespace>` if rollback fails. |
| `timed out waiting for the condition` | Helm `wait` flag timed out. Pods or jobs did not reach ready/complete state. | Same as `context deadline exceeded` — investigate pod-level failures. |

---

## OCI / Terraform Errors

| Pattern | Root Cause | Recommended Fix |
|---------|-----------|-----------------|
| `Private Endpoint Subnet Ocids cannot be null` | ADB resource missing `subnet_id` or the subnet OCID variable is empty. The ADB requires a private endpoint subnet when `is_mtls_connection_required = false`. | Verify `db_subnet_id` is set. If creating new networking, check that the DB subnet resource is being created (count > 0). |
| `400-InvalidParameter` | An OCI API parameter has an invalid value. The error message usually names the specific parameter. | Read the full error message — it names the offending parameter. Check the corresponding Terraform variable/resource attribute. |
| `404-NotAuthorizedOrNotFound` | Either the resource does not exist, or the IAM principal lacks permissions to access it. OCI returns the same error code for both cases. | Check IAM policies for the user/dynamic-group. Verify resource OCIDs are correct. Common: missing `manage` verb on the resource type, or compartment mismatch. |
| `429-TooManyRequests` | OCI API rate limit exceeded. Common during large applies with many resources. | Retry the ORM job. If persistent, add `depends_on` to serialize resource creation or reduce parallelism. |
| `500-InternalError` | OCI service-side error. | Retry the job. If persistent, check OCI service health dashboard and file a support ticket. |
| `One-way TLS connections require a private endpoint` | ADB has `is_mtls_connection_required = false` but no `private_endpoint_label`. OCI requires either a private endpoint, a VCN ACL, or a public IP ACL for one-way TLS. | Add `private_endpoint_label` to the ADB resource. See BUG-005 in BUGS.md. |
| `Error: Failed to parse value for host: https://` | Kubernetes/Helm provider received an empty cluster endpoint. Happens in existing-cluster mode when the endpoint locals don't fall back to the kubeconfig server URL. | Check that `existing_cluster_id` is valid and the cluster has a public endpoint. See BUG-003 in BUGS.md. |
| `secrets ".*" already exists` | A Kubernetes secret already exists on the cluster and Terraform is trying to create (not import) it. Common on existing-cluster deployments. | Re-run apply — Terraform will adopt the resource into state. Or delete the secret manually first: `kubectl delete secret <name> -n <namespace>`. See BUG-004 in BUGS.md. |
| `random_id.blueprint_deploy_id is empty tuple` | Blueprint deploy ID accessed for a category that doesn't create blueprints (enterprise_rag, enterprise_rag_aiq). Count condition mismatch. | Check the `contains()` gate in vars.tf — both enterprise_rag and enterprise_rag_aiq must be excluded. See BUG-002 in BUGS.md. |

---

## Kubernetes Scheduling Errors

| Pattern | Root Cause | Recommended Fix |
|---------|-----------|-----------------|
| `FailedScheduling: Insufficient cpu` or `Insufficient memory` | The cluster does not have enough allocatable CPU or memory for the pod's resource requests. | Check node capacity: `kubectl describe nodes \| grep -A5 "Allocated resources"`. Scale the node pool or reduce pod resource requests. |
| `FailedScheduling: 0/N nodes are available: .* untolerated taint` | Pod lacks a toleration for a taint on the target nodes. GPU nodes typically have `nvidia.com/gpu` taints. | Add the required toleration to the pod spec/Helm values. Check taints: `kubectl describe node <node> \| grep Taint`. |
| `FailedScheduling: 0/N nodes are available: .* node(s) didn't match Pod's node affinity/selector` | Pod has a nodeSelector or nodeAffinity that doesn't match any available node labels. | Check pod's nodeSelector and node labels. Common: wrong GPU shape label or availability domain. |
| `ImagePullBackOff` or `ErrImagePull` | Container image cannot be pulled. Either the image doesn't exist, the tag is wrong, or registry credentials are missing/invalid. | Check image name and tag. Verify imagePullSecrets exist: `kubectl get secret -n <namespace>`. Test pull manually: `docker pull <image>`. For OCI Registry: verify the customer secret key is valid and the dynamic group policy allows image pulls. |
| `CrashLoopBackOff` | Container starts but exits repeatedly. The application inside is crashing. | Check logs: `kubectl logs <pod> -n <namespace> --previous`. Common sub-causes: missing env vars, bad config, database connection failures, OOM kills. |
| `OOMKilled` | Container exceeded its memory limit and was killed by the kernel. | Increase the memory limit in the pod spec or Helm values. Check if the application has a memory leak. |
| `CreateContainerConfigError` | A referenced ConfigMap or Secret does not exist. | Check the pod's `envFrom` and `volumeMounts` references. Verify the ConfigMap/Secret exists: `kubectl get configmap,secret -n <namespace>`. |

---

## PVC / Storage Errors

| Pattern | Root Cause | Recommended Fix |
|---------|-----------|-----------------|
| `PVC Pending` with `WaitForFirstConsumer` | The PVC uses a StorageClass with `volumeBindingMode: WaitForFirstConsumer`. The PVC will remain Pending until a pod that uses it is scheduled. | This is normal behavior — fix the pod scheduling issue first. The PVC will bind automatically once the pod is scheduled to a node. |
| `PVC Pending` with `ProvisioningFailed` | The CSI driver failed to create the backing volume. Common causes: quota exceeded, wrong availability domain, missing IAM policy for block volumes. | Check events: `kubectl describe pvc <name> -n <namespace>`. Verify the OKE dynamic group has `manage volumes` and `manage volume-attachments` policies. |
| `mount failed: mount.nfs: access denied` | NFS mount target security list does not allow traffic from the worker subnet, or export set permissions are wrong. | Check mount target security list allows TCP 2048-2050, UDP 2048, and TCP 111 from the worker subnet CIDR. Verify NFS export options. |

---

## Corrino / Blueprint Errors

| Pattern | Root Cause | Recommended Fix |
|---------|-----------|-----------------|
| `deployment_name .* already exists` | A blueprint with this deployment name was already submitted to Corrino. Deployments are immutable — cannot reuse names. | Undeploy the existing deployment via Corrino API first, then retry. Or change the `deployment_name` to a unique value. |
| `Connection refused` on Corrino API | The Corrino control plane pods are not running or not ready. The Kubernetes job that submits blueprints cannot reach the API. | Check Corrino pods: `kubectl get pods -n corrino-cp`. Wait for them to become Ready, or investigate why they are failing. |
| `blueprint validation failed` | The submitted blueprint JSON does not conform to the Corrino schema. | Check the error detail for the specific validation failure. Compare the blueprint payload against `~/code/corrino/api/json_schema/combined_schema.json`. |

---

## Network / Connectivity Errors

| Pattern | Root Cause | Recommended Fix |
|---------|-----------|-----------------|
| `dial tcp: lookup .* no such host` | DNS resolution failed inside the cluster. The pod cannot resolve an external hostname. | Check CoreDNS pods: `kubectl get pods -n kube-system -l k8s-app=kube-dns`. Verify the VCN has a service gateway for OCI services and the route table has a rule for it. |
| `dial tcp .*:443: i/o timeout` | Outbound HTTPS traffic is blocked. The pod cannot reach an external service. | Check security lists/NSGs for the worker subnet — egress to 0.0.0.0/0 on TCP 443 must be allowed. Verify NAT gateway and route table. |
| `x509: certificate signed by unknown authority` | TLS certificate validation failed. The pod does not trust the CA that signed the server's certificate. | If using a private CA, mount the CA bundle into the pod. For OCI services, ensure the pod has up-to-date CA certificates. |
