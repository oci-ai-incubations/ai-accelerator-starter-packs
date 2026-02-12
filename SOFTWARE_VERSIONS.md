# Software Versions

This document contains container image versions for each accelerator pack configuration.

## cuOpt Starter Pack

### cuOpt Small

| Container | Image | Version |
|-----------|-------|---------|
| cuOpt | nvcr.io/nvidia/cuopt/cuopt | 25.10.0-cuda12.9-py3.13 |
| LlamaStack (with frontend) | iad.ocir.io/iduyx1qnmway/corrino-devops-repository | llama-stack_v_d684ec9 |
| cuOpt Frontend | iad.ocir.io/iduyx1qnmway/corrino-devops-repository | cuopt-interactive-frontend-v0.0.1 |

### cuOpt Medium

| Container | Image | Version |
|-----------|-------|---------|
| cuOpt | nvcr.io/nvidia/cuopt/cuopt | 25.10.0-cuda12.9-py3.13 |
| LlamaStack (with frontend) | iad.ocir.io/iduyx1qnmway/corrino-devops-repository | llama-stack_v_d684ec9 |
| cuOpt Frontend | iad.ocir.io/iduyx1qnmway/corrino-devops-repository | cuopt-interactive-frontend-v0.0.1 |

## VSS Starter Pack

### VSS Small

| Container | Image | Version |
|-----------|-------|---------|
| VSS Engine | nvcr.io/nvidia/blueprint/vss-engine | 2.4.0 |
| Elasticsearch | docker.io/elasticsearch | 9.1.2 |
| Neo4j | docker.io/neo4j | 5.26.4 |
| Embedding NIM | nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2 | 1.9.0 |
| Rerank NIM | nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2 | 1.7.0 |
| LLM NIM | nvcr.io/nim/meta/llama-3.1-8b-instruct | 1.13.1 |

### VSS Medium

| Container | Image | Version |
|-----------|-------|---------|
| VSS Engine | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/vss-engine | 2.4.0-custom |
| Elasticsearch | docker.io/elasticsearch | 9.1.2 |
| Neo4j | docker.io/neo4j | 5.26.4 |
| Embedding NIM | nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2 | 1.9.0 |
| Rerank NIM | nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2 | 1.7.0 |
| Riva NIM | nvcr.io/nim/nvidia/parakeet-0-6b-ctc-en-us | 2.0.0 |
| LLM NIM | nvcr.io/nim/meta/llama-3.1-8b-instruct | 1.13.1 |

## PaaS RAG Starter Pack

### PaaS RAG Small

| Container | Image | Version |
|-----------|-------|---------|
| LlamaStack | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci | (no tag specified) |
| Frontend | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/oracle-net-frontend | latest |

### PaaS RAG Medium

| Container | Image | Version |
|-----------|-------|---------|
| LlamaStack | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci | (no tag specified) |
| Frontend | iad.ocir.io/iduyx1qnmway/corrino-devops-repository/oracle-net-frontend | latest |

## Enterprise RAG Starter Pack

### Enterprise RAG Small

| Container | Image | Version |
|-----------|-------|---------|
| RAG Server | nvcr.io/nvidia/blueprint/rag-server | 2.3.0 |
| Ingestor Server | nvcr.io/nvidia/blueprint/ingestor-server | 2.3.0 |
| RAG Frontend | iad.ocir.io/iduyx1qnmway/enterprise-rag-frontend | v0.0.1 |
| Elasticsearch | docker.io/bitnamilegacy/elasticsearch | 9.0.3-debian-12-r1 |
| Elasticsearch Volume Permissions | docker.io/bitnamilegacy/os-shell | 12-debian-12-r48 |
| Elasticsearch Sysctl | docker.io/bitnamilegacy/os-shell | 12-debian-12-r48 |
| OpenTelemetry Collector | otel/opentelemetry-collector-contrib | 0.131.0 |
| LLM NIM | nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5 | 1.14.0 |
| Embedding NIM | nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2 | 1.10.1 |
| VLM Embedding | nvcr.io/nvidia/nemo-microservices/llama-3.2-nemoretriever-1b-vlm-embed-v1 | 1.7.0 |
| Rerank NIM | nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2 | 1.8.0 |
| VLM NIM | nvcr.io/nim/nvidia/llama-3.1-nemotron-nano-vl-8b-v1 | 1.3.1 |
| NV-Ingest | nvcr.io/nvidia/nemo-microservices/nv-ingest | 25.9.0 |
| Milvus | docker.io/milvusdb/milvus | v2.5.17 |
| Milvus etcd | milvusdb/etcd | 3.5.22-r1 |
| MinIO | docker.io/minio/minio | RELEASE.2025-09-07T16-13-09Z |
| Redis | redis | 8.2.1 |
| PaddleOCR | nvcr.io/nim/baidu/paddleocr | 1.5.0 |
| NeMoRetriever OCR | nvcr.io/nvidia/nemo-microservices/nemoretriever-ocr-v1 | 1.1.0 |
| NeMoRetriever Graphic Elements | nvcr.io/nim/nvidia/nemoretriever-graphic-elements-v1 | 1.5.0 |
| NeMoRetriever Page Elements | nvcr.io/nim/nvidia/nemoretriever-page-elements-v2 | 1.5.0 |
| NeMoRetriever Table Structure | nvcr.io/nim/nvidia/nemoretriever-table-structure-v1 | 1.5.0 |
| NeMoRetriever Parse | nvcr.io/nim/nvidia/nemoretriever-parse | 1.2 |

## Unique nvcr containers
To extract from this file:
```bash
grep 'nvcr\.io' SOFTWARE_VERSIONS.md | awk -F'|' '{print $3"/"$4}' | sed 's/ *//g'| sort -u
nvcr.io/nim/baidu/paddleocr/1.5.0 
nvcr.io/nim/meta/llama-3.1-8b-instruct/1.13.1 
nvcr.io/nim/nvidia/llama-3.1-nemotron-nano-vl-8b-v1/1.3.1 
nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2/1.10.1 
nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2/1.9.0 
nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2/1.7.0 
nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2/1.8.0 
nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5/1.14.0 
nvcr.io/nim/nvidia/nemoretriever-graphic-elements-v1/1.5.0 
nvcr.io/nim/nvidia/nemoretriever-page-elements-v2/1.5.0 
nvcr.io/nim/nvidia/nemoretriever-parse/1.2 
nvcr.io/nim/nvidia/nemoretriever-table-structure-v1/1.5.0 
nvcr.io/nim/nvidia/parakeet-0-6b-ctc-en-us/2.0.0 
nvcr.io/nvidia/blueprint/ingestor-server/2.3.0 
nvcr.io/nvidia/blueprint/rag-frontend/2.3.0 
nvcr.io/nvidia/blueprint/rag-server/2.3.0 
nvcr.io/nvidia/blueprint/vss-engine/2.4.0 
nvcr.io/nvidia/cuopt/cuopt/25.10.0-cuda12.9-py3.13 
nvcr.io/nvidia/nemo-microservices/llama-3.2-nemoretriever-1b-vlm-embed-v1/1.7.0 
nvcr.io/nvidia/nemo-microservices/nemoretriever-ocr-v1/1.1.0 
nvcr.io/nvidia/nemo-microservices/nv-ingest/25.9.0
```
