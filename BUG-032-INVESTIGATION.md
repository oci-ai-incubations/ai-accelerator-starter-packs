# BUG-032 Investigation Doc — enterprise_rag/small APPLY FAILED, pack functionally works

**Status (as of 2026-05-06 02:58 UTC)**: live, ready for investigator. Cluster + both stacks preserved. Pack is serving model requests successfully despite the FAILED apply.

**TL;DR**: The Terraform apply for enterprise_rag/small fails at the `terraform_data.patch_nim_operator_resources` 30-min wait gate. The wait gate fails because nim-operator (k8s-nim-operator-3.1.0) spawns a *retry* cache-job pod that tries to mount an RWO PVC already attached to the live nim-llm Deployment pod — resulting in a `Multi-Attach error`, the retry pod gets stuck `ContainerCreating` forever, the NIMCache CR's `.status` never flips to Ready, and the wait gate times out. **The pack is functionally working** — `/v1/chat/completions` returns valid responses from the deployed model.

---

## 1. Bug Hypothesis

**Root cause**: PVC ReadWriteOnce + nim-operator retry-on-failure race.

### Sequence (verified)

1. nim-operator creates `Job/nim-llm-cache-job-vlqws` to download `nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b:1.8.0`.
2. The job pod mounts `pvc/nim-llm-cache-pvc` (RWO, 500Gi, oci-bv block volume), downloads the model, succeeds, gets reaped.
3. The `Deployment/nim-llm` pod (`nim-llm-599f644859-kqbhz`) mounts the same PVC, loads the model on 8× A100 40GB at FP8 quantization (38/40 GB VRAM utilization), reaches `1/1 Ready`, starts serving on port 8000.
4. The nim-operator reconciler decides to spawn a *retry* cache-job (`Job/nim-llm-cache-job-qn466` started 23:40:32Z) — possibly because it interpreted the original Job's reaping as failure.
5. The retry pod attempts to mount the same RWO PVC. Kubernetes responds: `FailedAttachVolume: Multi-Attach error for volume "csi-d03a658e-..." Volume is already used by pod(s) nim-llm-599f644859-kqbhz`.
6. Retry pod stays `ContainerCreating` forever (currently 3h14m+ elapsed).
7. Job stays `Running 0/1, active=1` indefinitely (`backoffLimit: 5` configured; it would re-spawn 5 times).
8. NIMCache CR `.status.conditions[NIM_CACHE_JOB_COMPLETED] = False, reason: JobFailed`. State stays `InProgress`.
9. NIMService CR `.status.conditions[Ready] = False, reason: NIMCacheNotReady, message: "NIMCache nim-llm-cache not ready"`.
10. The Terraform post-deploy hook `terraform_data.patch_nim_operator_resources` (in `ai-accelerator-tf/helm.tf:594`) does `kubectl wait nimservice/nim-llm --for=condition=Ready --timeout=30m`. It hits the 30-min timeout, exits non-zero, and the apply FAILS.

### Why this is functional vs strict-correctness

- **Functional**: the live `nim-llm` pod is happily serving traffic. `/v1/chat/completions` returns valid model output. End user, hitting the LB URL, would never know anything was wrong.
- **Strict-correctness**: ORM Console shows the apply as FAILED. A user reading job state would reasonably conclude the deployment broke.

### Why other NIMServices succeed

The 6 other NIMServices in the deployment (nemotron-embedding, nemotron-ranking, nemoretriever-ocr-v1, nemoretriever-graphic-elements-v1, nemoretriever-page-elements-v3, nemoretriever-table-structure-v1) reached `Ready=True` normally. Only `nim-llm` is stuck. Two hypotheses why:

- **(H1)** Only the `nim-llm` chart sets a NIMCache CR with retry-job behavior; the other NIMServices fetch their models differently.
- **(H2)** Only the `nim-llm` model is large enough that the Job runtime triggers operator-side retry logic; the smaller model fetches complete fast enough to evade the retry race.

