# Frontend Skins — Architecture

This document describes how the frontend skins system works end-to-end, from the YAML catalog to the deployed container image.

## Problem

Frontend container images were hardcoded across multiple Terraform files (`blueprint_files.tf`, `app-vss-oracle-ux.tf`, Helm values). Adding a new frontend option or swapping an image required changes in several places. There was no way for ORM users to choose which frontend UI they wanted.

## Design Principle: Single Source of Truth

One YAML file defines all available skins. Two consumers read it:

1. **`create_final_schema.py`** (Python) — reads it at schema generation time to build the ORM dropdown
2. **`frontend-skins.tf`** (Terraform) — reads it at plan/apply time to resolve the user's selection to an image URI

Adding a new skin is a single-file change to the catalog. No Terraform code, schema YAML, or Python script changes needed.

## Data Flow

```
┌─────────────────────────────────────────┐
│  schemas/frontend_skins.yaml            │
│  (single source of truth)               │
└──────────┬──────────────┬───────────────┘
           │              │
     Schema Gen       Terraform
           │              │
           ▼              ▼
┌──────────────────┐  ┌──────────────────────────┐
│ create_final_     │  │ frontend-skins.tf        │
│ schema.py         │  │                          │
│                   │  │ yamldecode(file(...))     │
│ Reads catalog,    │  │ coalesce(var, default)    │
│ injects enum into │  │ resolves to image_uri     │
│ generated schema  │  │                          │
└────────┬─────────┘  └────────────┬─────────────┘
         │                         │
         ▼                         ▼
┌──────────────────┐  ┌──────────────────────────┐
│ ORM UI Dropdown   │  │ local.frontend_skin_     │
│                   │  │   image_uri              │
│ User selects a    │  │   provider               │
│ skin from the     │  │   name                   │
│ enum list         │  │   container_port          │
└────────┬─────────┘  └────────────┬─────────────┘
         │                         │
         │   var.frontend_skin     │
         └────────────►────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
              Blueprint       Helm set       Outputs
              consumers       overrides
              (cuopt,vss,     (enterprise_   (skin name,
               paas_rag)       rag)           image, provider,
                                              learn more URL)
```

## File-by-File Walkthrough

### `ai-accelerator-tf/schemas/frontend_skins.yaml`

The catalog. Each starter pack category has a `default` skin and a list of `skins`, where each skin has:

- `key` — dropdown display text, suffixed with `(Core App)` or `(Partner Contributed)`
- `image_uri` — full container image URI including tag
- `provider` — "Oracle" or "NVIDIA"
- `container_port` — the port the application inside the container listens on (maps to `recipe_container_port` in OCI AI Blueprints)

```yaml
cuopt:
  default: "Vehicle Route Optimizer Frontend (Core App)"
  skins:
    - key: "Vehicle Route Optimizer Frontend (Core App)"
      image_uri: "iad.ocir.io/iduyx1qnmway/corrino-devops-repository:cuopt-interactive-frontend-v0.0.2"
      provider: "Oracle"
      container_port: "3000"
    - key: "Oracle Interactive - Route visualization (Partner Contributed)"
      image_uri: "iad.ocir.io/iduyx1qnmway/corrino-devops-repository:cuopt-interactive-frontend-v0.0.3"
      provider: "Oracle"
      container_port: "80"
```

The `key` is what appears in the ORM dropdown. It must be short and self-descriptive because ORM enum dropdowns show the raw string value with no per-item description. Keys are suffixed with `(Core App)` for Oracle-built and tested skins, or `(Partner Contributed)` for third-party skins.

### Why `container_port` matters

Different frontend images may serve on different ports. In OCI AI Blueprints, two port concepts exist:

- **`recipe_container_port`** — the port the application inside the container listens on. This must match what the frontend process actually binds to.
- **`recipe_host_port`** — the outward-facing port that OCI AI Blueprints opens for traffic. Defaults to port 80 if not specified.

The `container_port` field in the catalog maps to `recipe_container_port`. Without it, swapping between skins that listen on different ports (e.g., Core App on 3000, Partner Contributed on 80) would result in a 502 Bad Gateway because the ingress routes traffic to a port that nothing is listening on.

### Per-skin environment variables (`container_env`)

Each skin can specify a `container_env` list of static key/value pairs. These are environment variables that the skin's container needs but that differ between skins (e.g., `PORT`, `NODE_ENV`).

The pattern in `blueprint_files.tf`:
- If `container_env` is **empty** (`[]`): no env vars are injected — the image uses its Dockerfile defaults. This is the case for Core App skins that are self-contained.
- If `container_env` is **non-empty**: the skin-specific static values are merged with dynamic infrastructure values (Terraform variables like `ADMIN_USERNAME`, blueprint interpolation like `CUOPT_ENDPOINT`) that can't live in the YAML catalog. Both sets are injected together.

```yaml
# Core App — no env overrides, uses image defaults
container_env: []

# Partner Contributed — needs PORT and NODE_ENV overrides
container_env:
  - key: "NODE_ENV"
    value: "production"
  - key: "PORT"
    value: "3001"
```

This avoids a binary `inject_env` toggle and handles the case where two skins both need env vars but differ on specific values.

### `create_final_schema.py`

The `inject_frontend_skin()` function runs **after** the common+category schema deep merge. It:

