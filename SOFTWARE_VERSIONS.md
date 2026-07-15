# Software Versions

This document contains container image versions for each accelerator pack configuration.

## Vehicle Route Optimizer

### Vehicle Route Optimizer Small

| Container | Image | Version |
|-----------|-------|---------|
| cuOpt | nvcr.io/nvidia/cuopt/cuopt | 25.10.0-cuda12.9-py3.13 |
| LlamaStack | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci | v0.0.3 |
| cuOpt Frontend | iad.ocir.io/iduyx1qnmway/corrino-devops-repository | cuopt-interactive-frontend-04caab9 |
| cuOpt Backend (FastAPI) | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/cuopt-ev-routing-backend | 7e621bb |
| Auth Service (when enable_auth_service=true) | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/accelerator-pack-auth-service | v1.1.0-a7121c7 |

### Vehicle Route Optimizer Medium

| Container | Image | Version |
|-----------|-------|---------|
| cuOpt | nvcr.io/nvidia/cuopt/cuopt | 25.10.0-cuda12.9-py3.13 |
| LlamaStack | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci | v0.0.3 |
| cuOpt Frontend | iad.ocir.io/iduyx1qnmway/corrino-devops-repository | cuopt-interactive-frontend-04caab9 |
| cuOpt Backend (FastAPI) | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/cuopt-ev-routing-backend | 7e621bb |
| Auth Service (when enable_auth_service=true) | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/accelerator-pack-auth-service | v1.1.0-a7121c7 |

