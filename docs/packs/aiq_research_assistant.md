# AI-Q Research Assistant Accelerator Pack

The **AI-Q Research Assistant Accelerator Pack** is an AI Accelerator Pack that delivers a combined **hardware and software** solution for agentic research workflows on Oracle Cloud Infrastructure (OCI). It deploys the [NVIDIA AI-Q Research Assistant (AIRA)](https://github.com/NVIDIA-AI-Blueprints/aiq-research-assistant) blueprint — an agentic RAG system that combines document retrieval with live web search to produce cited, multi-source research reports.

## What You Get

- **Hardware:** GPU-enabled OCI resources (OKE cluster and networking) sized for running both the AIRA agent and the underlying RAG pipeline.
- **Software:** The NVIDIA AI-Q Research Assistant stack, including:
  - **AIRA backend & frontend**: An agent that plans, retrieves, and synthesizes answers across document collections and the web.
  - **NVIDIA RAG pipeline**: Ingestor, retriever, and RAG server for document-grounded question answering.
  - **NIM for LLMs**: Llama-3.3-70b-instruct served via NVIDIA NIM for high-throughput inference.
  - **Observability**: Phoenix for tracing and monitoring agent runs.
  - **Web search** (optional): Tavily integration for real-time web retrieval alongside document collections.

## Use Cases

AI-Q Research Assistant is designed for knowledge workers who need to synthesize large volumes of documents quickly. Typical applications include:

- **Biomedical research**: Query clinical reports, literature, and trial summaries to surface insights across large corpora.
- **Financial analysis**: Analyze earnings reports, SEC filings, and financial documents from multiple companies side-by-side.
- **Enterprise knowledge Q&A**: Combine internal document collections with live web search to answer complex, multi-hop questions with citations.

## Deployment Architecture on OCI

```
┌──────────────────────────────────────────────────────────────────────────┐
│  OCI Tenancy                                                             │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  VCN                                                               │  │
│  │                                                                    │  │
│  │  ┌──────────────────────────────────────────────────────────────┐  │  │
│  │  │  OKE Cluster                                                 │  │  │
│  │  │                                                              │  │  │
│  │  │  ┌────────────────────────────────────────────────────────┐  │  │  │
│  │  │  │  GPU Node Pool (2 nodes × 8 GPUs each)                 │  │  │  │
│  │  │  │  BM.GPU4.8 (Small) or BM.GPU.A100-v2.8 (Medium)        │  │  │  │
│  │  │  │                                                        │  │  │  │
│  │  │  │  ┌────────────────────────────────────────────────┐    │  │  │  │
│  │  │  │  │  AIRA Agent (AI-Q Research Assistant)          │    │  │  │  │
│  │  │  │  │  ┌──────────────────┐  ┌────────────────────┐  │    │  │  │  │
│  │  │  │  │  │  AIRA Backend    │  │  AIRA Frontend     │  │    │  │  │  │
│  │  │  │  │  │  (planner +      │  │  (web UI :30080)   │  │    │  │  │  │
│  │  │  │  │  │   synthesizer)   │  │                    │  │    │  │  │  │
│  │  │  │  │  └────────┬─────────┘  └────────────────────┘  │    │  │  │  │
│  │  │  │  └───────────┼────────────────────────────────────┘    │  │  │  │
│  │  │  │              │ queries                                 │  │  │  │
│  │  │  │  ┌───────────▼────────────────────────────────────┐    │  │  │  │
│  │  │  │  │  NVIDIA RAG Pipeline                           │    │  │  │  │
│  │  │  │  │  ┌───────────┐  ┌───────────┐  ┌───────────┐   │    │  │  │  │
│  │  │  │  │  │ Ingestor  │  │ Retriever │  │ RAG Server│   │    │  │  │  │
│  │  │  │  │  └───────────┘  └───────────┘  └───────────┘   │    │  │  │  │
│  │  │  │  └────────────────────────┬───────────────────────┘    │  │  │  │
│  │  │  │                           │                            │  │  │  │
│  │  │  │  ┌────────────────────────▼───────────────────────┐    │  │  │  │
│  │  │  │  │  NIM LLM (Llama-3.3-70b-instruct)              │    │  │  │  │
│  │  │  │  └────────────────────────────────────────────────┘    │  │  │  │
│  │  │  │                                                        │  │  │  │
│  │  │  │  ┌──────────────┐  ┌──────────────┐                    │  │  │  │
│  │  │  │  │ Phoenix      │  │ Milvus       │                    │  │  │  │
│  │  │  │  │ (tracing)    │  │ (vector DB)  │                    │  │  │  │
│  │  │  │  └──────────────┘  └──────────────┘                    │  │  │  │
│  │  │  └────────────────────────────────────────────────────────┘  │  │  │
│  │  │                                                              │  │  │
│  │  │  ┌──────────────┐   ┌──────────────┐                         │  │  │
│  │  │  │  Ingress /   │   │  Blueprints  │                         │  │  │
│  │  │  │  Load Balancer│   │  Portal      │                        │  │  │
│  │  │  └──────────────┘   └──────────────┘                         │  │  │
│  │  └──────────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│                            ┌─────────────────┐                           │
│                            │  Tavily API     │ (optional, web search)    │
│                            └─────────────────┘                           │
└──────────────────────────────────────────────────────────────────────────┘
```

## Hardware Requirements

| Size | OCI Shape | Nodes | GPUs |
|------|-----------|-------|------|
| **Small** | BM.GPU4.8 | 2 | 16× A100 40GB (8 per node) |
| **Medium** | BM.GPU.A100-v2.8 | 2 | 16× A100 80GB (8 per node) |

Both sizes run the RAG pipeline and the AIRA agent across the same node pool. Use Medium if BM.GPU4.8 is unavailable in your region.

## Deployment and Access

You can deploy the AI-Q Research Assistant Accelerator Pack from the **OCI Console**. Under **AI Accelerator Packs**, select the AI-Q Research Assistant pack, choose a deployment size, add your NGC API key and optional Tavily API key for web search, and click Create. The console provisions the GPU compute, OKE cluster, networking, and the full AIRA software stack.

After deployment you get:

- **AIRA Web UI**: Accessible at port 30080 (`http://<node-ip>:30080`), where you can submit research queries, browse document collections, and view cited, multi-source answers.

> **Note:** Two default document collections are pre-loaded — one with biomedical research reports (Cystic Fibrosis) and one with public financial documents (Alphabet, Meta, Amazon) — to enable out-of-the-box demos.

## Additional References

- [NVIDIA AI-Q Research Assistant Blueprint](https://github.com/NVIDIA-AI-Blueprints/aiq-research-assistant)
- [NVIDIA RAG Blueprint](https://github.com/NVIDIA-AI-Blueprints/rag)
- [NVIDIA NIM for LLMs — Profile Selection](https://docs.nvidia.com/nim/large-language-models/latest/profiles.html)