1. Reads the skin keys for the current category from the catalog
2. Builds an `enum` variable definition with those keys as options
3. Injects it into the merged schema's `variables` section (overwriting the hidden `string` fallback from `common_schema.yaml`)
4. Appends `frontend_skin` to the "Deployment Configuration" variable group

For cuopt specifically, it sets conditional visibility tied to `cuopt_frontend_enabled` so the dropdown only appears when the frontend toggle is on.

The injection happens per-category during `--all` generation, so each pack's generated schema only contains that pack's skin options.

### `ai-accelerator-tf/frontend-skins.tf`

Terraform-side resolution. Key locals:

- **`frontend_skins_catalog`** — `yamldecode(file(...))` reads the same YAML
- **`effective_frontend_skin`** — `coalesce(var.frontend_skin, catalog_default)` handles the case where `var.frontend_skin` is empty (local dev without ORM)
- **`selected_skin`** — filters the category's skin list to find the matching entry
- **`frontend_skin_image_uri`** — the resolved container image, used by all consumers
- **`frontend_skin_container_port`** — the port the container listens on, used by blueprint and K8s consumers

### `ai-accelerator-tf/vars.tf`

```hcl
variable "frontend_skin" {
  type    = string
  default = ""
}
```

Default is empty string. ORM populates it from the schema enum's default. Local dev uses the `coalesce` fallback in `frontend-skins.tf`.

### Consumer Files

**Blueprint packs** (`blueprint_files.tf`, `app-vss-oracle-ux.tf`) — replaced hardcoded image URI strings with `local.frontend_skin_image_uri` and hardcoded `recipe_container_port` values with `local.frontend_skin_container_port`.

**Helm packs** (`helm.tf`) — added `set` blocks that split `local.frontend_skin_image_uri` into `frontend.image.repository` and `frontend.image.tag` using `split(":", ...)`, following the existing pattern used for `nim-llm.image.repository`.

**`enterprise_rag_aiq`** is scoped to a single skin in v1 (no `set` override). Its frontend is served by a separate Helm chart (`aiq`) with its own ingress resource in a different namespace, so swapping skins requires more than an image URI change.

### Schema Files

**`common_schema.yaml`** defines:
- A hidden `frontend_skin` variable (`type: string, visible: false`) as a fallback
- 4 output definitions (`frontend_skin_name`, `frontend_skin_image_uri`, `frontend_skin_provider`, `frontend_skins_learn_more`)
- A "Frontend Skin" output group

The hidden variable gets overwritten by `create_final_schema.py`'s injection with the proper `type: enum` definition. It exists so Terraform always has the variable declared even without ORM.

### Outputs

| Output | Type | Description |
|---|---|---|
| `frontend_skin_name` | `string` | Selected skin's display name |
| `frontend_skin_image_uri` | `copyableString` | Container image URI (with copy button in ORM) |
| `frontend_skin_provider` | `string` | "Oracle" or "NVIDIA" |
| `frontend_skins_learn_more` | `link` | Clickable URL to `docs/skins/README.md` |

## Testing

### Terraform Unit Tests

`tests/starter_pack_frontend_skins.tftest.hcl` — 7 test runs:

- One `*_default_skin_resolves` test per category (5 tests) — validates the `coalesce` fallback works when `frontend_skin` is empty
- `cuopt_explicit_nvidia_skin` — validates explicit non-default skin selection
- `skin_outputs_populated` — validates all 4 outputs resolve to non-null values

Existing per-pack tests (`starter_pack_cuopt.tftest.hcl`, etc.) also exercise skin resolution implicitly via the `coalesce` fallback.

### Schema Tests

- `schema_expectations.yaml` — `frontend_skin` in `required_variables`, 4 skin outputs in `required_outputs`, per-category `variable_properties` checking `type: enum`
- `test_schema_structure.py::TestFrontendSkinCatalogSync` — validates that each generated schema's `frontend_skin` enum values and default match the catalog YAML

## Adding a New Skin

One-file change in `schemas/frontend_skins.yaml`:

```yaml
vss:
  default: "Oracle Custom - Enhanced search (Core App)"
  skins:
    - key: "Oracle Custom - Enhanced search (Core App)"
      image_uri: "iad.ocir.io/.../vss-oracle-ux-dev-0.0.4"
      provider: "Oracle"
      container_port: "3000"
    - key: "NVIDIA Blueprint - Video analytics (Partner Contributed)"   # add this
      image_uri: "nvcr.io/nvidia/blueprint/vss-frontend:2.4.0"
      provider: "NVIDIA"
      container_port: "8080"
```

Then regenerate schemas:

```bash
python create_final_schema.py --all
```

No Terraform code changes. No schema YAML changes. No Python script changes. The new skin appears in the ORM dropdown and is resolvable by Terraform.

Also update `docs/skins/README.md` with the new skin's details (provider, image, version, repo link, description).

## Limitations

- **`enterprise_rag_aiq` is single-skin in v1.** Its frontend is deployed by a separate Helm chart with its own ingress and namespace. Multi-skin support requires designing ingress routing logic to toggle between Helm chart frontends.
- **ORM enum dropdowns show raw string values.** There are no per-item descriptions in the dropdown itself. The skin `key` must be self-descriptive. A "Learn More" link in the variable description points users to `docs/skins/README.md` for details.
- **One skin active at a time.** The system does not support deploying multiple frontends simultaneously. Switching skins requires re-applying the stack.