The cuOpt Frontend is a static-SPA nginx image; /api/* routes through the OKE ingress to the cuopt-ev-routing-backend pod (FastAPI, HS256 JWT validation when auth-service is enabled). See the parent repo's `AUTH-INTEGRATION.md` for the pack auth-integration guide.

## Video Search and Summarization

### Video Search and Summarization POC

| Container | Image | Version |
|-----------|-------|---------|
| VSS Engine | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/vss-engine | 2.4.0-poc-custom-c105566 |
| VSS Oracle UX | iad.ocir.io/iduyx1qnmway/corrino-devops-repository | vss-oracle-ux-090468e |
| Download Service | iad.ocir.io/iduyx1qnmway/corrino-devops-repository | vss-download-service-090468e |
| Auth Service (when enable_auth_service=true) | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/accelerator-pack-auth-service | v1.1.0-a7121c7 |
| LlamaStack | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci | v0.0.3 |
| Elasticsearch | docker.io/elasticsearch | 9.1.2 |
| Neo4j | docker.io/neo4j | 5.26.4 |
| Embedding NIM | nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2 | 1.9.0 |
| Rerank NIM | nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2 | 1.7.0 |
| Riva NIM | nvcr.io/nim/nvidia/parakeet-0-6b-ctc-en-us | 2.0.0 |

### Video Search and Summarization Small

| Container | Image | Version |
|-----------|-------|---------|
| VSS Engine | nvcr.io/nvidia/blueprint/vss-engine | 2.4.0 |
| Elasticsearch | docker.io/elasticsearch | 9.1.2 |
| Neo4j | docker.io/neo4j | 5.26.4 |
| Embedding NIM | nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2 | 1.9.0 |
| Rerank NIM | nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2 | 1.7.0 |
| LLM NIM | nvcr.io/nim/meta/llama-3.1-8b-instruct | 1.13.1 |

### Video Search and Summarization Medium

| Container | Image | Version |
|-----------|-------|---------|
| VSS Engine | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/vss-engine | 2.4.0-custom |
| Elasticsearch | docker.io/elasticsearch | 9.1.2 |
| Neo4j | docker.io/neo4j | 5.26.4 |
| Embedding NIM | nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2 | 1.9.0 |
| Rerank NIM | nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2 | 1.7.0 |
| Riva NIM | nvcr.io/nim/nvidia/parakeet-0-6b-ctc-en-us | 2.0.0 |
| LLM NIM | nvcr.io/nim/meta/llama-3.1-8b-instruct | 1.13.1 |

## Managed Enterprise Chat Agent

### Managed Enterprise Chat Agent Small

| Container | Image | Version |
|-----------|-------|---------|
| LlamaStack | ord.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci | ba41068 |
| Frontend | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/oracle-net-frontend | v0.0.3 |

### Managed Enterprise Chat Agent Medium

| Container | Image | Version |
|-----------|-------|---------|
| LlamaStack | ord.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci | ba41068 |
| Frontend | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/oracle-net-frontend | v0.0.3 |

## Warehouse Pick Path Optimizer

### Warehouse Pick Path Optimizer Small

| Container | Image | Version |
|-----------|-------|---------|
| Pick-path Solver Backend | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/warehouse-pick-path-optimizer-be | 2d2a008 |
| Pick-path Optimizer Frontend | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/warehouse-pick-path-optimizer-fe | 2d2a008 |

The backend image extends `nvcr.io/nvidia/cuopt:26.6.0a-cuda13.0-py3.13` (GPU solver + Python 3.13). The backend and frontend are built from the same commit and share a short-SHA tag, pinned by `ai-accelerator-tf/blueprint_files.tf` on every release.

## Self-Hosted Enterprise Chat Agent

### Self-Hosted Enterprise Chat Agent Small

| Container | Image | Version |
|-----------|-------|---------|
| RAG Server | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/nvidia-rag-retrieval-oci | v0.0.7 |
| Ingestor Server | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/nvidia-rag-ingestion-oci | v0.0.7 |
| RAG Frontend | iad.ocir.io/iduyx1qnmway/enterprise-rag-frontend | v0.0.2 |
| Helm Chart | nvidia-blueprint-rag | v2.5.0 |
| NIM Operator | k8s-nim-operator | 3.1.0 |
| Elasticsearch | docker.io/bitnamilegacy/elasticsearch | 9.0.3-debian-12-r1 |
| Elasticsearch Volume Permissions | docker.io/bitnamilegacy/os-shell | 12-debian-12-r48 |
| Elasticsearch Sysctl | docker.io/bitnamilegacy/os-shell | 12-debian-12-r48 |
| OpenTelemetry Collector | otel/opentelemetry-collector-contrib | 0.131.0 |
| LLM NIM | nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b | 1.8.0 |
| Embedding NIM | nvcr.io/nim/nvidia/llama-nemotron-embed-1b-v2 | 1.13.0 |
| VLM Embedding | nvcr.io/nim/nvidia/llama-nemotron-embed-vl-1b-v2 | 1.12.0 |
| Rerank NIM | nvcr.io/nim/nvidia/llama-nemotron-rerank-1b-v2 | 1.10.0 |
| VLM NIM | nvcr.io/nim/nvidia/nemotron-nano-12b-v2-vl | 1.5.0 |
| NV-Ingest | nvcr.io/nvidia/nemo-microservices/nv-ingest | 26.1.2 |
| Redis | redis | 8.2.1 |
| PaddleOCR | nvcr.io/nim/baidu/paddleocr | 1.5.0 |
| NeMo OCR | nvcr.io/nim/nvidia/nemoretriever-ocr-v1 | 1.2.1 |
| Nemotron Graphic Elements | nvcr.io/nim/nvidia/nemotron-graphic-elements-v1 | 1.8.0 |
| Nemotron Page Elements | nvcr.io/nim/nvidia/nemotron-page-elements-v3 | 1.8.0 |
| Nemotron Table Structure | nvcr.io/nim/nvidia/nemotron-table-structure-v1 | 1.8.0 |
| Nemotron Parse | nvcr.io/nim/nvidia/nemotron-parse | 1.5.0 |

## Unique nvcr containers
To extract from this file:
```bash
grep 'nvcr\.io' SOFTWARE_VERSIONS.md | awk -F'|' '{print $3"/"$4}' | sed 's/ *//g'| sort -u
nvcr.io/nim/baidu/paddleocr/1.5.0
nvcr.io/nim/meta/llama-3.1-8b-instruct/1.13.1
nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2/1.9.0
nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2/1.7.0
nvcr.io/nim/nvidia/llama-nemotron-embed-1b-v2/1.13.0
nvcr.io/nim/nvidia/llama-nemotron-embed-vl-1b-v2/1.12.0
nvcr.io/nim/nvidia/llama-nemotron-rerank-1b-v2/1.10.0
nvcr.io/nim/nvidia/nemoretriever-ocr-v1/1.2.1
nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b/1.8.0
nvcr.io/nim/nvidia/nemotron-graphic-elements-v1/1.8.0
nvcr.io/nim/nvidia/nemotron-nano-12b-v2-vl/1.5.0
nvcr.io/nim/nvidia/nemotron-page-elements-v3/1.8.0
nvcr.io/nim/nvidia/nemotron-parse/1.5.0
nvcr.io/nim/nvidia/nemotron-table-structure-v1/1.8.0
nvcr.io/nim/nvidia/parakeet-0-6b-ctc-en-us/2.0.0
nvcr.io/nvidia/blueprint/vss-engine/2.4.0
nvcr.io/nvidia/cuopt/cuopt/25.10.0-cuda12.9-py3.13
nvcr.io/nvidia/nemo-microservices/nv-ingest/26.1.2
```
