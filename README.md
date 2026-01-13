# AI Accelerator Starter Packs

Pre-configured Terraform deployments for AI/ML workloads on Oracle Cloud Infrastructure (OCI). Each starter pack includes an OKE (Oracle Kubernetes Engine) cluster with pre-configured compute shapes and AI blueprints for specific use cases.

## Available Starter Packs

### cuOpt Small
**Use Case:** NVIDIA cuOpt optimization workloads for route optimization, logistics, and operations research.

**Compute Resources:**
- **GPU Worker Nodes:** 1x BM.GPU4.8
  - 8x NVIDIA A100 40GB GPUs
  - 128 OCPUs (AMD EPYC 7J13)
  - 2048 GB RAM
  - 150 GB boot volume
- **Control Plane Nodes:** 2x VM.Standard.E5.Flex
  - 3 OCPUs each
  - 64 GB RAM each

---

### VSS Medium
**Use Case:** Video Search and Summarization (VSS) workloads with GPU acceleration for video processing and AI inference.

**Compute Resources:**
- **GPU Worker Nodes:** 1x BM.GPU4.8
  - 8x NVIDIA A100 40GB GPUs
  - 128 OCPUs (AMD EPYC 7J13)
  - 2048 GB RAM
  - 200 GB boot volume
- **Control Plane Nodes:** 2x VM.Standard.E5.Flex
  - 32 OCPUs each
  - 128 GB RAM each
- **CPU Worker Nodes:** 1x VM.Standard.E5.Flex
  - 3 OCPUs
  - 64 GB RAM
  - 150 GB boot volume

---

### AI.Q PaaS
**Use Case:** 'paas_rag' deploys RAG workloads on CPU using OCI PaaS services.

**Compute Resources:**
- **Control Plane Nodes:** 2x VM.Standard.E5.Flex
  - 6 OCPUs each
  - 48 GB RAM each
- **CPU Worker Nodes:** 1x VM.Standard.E5.Flex
  - 28 OCPUs
  - 128 GB RAM
  - 150 GB boot volume
- **Oracle Database 26ai:** Autonomous Database with AI features
  - 2 ECPU cores
  - 1 TB storage
  - AI-optimized lakehouse workload type

---

## Deploying using OCI Resource Manager (Stacks)

1. **Create a Stack** in OCI Console → Resource Manager -> Stacks.
2. **Upload the zip** zip the contents of the `ai-accelerator-tf/` folder (Terraform root) and upload it.
3. In the Stack UI, set:
   - `starter_pack_choice`: `cuopt_small` / `vss_medium` / `paas_rag`
   - `corrino_admin_username`, `corrino_admin_password`, `corrino_admin_email`
   - `db_username`, `db_password` (used for `paas_rag` database provisioning)
   -  Optional: Oracle Database 26ai sizing for `paas_rag` is also configurable (for example `db_compute_count` and `db_data_storage_size_in_tbs`) and can be customized if needed.
4. Run **Apply**.
5. Use Stack **Outputs** to find the portal URL, monitoring URL, and (for `paas_rag`) database details.

## Features

- **Pre-configured OKE Clusters:** Kubernetes clusters optimized for AI workloads
- **GPU Support:** GPUs with NVAIE (NVIDIA AI Enterprise) enabled
- **Monitoring Stack:** Prometheus and Grafana for observability
- **AI Blueprints:** Pre-deployed AI application blueprints for each use case
- **Oracle Database 26ai:** AI-optimized autonomous database (PaaS RAG pack)

## Outputs

After deployment, you'll receive:
- `blueprints_portal_url`: Portal URL
- `corrino_api_url`: Corrino/Blueprints API URL
- `starter_pack_url`: Starter pack URL (special handling for `vss_medium`)
- `grafana_url`: Grafana URL
- `prometheus_url`: Prometheus URL