Worth disambiguating during investigation.

---

## 2. Timeline of Events (UTC)

| Time | Event |
|---|---|
| 2026-05-05 20:14Z | Track 1 dispatched to SJC AD-1 (LON OCI capacity issue earlier — irrelevant here) |
| 2026-05-05 20:36:29Z | Infra stack apply submitted |
| 2026-05-05 21:04:45Z | Infra apply SUCCEEDED (28 min) — 2 BM.GPU4.8 + 2 E5.Flex nodes |
| 2026-05-05 22:44:29Z | App stack apply submitted |
| 2026-05-05 22:53Z | rag namespace created, nim-operator helm release deployed, NIMCache CR `nim-llm-cache` created (PVC_CREATED condition flipped at 22:53:10Z) |
| 2026-05-05 22:53:11Z | NIMService CR `nim-llm` initial Ready condition: `False, reason: NIMCacheNotReady` (this is the original/expected initial state) |
| 2026-05-05 ~22:55Z | Original cache job `nim-llm-cache-job-vlqws` runs, downloads model |
| 2026-05-05 ~23:31Z | nim-llm Deployment pod becomes 1/1 Ready, model loaded |
| 2026-05-05 23:40:32Z | NIMCache CR transition: NIM_CACHE_RECONCILE_FAILED→False ("Reconciled"), JOB_PENDING→False ("JobRunning"), JOB_COMPLETED→False ("JobFailed"), JOB_CREATED→True ("JobCreated"). **The retry Job `nim-llm-cache-job-qn466` is spawned at this moment.** |
| 2026-05-05 23:40:32Z | NIMService CR transition: Failed→False ("Ready"), but Ready stayed False ("NIMCacheNotReady") |
| 2026-05-05 ~23:41Z | Retry pod fails to mount PVC: Multi-Attach error |
| 2026-05-06 00:00:41Z | App apply terminal: FAILED (TERRAFORM_EXECUTION_ERROR after 76m total) |
| 2026-05-06 ~00:35Z | Functional smoke test PASSED — chat completions returning valid output |

---

## 3. Cluster + Stack Details (Live)

### OCI Resource Manager Stacks

```
INFRA  ACTIVE  Enterprise RAG - Infra - v0.0.8 2026-05-05_2014 SJC (track1)
       ocid1.ormstack.oc1.us-sanjose-1.amaaaaaam3augwaa36wqai2lpepvs3uymr2lntnotlzc4luju5itmeu52aqa
       Created 20:36:29Z, apply SUCCEEDED 21:04:45Z

APP    ACTIVE  Enterprise RAG - App   - v0.0.8 2026-05-05_2200 SJC (track1)
       ocid1.ormstack.oc1.us-sanjose-1.amaaaaaam3augwaa34uz2j72yv65fhw5hm3izvlyzc23vjqzexog2z4qhfza
       Created 22:44:29Z, apply FAILED 00:00:41Z (Terraform execution error)
       Failed job: ocid1.ormjob.oc1.us-sanjose-1.amaaaaaam3augwaaljqfroyb6c3sijbif2cqrxumus47p5b5lzdsd4vfyamq
```

Region: `us-sanjose-1`
Compartment: Grant-Compartment (under `aiincubations` tenancy)

### OKE Cluster

```
Name:           AI-Accel-OKE-oTKAI4
OCID:           ocid1.cluster.oc1.us-sanjose-1.aaaaaaaaldpn7mp443ajpejixedo6enlgp7n4vo3uo2re3fgkc7qxne25emq
Public ep:      192.9.225.66:6443
Private ep:     10.0.86.201:6443
VCN hostname:   c7qxne25emq.endpointotkai4.vcnotkai4.oraclevcn.com:6443
Kubernetes:     v1.34.1
Node count:     4 Ready (2 BM.GPU4.8 workers + 2 E5.Flex control-plane)
```

