# Warehouse Pick Path Optimizer

The **Warehouse Pick Path Optimizer** is an AI Accelerator Pack that delivers a combined **hardware and software** solution for warehouse operations on Oracle Cloud Infrastructure (OCI) by pairing the [NVIDIA cuOpt](https://docs.nvidia.com/cuopt/user-guide/latest/introduction.html) GPU solver with a web application purpose-built for warehouse managers. It ingests Oracle WMS-compatible layout and order-batch CSVs and returns balanced, capacity-aware pick paths for a configurable number of pickers.

## What You Get

- **Hardware:** 1× NVIDIA A10 24 GB GPU (`VM.GPU.A10.1`) plus a CPU flex pool for the frontend and control plane, running on Oracle Kubernetes Engine (OKE).
- **Software:**
  - **Pick-path solver backend** (Python 3.13 + FastAPI + NVIDIA cuOpt on GPU, with a CPU nearest-neighbour fallback). Models a Capacitated VRP: waves → tasks (bin-packed to picker capacity) → per-picker routes with cumulative-carry-aware depot returns.
  - **Web frontend** (React + MUI Oracle dark theme) for uploading warehouse layouts, SKU masters, inventory snapshots, and order batches; configuring pickers / solver time / wave mode / direction; and exploring the optimised pick paths on a 2D map and in per-picker tables. Solutions can be exported to CSV for downstream WMS consumption.
  - **Oracle Autonomous DB (26ai)** persists uploads and authenticated user state; connects over TLS using the bundled connection string (no wallet required).

Together, the pack gives a warehouse team a one-click way to plan capacity-respecting pick paths across multiple pickers for either inbound (receiving / putaway) or outbound (shipping) flows.

## Use Case

Warehouses that run on Oracle WMS already have the raw signals needed to plan pick paths — locations, SKUs, inventory snapshots, and order batches — but turning that into an even, capacity-respecting route for a multi-picker crew is a manual, travel-heavy job. Left to humans, one picker often ends up with the majority of a large batch while others finish early; lines that exceed a picker's carry capacity need to be split by hand; and there is no fast way to rerun the plan when inventory or staffing changes.

The Warehouse Pick Path Optimizer closes the loop:

- Upload a `warehouse_layout.csv` once, then a fresh `order_batch.csv` per wave. Optional `sku_master.csv` unlocks weight-aware capacity splitting; optional `inventory_snapshot.csv` improves SKU-to-location resolution.
- Configure the number of pickers, solver time budget, wave grouping (single / priority / deadline), and direction (inbound / outbound). Click **Optimize**.
- Pick paths come back in seconds with: per-picker travel distance, estimated time, pick count, total carried weight, and a step-by-step table with zone / aisle / bay / level context. The results page charts picks-per-hour improvement and distance saved versus a capacity-aware baseline.
- Export the solution to CSV for the WMS, or iterate interactively by re-running with different parameters.

## Specs, Additional References, and Architecture

**Deployment Architecture on OCI**

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
│  │  │  │  GPU Node Pool                                         │  │  │  │
│  │  │  │  Small: 1× VM.GPU.A10.1 (NVIDIA A10 24 GB)             │  │  │  │
│  │  │  │                                                        │  │  │  │
│  │  │  │  ┌──────────────────────────────────────────────────┐  │  │  │  │
│  │  │  │  │  Pick-path Solver Backend                        │  │  │  │  │
│  │  │  │  │  (FastAPI + cuOpt GPU solver; CPU fallback)      │  │  │  │  │
│  │  │  │  └──────────────────┬───────────────────────────────┘  │  │  │  │
│  │  │  │                     │ /api                             │  │  │  │
│  │  │  │  ┌──────────────────▼───────────────────────────────┐  │  │  │  │
│  │  │  │  │  Web Frontend (React + MUI)                      │  │  │  │  │
│  │  │  │  │  CSV uploads, optimise form, pick-path map &     │  │  │  │  │
│  │  │  │  │  tables, CSV export                              │  │  │  │  │
│  │  │  │  └──────────────────────────────────────────────────┘  │  │  │  │
│  │  │  └────────────────────────────────────────────────────────┘  │  │  │
│  │  │                                                              │  │  │
│  │  │  ┌──────────────┐   ┌──────────────┐                         │  │  │
│  │  │  │  Ingress /   │   │  Blueprints  │                         │  │  │
│  │  │  │ Load Balancer│   │  Portal      │                         │  │  │
│  │  │  └──────┬───────┘   └──────────────┘                         │  │  │
│  │  └─────────┼────────────────────────────────────────────────────┘  │  │
│  └────────────┼───────────────────────────────────────────────────────┘  │
│               │                                                          │
│  ┌────────────▼──────────────────────┐                                   │
│  │  Oracle Autonomous DB (26ai)      │                                   │
│  │  Uploads, auth state, results     │                                   │
│  └───────────────────────────────────┘                                   │
└──────────────────────────────────────────────────────────────────────────┘
                │
                ▼
     Pick Path Optimizer Web UI
  (upload CSVs, configure pickers /
   direction / waves, run optimise,
   export solution)
```

### Inputs

| File | Required | Purpose |
|---|---|---|
| `warehouse_layout.csv` | Yes | Oracle WMS LOC interface — locations, zones, aisles, bays, coordinates. Upload infrequently. |
| `order_batch.csv` | Yes | Oracle WMS ORR (H1/H2) interface — order lines with SKU, qty, preferred pick location, priority, ship deadline. Upload per wave. |
| `sku_master.csv` | No | SKU master with per-unit weight — enables capacity-aware routing and per-line splitting. |
| `inventory_snapshot.csv` | No | Current on-hand inventory by location — improves SKU-to-location resolution when `preferred_pick_location_id` is missing. |

### Key Tunables

| Control | Default | Notes |
|---|---|---|
| Number of pickers | 1 | Cross-picker workload is balanced by an internal `ceil(total_work / num_pickers)` cap on each vehicle's demand. |
| Solver time | 5 s | Wall-clock budget for the cuOpt solver (1–60 s). Longer runs may find shorter routes. |
| Wave mode | Single | `single` / `priority` (one wave per priority value) / `deadline` (wave per ship-deadline window). |
| Direction | Inbound | `inbound` (truck → rack, putaway) / `outbound` (rack → truck, shipping). VRP is direction-symmetric; the value drives UI labels and downstream WMS semantics. |
| Solver mode | Consistent | `consistent` (deterministic single-climber cuOpt run) / `exploratory` (multi-climber, may beat the consistent mode on very large batches but varies between runs). |

## Deployment and Access

You can deploy the Warehouse Pick Path Optimizer from terraform directly, or by following the steps below from the base level of this repository:

```bash
python3 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt

python3 create_final_schema.py -c warehouse_pick_path

zip -r warehouse_pick_path.zip ai-accelerator-tf
```

Then, go to "stacks" in the console and upload the generated zip. Fill out the fields, click next, and select to run the apply job.


After deployment you get:

- **OCI AI Blueprints Portal** — URL exposed by the stack; manages blueprint lifecycle.
- **Warehouse Pick Path Optimizer UI** — upload CSVs, configure a run, optimise, and export the solution. Includes a first-run admin setup flow for tenant isolation.
