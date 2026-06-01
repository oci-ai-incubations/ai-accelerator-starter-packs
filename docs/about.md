# About OCI AI Accelerator Packs

AI Accelerator packs are a full deployment OCI resource manager templates that deploy the necessary OCI services and Gen AI applications with optimizations to make Gen AI apps operational. AI Accelerator packs leverage OCI AI Blueprints as a platform to launch and manage the lifecycle of Gen AI applications. For more information please visit [product page.](https://www.oracle.com/artificial-intelligence/ai-accelerator-packs/?source=:eng:lw:ie::::AIAcceleratorPacksWebinar)

## Available AI Accelerator Packs & Details

All AI Accelerator Packs will deploy the OCI AI Blueprints which includes open-source components like **Prometheus, Grafana, PosgreSQL, KEDA & MLFlow**.
This list is updated frequently as we continue curating more.

## Vehicle Delivery Route Optimizer

### Deployment Sizes & Services Required

Table with a list of sizes and supported packs.

| Deployment Size | Component                               | Requirements                        | SKU                                | Specs              | Quantity |
| --------------- | --------------------------------------- | ----------------------------------- | ---------------------------------- | ------------------ | -------- |
| **POC**         | OCI Core Compute                        | Nvidia A10 24 GB GPU                | VM.GPU.A10.2                       | 2 GPUs             | 1        |
|                 |                                         | CPU VM Flex                         | VM.Standard.E5.Flex                | ocpus=3, memory=64 | 2        |
|                 |                                         | CPU VM Flex                         | VM.Standard.E5.Flex                | ocpus=4, memory=32 | 1        |
|                 | OCI Boot Volume                         | Boot Block Volume                   | NA                                 | 300 GB             | 1        |
|                 | OCI Services                            | OCI Gen AI Services Shared EndPoint | Consumption based license          |
|                 | OCI Services                            | Oracle Kubernetes Engine (OKE)      | NA                                 | NA                 | 1        |
|                 | NVIDIA AI Enterprise License & Software | cuOPT Libraries & NIM Containers    | OCI Billed (attached to # of GPUs) | NA                 | 8        |
|                 | OCI Software                            | OCI AI Blueprints                   | Free                               | 1                  | NA       |
| **SMALL**       | OCI Core Compute                        | Nvidia A100 40 GB GPU               | BM.GPU4.8                          | 8 GPUs             | 1        |
|                 |                                         | CPU VM Flex                         | VM.Standard.E5.Flex                | ocpus=3, memory=64 | 2        |
|                 |                                         | CPU VM Flex                         | VM.Standard.E5.Flex                | ocpus=4, memory=32 | 1        |
|                 | OCI Boot Volume                         | Boot Block Volume                   | NA                                 | 300 GB             | 1        |
|                 | OCI Services                            | OCI Gen AI Services Shared EndPoint | Consumption based license          |
|                 | OCI Services                            | Oracle Kubernetes Engine (OKE)      | NA                                 | NA                 | 1        |
|                 | NVIDIA AI Enterprise License & Software | cuOPT Libraries & NIM Containers    | OCI Billed (attached to # of GPUs) | NA                 | 8        |
|                 | OCI Software                            | OCI AI Blueprints                   | Free                               | 1                  | NA       |
| **MEDIUM**      | OCI Core Compute                        | Nvidia A100 80 GB GPU               | BM.GPU.A100-v2.8                   | 8 GPUs             | 1        |
|                 |                                         | CPU VM Flex                         | VM.Standard.E5.Flex                | ocpus=3, memory=64 | 2        |
|                 |                                         | CPU VM Flex                         | VM.Standard.E5.Flex                | ocpus=4, memory=32 | 1        |
|                 | OCI Boot Volume                         | Boot Block Volume                   | NA                                 | 300 GB             | 1        |
|                 | OCI Services                            | OCI Gen AI Services Shared EndPoint | Consumption based license          |
|                 | OCI Services                            | Oracle Kubernetes Engine (OKE)      | NA                                 | NA                 | 1        |
|                 | NVIDIA AI Enterprise License & Software | cuOPT Libraries & NIM Containers    | OCI Billed (attached to # of GPUs) | NA                 | 8        |
|                 | OCI Software                            | OCI AI Blueprints                   | Free                               | 1                  | NA       |

Other necessary VNET , public IP, load balancers and subnets are required.

## Video Search and Summarization

### Deployment Sizes & Services Required

Table with a list of sizes and supported packs.

| Deployment Size | Component                               | Requirements                                                      | SKU                                | Specs                | Quantity |
| --------------- | --------------------------------------- | ----------------------------------------------------------------- | ---------------------------------- | -------------------- | -------- |
| **SMALL**       | OCI Core Compute                        | Nvidia A100 40 GB GPU                                             | BM.GPU4.8                          | 8 GPUs               | 1        |
|                 |                                         | CPU VM Flex                                                       | VM.Standard.E5.Flex                | ocpus=32, memory=128 | 1        |
|                 |                                         | CPU VM Flex                                                       | VM.Standard.E5.Flex                | ocpus=3, memory=64   | 2        |
|                 | OCI Boot Volume                         | Boot Block Volume                                                 | NA                                 | 300 GB               | 1        |
|                 | OCI Services                            | Oracle Kubernetes Engine (OKE)                                    | NA                                 | NA                   | 1        |
|                 | NVIDIA AI Enterprise License & Software | NVIDIA Cosmos Reasoning, Parakeet, Related NIMs , Reranker Models | OCI Billed (attached to # of GPUs) | NA                   | 8        |
| OCI Software    | OCI AI Blueprints                       | Free                                                              | 1                                  | NA                   | NA       |
| **MEDIUM**      | OCI Core Compute                        | Nvidia L40S GPU                                                   | BM.GPU.L40S.4                      | 4 GPUs               | 2        |
|                 |                                         | CPU VM Flex                                                       | VM.Standard.E5.Flex                | ocpus=32, memory=128 | 1        |
|                 |                                         | CPU VM Flex                                                       | VM.Standard.E5.Flex                | ocpus=3, memory=64   | 2        |
|                 | OCI Boot Volume                         | Boot Block Volume                                                 | NA                                 | 300 GB               | 1        |
|                 | OCI Services                            | Oracle Kubernetes Engine (OKE)                                    | NA                                 | NA                   | 1        |
|                 | NVIDIA AI Enterprise License & Software | NVIDIA Cosmos Reasoning, Parakeet, Related NIMs , Reranker Models | OCI Billed (attached to # of GPUs) | NA                   | 8        |
| OCI Software    | OCI AI Blueprints                       | Free                                                              | 1                                  | NA                   | NA       |

Other necessary VNET , public IP, load balancers and subnets are required.

## Enterprise Knowledge Chat Agent - Self-Hosted AI Models

### Deployment Sizes & Services Required

Table with a list of sizes and supported packs.

| Deployment Size | Component                               | Requirements                   | SKU                                | Specs              | Quantity |
| --------------- | --------------------------------------- | ------------------------------ | ---------------------------------- | ------------------ | -------- |
| **SMALL**       | OCI Core Compute                        | Nvidia A100 40 GB GPU          | BM.GPU4.8                          | 8 GPUs             | 2        |
|                 |                                         | CPU VM Flex                    | VM.Standard.E5.Flex                | ocpus=4, memory=32 | 2        |
|                 | OCI Boot Volume                         | Boot Block Volume              | NA                                 | 300 GB             | 2        |
|                 | OCI Services                            | Oracle Kubernetes Engine (OKE) | NA                                 | NA                 | 1        |
|                 | NVIDIA AI Enterprise License & Software | NVIDIA NIMs                    | OCI Billed (attached to # of GPUs) | NA                 | 16       |
|                 | OCI Software                            | OCI AI Blueprints              | Free                               | 1                  |

Other necessary VNET , public IP, load balancers and subnets are required.

## Enterprise Knowledge Chat Agent - Managed AI Models

### Deployment Sizes & Services Required

Table with a list of sizes and supported packs.

| Deployment Size | Component            | Requirements                   | SKU                 | Specs               | Quantity |
| --------------- | -------------------- | ------------------------------ | ------------------- | ------------------- | -------- |
| **SMALL**       | OCI Core Compute     | CPU VM Flex                    | VM.Standard.E5.Flex | ocpus=4, memory=32  | 2        |
|                 | OCI Boot Volume      | Boot Block Volume              | NA                  | 300 GB              | 2        |
|                 | OCI Services         | Oracle Kubernetes Engine (OKE) | NA                  | NA                  | 1        |
|                 | OCI Services         | Oracle 26 AI                   | NA                  | 4 ECPU, 2TB storage | 1        |
|                 | Open Source Software | Meta LLama Stack               | Free                | NA                  | NA       |
|                 | OCI Software         | OCI AI Blueprints              | Free                | NA                  | NA       |
| **MEDIUM**      | OCI Core Compute     | CPU VM Flex                    | VM.Standard.E5.Flex | ocpus=4, memory=32  | 2        |
|                 | OCI Boot Volume      | Boot Block Volume              | NA                  | 300 GB              | 2        |
|                 | OCI Services         | Oracle Kubernetes Engine (OKE) | NA                  | NA                  | 1        |
|                 | OCI Services         | Oracle 26 AI                   | NA                  | 8 ECPU, 8TB storage | 1        |
|                 | Open Source Software | Meta LLama Stack               | Free                | NA                  | NA       |
|                 | OCI Software         | OCI AI Blueprints              | Free                | NA                  | NA       |

Other necessary VNET , public IP, load balancers and subnets are required.

## Warehouse Pick Path Optimizer

### Deployment Sizes & Services Required

| Deployment Size | Component                               | Requirements                        | SKU                                | Specs                | Quantity |
| --------------- | --------------------------------------- | ----------------------------------- | ---------------------------------- | -------------------- | -------- |
| **SMALL**       | OCI Core Compute                        | Nvidia A10 24 GB GPU                | VM.GPU.A10.1                       | 1 GPU                | 1        |
|                 |                                         | CPU VM Flex                         | VM.Standard.E5.Flex                | ocpus=3, memory=64   | 2        |
|                 |                                         | CPU VM Flex                         | VM.Standard.E5.Flex                | ocpus=8, memory=64   | 1        |
|                 | OCI Boot Volume                         | Boot Block Volume                   | NA                                 | 150 GB               | 1        |
|                 | OCI Services                            | Oracle Kubernetes Engine (OKE)      | NA                                 | NA                   | 1        |
|                 | OCI Services                            | Oracle 26 AI Autonomous Database    | NA                                 | 4 ECPU, 2 TB storage | 1        |
|                 | NVIDIA AI Enterprise License & Software | cuOpt Libraries                     | OCI Billed (attached to # of GPUs) | NA                   | 1        |
|                 | OCI Software                            | OCI AI Blueprints                   | Free                               | 1                    | NA       |

Other necessary VCN, public IP, load balancers, and subnets are required.

## Enterprise Agentic AI Starter Kit

### Deployment Sizes & Services Required

| Deployment Size | Component                               | Requirements                   | SKU                                | Specs              | Quantity |
| --------------- | --------------------------------------- | ------------------------------ | ---------------------------------- | ------------------ | -------- |
| **SMALL**       | OCI Core Compute                        | Nvidia A100 40 GB GPU          | BM.GPU4.8                          | 8 GPUs             | 2        |
|                 |                                         | CPU VM Flex                    | VM.Standard.E5.Flex                | ocpus=4, memory=32 | 2        |
|                 | OCI Boot Volume                         | Boot Block Volume              | NA                                 | 300 GB             | 2        |
|                 | OCI Services                            | Oracle Kubernetes Engine (OKE) | NA                                 | NA                 | 1        |
|                 | NVIDIA AI Enterprise License & Software | NVIDIA NIMs                    | OCI Billed (attached to # of GPUs) | NA                 | 16       |
|                 | OCI Software                            | OCI AI Blueprints              | Free                               | 1                  |

Other necessary VNET, public IP, load balancers and subnets are required.