### Networking

```
VCN:               ocid1.vcn.oc1.us-sanjose-1.amaaaaaam3augwaahy46pc2n5flio3d5orqaajo2h42imhdzlovwulpmvrca
Node subnet:       ocid1.subnet.oc1.us-sanjose-1.aaaaaaaavinqzam654ylg456wjpluzpi2q3bmc3gbvenzqac3jnsyuijwz3a
ADB subnet:        ocid1.subnet.oc1.us-sanjose-1.aaaaaaaafmg6wqi7d4dosyswzyv7lek2ashrfxbwrpxmgbms2amggrb4rlyq
LB IP (frontend):  146.235.205.26
LB hostnames:      blueprints.146-235-205-26.nip.io
                   api.146-235-205-26.nip.io
                   grafana.146-235-205-26.nip.io
                   prometheus.146-235-205-26.nip.io
```

### Pods (rag namespace) — current state

14 of 15 pods Running 1/1. Only stuck pod:

```
nim-llm-cache-job-qn466   0/1   ContainerCreating   3h14m+   <none>   10.0.101.80
```

The live nim-llm pod (working fine):

```
nim-llm-599f644859-kqbhz   1/1   Running   3h24m   172.16.2.13   10.0.108.163 (BM.GPU4.8)
```

### Storage

```
PVC:           nim-llm-cache-pvc
StorageClass:  oci-bv (default; provisioner: blockvolume.csi.oraclecloud.com)
AccessMode:    ReadWriteOnce         ← THE BUG
Capacity:      500Gi
Status:        Bound
PV:            csi-d03a658e-ffd5-4546-97e9-d6725cd81952
Volume OCID:   ocid1.volume.oc1.us-sanjose-1.abzwuljrf26qwph4jw7xwvfimoxcctficzyejvb4yjejcjosjs273ttyp7da
fsType:        ext4
```

All 10 PVCs in `rag` namespace use `oci-bv` (block) + RWO. **No FSS storage class is provisioned on this cluster** — fix candidate (a) "RWX PVC" requires adding `oci-fss` storage class at the infra level.

### NIMCache CR (the stale one)

```yaml
spec:
  source.ngc.model.engine: vllm
  source.ngc.model.precision: fp8
  source.ngc.model.tensorParallelism: "8"
  source.ngc.modelPuller: nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b:1.8.0
  storage.pvc.size: 500Gi
  storage.pvc.volumeAccessMode: ReadWriteOnce    ← explicitly set in chart template
status:
  state: InProgress
  conditions:
    NIM_CACHE_PVC_CREATED:        True   "PVC has been created"   22:53:10Z
    NIM_CACHE_RECONCILE_FAILED:   False  "Reconciled"             23:40:32Z
    NIM_CACHE_JOB_PENDING:        False  "JobRunning"             23:40:32Z
    NIM_CACHE_JOB_COMPLETED:      False  "JobFailed"              23:40:32Z
    NIM_CACHE_JOB_CREATED:        True   "JobCreated"             23:40:32Z
```

### NIMService CR (the stale one)

```yaml
status:
  state: NotReady
  conditions:
    Ready:   False  reason: NIMCacheNotReady   message: "NIMCache nim-llm-cache not ready"   22:53:11Z
    Failed:  False  reason: Ready              message: "NIMCache nim-llm-cache not ready"   23:40:32Z
```

### Job / retry pod

```
NAME                STATUS    COMPLETIONS  DURATION  AGE
nim-llm-cache-job   Running   0/1          3h15m+    3h15m+

spec.backoffLimit: 5
spec.completions:  1
spec.parallelism:  1
ownerRef:          NIMCache/nim-llm-cache (controller=true)
status.active:     1
```

Original Multi-Attach event has aged out of k8s default 1h event TTL but was captured live earlier in the BUGS.md BUG-032 entry.

### Functional probe (verified pack works)

```bash
# In-cluster
kubectl exec -n rag <any-pod> -- curl -s http://nim-llm.rag.svc.cluster.local:8000/v1/models
# → 200 OK, returns model nvidia/nemotron-3-super-120b-a12b, max_model_len=32768

kubectl exec -n rag <any-pod> -- curl -s -X POST http://nim-llm.rag.svc.cluster.local:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"nvidia/nemotron-3-super-120b-a12b","messages":[{"role":"user","content":"Say hi"}],"max_tokens":5}'
# → 200 OK, returns chatcmpl-... with valid choices array

# External (LB)
curl -k https://blueprints.146-235-205-26.nip.io/  # frontend portal (TLS warning expected, self-signed)
```

GPU utilization on the worker node hosting nim-llm: 38169/40960 MiB used on GPU0 (93%) at idle, FP8 model loaded.

---

## 4. How to Connect (for the investigator)

```bash
# Generate kubeconfig
oci ce cluster create-kubeconfig \
  --cluster-id ocid1.cluster.oc1.us-sanjose-1.aaaaaaaaldpn7mp443ajpejixedo6enlgp7n4vo3uo2re3fgkc7qxne25emq \
  --region us-sanjose-1 \
  --kube-endpoint PUBLIC_ENDPOINT \
  --token-version 2.0.0 \
  --file ~/.kube/config-bug032

# Patch user.exec.args to inject your OCI profile
sed -i.bak 's|- ce$|- ce\n      - --profile\n      - aiincubations|' ~/.kube/config-bug032

export KUBECONFIG=~/.kube/config-bug032
kubectl get nodes              # 4 Ready
kubectl get pods -n rag        # 15 pods, retry stuck
kubectl get pvc -n rag         # all RWO
```

---

## 5. Reproduction Commands (validate the diagnosis yourself)

```bash
# 1) Confirm both NIMCache + NIMService are stale despite pod being healthy
kubectl get nimcache -n rag nim-llm-cache -o jsonpath='{.status.state}'         # InProgress
kubectl get nimservice -n rag nim-llm -o jsonpath='{.status.state}'             # NotReady
kubectl get pod -n rag -l app.kubernetes.io/name=nim-llm                        # 1/1 Running

# 2) Confirm the retry pod is stuck on Multi-Attach
kubectl get pods -n rag | grep nim-llm-cache-job                                # job-qn466 Pending/CC
RETRY_POD=$(kubectl get pods -n rag -o name | grep nim-llm-cache-job-qn466 | head -1)
kubectl describe -n rag $RETRY_POD                                              # Event TTL may have aged out
kubectl logs -n rag $RETRY_POD                                                  # likely empty (never started)

# 3) Confirm the live pod uses the same PV the retry pod wants
kubectl get pvc -n rag nim-llm-cache-pvc -o jsonpath='{.spec.accessModes}'      # [ReadWriteOnce]
kubectl get pod -n rag nim-llm-599f644859-kqbhz -o jsonpath='{.spec.volumes}' | jq

# 4) Confirm pack functions despite the failed apply
kubectl exec -n rag deploy/nim-llm -- curl -s http://localhost:8000/v1/models
kubectl exec -n rag deploy/nim-llm -- curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"nvidia/nemotron-3-super-120b-a12b","messages":[{"role":"user","content":"Hello"}],"max_tokens":10}'
```

---

## 6. Fix Candidates (with trade-offs)

### (a) Storage layer — RWX PVC backed by FSS
- Change NIMCache `.spec.storage.pvc.volumeAccessMode` to `ReadWriteMany`.
- Requires:
  1. Add `oci-fss` storage class to OKE cluster (FSS provisioner).
  2. Set `volumeAccessMode: ReadWriteMany` and `storageClassName: oci-fss` on the NIMCache CR.
  3. Verify nim-operator chart accepts these overrides (check chart values).
- Pros: clean storage-level fix; concurrent mount works.
- Cons: FSS is slower than block volume (network filesystem); 500Gi NFS-style storage may impact model load times; provisioning FSS at infra level requires changes to `ai-accelerator-tf/network.tf` + new resources.

### (b) Operator layer — suppress retry once cache satisfied
- Configure `spec.backoffLimit: 0` on the Job, OR file an upstream nim-operator bug to skip retry when the underlying Deployment pod is already serving (idempotency).
- Pros: no storage architecture change.
- Cons: requires either chart values override that may not exist, OR upstream fix; doesn't help if the chart re-spawns the Job with backoffLimit=5 hard-coded.

### (c) Hook layer — widen `terraform_data.patch_nim_operator_resources` predicate
- File: `ai-accelerator-tf/helm.tf:594` (and `:761` for the `_via_operator` variant).
- Current: `kubectl wait nimservice/nim-llm --for=condition=Ready --timeout=30m`
- Proposed: replace with custom check that accepts pod-Ready + curl /v1/health (or curl /v1/models) as success, ignoring stale CR status.
- Pros: no upstream chart dependency, no FSS provisioning, works around the operator bug at the wrapper layer.
- Cons: doesn't fix root cause; future operator versions might reorganize the CR conditions and break this workaround again; arguably masks the real upstream issue.

### (d) Architecture layer — split cache + serving PVCs
- Have a separate cache PVC for the download Job, copy/sync to the serving PVC during pod init, allow Job to use a transient PVC.
- Pros: addresses root cause cleanly.
- Cons: large architectural change in the rag chart; not feasible without upstream cooperation.

**Recommendation for v0.0.8 release**: ship as-is with documented workaround (verify pack health by curling LB URL, ignore the FAILED apply state). File for v0.0.9 with fix candidate **(c)** as the most pragmatic next step.

---

## 7. New Findings Worth Investigating

1. **`volumeAccessMode: ReadWriteOnce` is set in the NIMCache CR template** (not a chart default). The rag chart ships this explicitly. Investigation: where in the rag-v2.5.0 chart's template tree is this set, and is there a chart-values override knob?

2. **`backoffLimit: 5` on the Job** (explicit retry policy). nim-operator-3.1.0 sets this; investigate whether the chart exposes this as a configurable.

3. **patcher's `kubectl wait` predicate disagrees with NIMCache's actual state**. The patcher logged `nimcache/nim-llm-cache condition met` while NIMCache CR `.status.state` is still `InProgress`. The patcher uses `kubectl wait nimcache --for=jsonpath='{.status.state}=Ready'` (per `helm.tf:600-611`). So the patcher saw `state=Ready` at some point, but the operator later flipped state back to `InProgress` when it spawned the retry. This timing race deserves investigation.

4. **nim-operator helm release ships with empty user values** (chart defaults only). Worth checking the chart's exposed knobs for retry behavior or PVC access mode overrides.

5. **6 of 7 NIMServices recovered cleanly**; only nim-llm got stuck. What's special about nim-llm vs the others? Hypotheses: (H1) different NIMCache CR template only for nim-llm; (H2) larger model triggers retry-on-startup logic; (H3) longer Job runtime triggers a timeout-based retry.

---

## 8. References

- `ai-accelerator-tf/helm.tf:594` — `terraform_data.patch_nim_operator_resources` (the failing wait gate)
- `ai-accelerator-tf/helm.tf:761` — `_via_operator` variant (used in private-K8s mode)
- `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` — rag chart values
- `BUGS.md` BUG-032 entry (table line 38, full detail line 1462+)
- nim-operator chart: `k8s-nim-operator-3.1.0`
- rag chart: `https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.5.0.tgz`

---

## 9. Snapshot Provenance

Captured by track1-bmgpu4 at 2026-05-06 02:58 UTC. Full unstructured snapshot at `/tmp/track1-bmgpu4/bug-032-investigation-snapshot.txt` (~250 lines). This document distills + structures that snapshot for an external investigator.
