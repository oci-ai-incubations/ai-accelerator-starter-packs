# Frontend Skins — Architecture

This document describes how the frontend skins system works end-to-end, from the YAML catalog to the deployed container image(s). The system supports **multiple skins enabled simultaneously** per blueprint-pack deployment — users can turn on any combination of skins and each gets its own K8s deployment, service, ingress host, and URL.

## Problem

Frontend container images were hardcoded across multiple Terraform files (`blueprint_files.tf`, `app-vss-oracle-ux.tf`, Helm values). Adding a new frontend option or swapping an image required changes in several places, and there was no way for ORM users to choose which frontend UI(s) they wanted.

## Design Principle: Single Source of Truth

One YAML file defines all available skins. Two consumers read it:

1. **`create_final_schema.py`** (Python) — reads it at schema generation time to build one boolean toggle per skin
2. **`frontend-skins.tf`** (Terraform) — reads it at plan/apply time to resolve the user's enabled toggles to image URIs and K8s resources

Adding a new skin is a single-file change to the catalog plus one new `variable "skin_<name>"` entry in `vars.tf`. No other schema YAML, Python, or consumer-file changes needed.

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
│ Injects one       │  │ Reads skin_* bool vars,   │
│ boolean toggle    │  │ filters catalog to        │
│ per skin.         │  │ enabled_frontend_skins.   │
└────────┬─────────┘  └────────────┬─────────────┘
         │                         │
         ▼                         ▼
┌──────────────────┐  ┌──────────────────────────┐
│ ORM UI checkboxes │  │ local.enabled_frontend_  │
│                   │  │   skins (list)           │
│ User ticks any    │  │ local.primary_skin        │
│ combination of    │  │ local._catalog_default_   │
│ skin_* toggles    │  │   skin (fallback)         │
└────────┬─────────┘  └────────────┬─────────────┘
         │                         │
         │  var.skin_cuopt_core,   │
         │  var.skin_cuopt_partner,│
         │  var.skin_vss_core, ... │
         └────────────►────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
              Blueprint       Helm set       Outputs
              consumers       overrides      (multi-URL
              (cuopt, vss,    (enterprise_   map via
               paas_rag,       rag, uses      frontend_
               one job per     primary or     skin_urls)
               enabled skin)   catalog default)
```

## File-by-File Walkthrough

### `ai-accelerator-tf/schemas/frontend_skins.yaml`

The catalog. Each starter pack category has a `default` skin key and a list of `skins`. For **blueprint packs** (cuopt, vss, paas_rag), each skin entry has:

- `key` — the checkbox label, suffixed with `(Core App)` or `(Partner Contributed)`
- `image_uri` — full container image URI including tag
- `provider` — "Oracle" or "NVIDIA"
- `container_port` — the port the application inside the container listens on (maps to `recipe_container_port` in OCI AI Blueprints)
- `subdomain` — the per-skin ingress hostname prefix; each enabled skin gets `https://<subdomain>.<fqdn>`
- `variable_name` — the matching `skin_*` boolean variable name declared in `vars.tf`
- `default_enabled` — whether the toggle starts ticked in ORM

For **Helm packs** (enterprise_rag, enterprise_rag_aiq), skin entries have only `key`, `image_uri`, `provider`, and `container_port` — no `variable_name` / `subdomain` / `default_enabled` because these packs are single-skin in v1 and resolve via the catalog default rather than a toggle.

```yaml
cuopt:
  default: "Vehicle Route Optimizer Frontend (Core App)"
  skins:
    - key: "Vehicle Route Optimizer Frontend (Core App)"
      image_uri: "iad.ocir.io/.../cuopt-interactive-frontend-v0.0.2"
      provider: "Oracle"
      container_port: "3001"
      subdomain: "demo-cuopt"
      variable_name: "skin_cuopt_core"
      default_enabled: true
    - key: "Oracle Interactive - Route visualization (Partner Contributed)"
      image_uri: "iad.ocir.io/.../cuopt-interactive-frontend-v0.0.3"
      provider: "Oracle"
      container_port: "80"
      subdomain: "demo-cuopt-partner"
      variable_name: "skin_cuopt_partner"
      default_enabled: false
```

Keys are suffixed with `(Core App)` for Oracle-built and tested skins, or `(Partner Contributed)` for third-party skins.

### Why `container_port` matters

Different frontend images may serve on different ports. In OCI AI Blueprints, two port concepts exist:

- **`recipe_container_port`** — the port the application inside the container listens on. This must match what the frontend process actually binds to.
- **`recipe_host_port`** — the outward-facing port that OCI AI Blueprints opens for traffic. Defaults to port 80 if not specified.

The `container_port` field in the catalog maps to `recipe_container_port`. Without it, enabling skins that listen on different ports (e.g., Core App on 3001, Partner Contributed on 80) would result in a 502 Bad Gateway because the ingress routes traffic to a port that nothing is listening on.

### Environment variables

All skins within a pack share the same interface — they receive the same set of environment variables defined in `blueprint_files.tf` / `app-vss-oracle-ux.tf`. Each enabled skin gets the full base env var set (`CUOPT_ENDPOINT`, `LLAMASTACK_ENDPOINT`, `ADMIN_USERNAME`, `PORT`, etc.) regardless of whether that particular image uses them. Unused env vars in a container are harmless.

Environment variables are NOT part of the skin catalog. They live in the pack-specific Terraform and apply identically to all skins of that pack. This keeps the skin catalog simple.

### `ai-accelerator-tf/frontend-skins.tf`

Terraform-side resolution. Key locals:

- **`frontend_skins_catalog`** — `yamldecode(file(...))` reads the YAML.
- **`category_skins`** — the catalog's `skins` list for the current `starter_pack_category`.
- **`skin_enabled_map`** — `{ "skin_cuopt_core" = var.skin_cuopt_core, ... }`. Must stay in sync with the `variable "skin_*"` declarations in `vars.tf`; referencing an undeclared var is a plan-time error, which catches mismatches.
- **`enabled_frontend_skins`** — the catalog-ordered list of skins whose `variable_name` toggle is `true`. Empty for Helm packs (their catalog entries have no `variable_name`). Catalog order is preserved, which makes the primary-skin selection deterministic.
- **`primary_skin`** — the first element of `enabled_frontend_skins`, or `null` for Helm packs. The blueprint-pack precondition requires at least one skin enabled when `deploy_application=true`, so `primary_skin` is non-null in that case. Used by consumers that historically expected a single skin (Helm `set` blocks, back-compat scalar outputs).
- **`_catalog_default_skin`** — the catalog entry whose `key` matches the pack's top-level `default:` key. Used in two places:
  1. **Helm-pack back-compat fallback.** For enterprise_rag / enterprise_rag_aiq there are no `skin_*` toggles, so `primary_skin` is null; the scalar back-compat locals (`frontend_skin_image_uri`, `frontend_skin_provider`, `frontend_skin_name`, `frontend_skin_container_port`) fall back to this entry's fields so `helm.tf` and the scalar outputs keep working.
  2. **VSS K8s naming rule.** The default skin keeps the base resource name (`vss-oracle-ux`) while non-default skins get a suffix (`vss-oracle-ux-skin-vss-foo`).
- **`_assert_catalog_default_resolves`** — fail-fast assertion. If the catalog's top-level `default:` key fails to match any `skin.key`, `_catalog_default_skin` becomes `null` — which would silently break the VSS K8s naming rule (every skin becomes non-default and takes a suffix, breaking the upgrade-without-rename promise). The `tobool(...)` trick raises a plan error with a clear message.
- **`default_skin_variable_name`** — the `variable_name` of `_catalog_default_skin`, used by `app-vss-oracle-ux.tf` for the naming rule.
- **`frontend_skin_image_uri` / `_provider` / `_name` / `_container_port`** — scalar back-compat locals used by `helm.tf` (split into image repo+tag), VSS locals, and scalar outputs. Return `primary_skin`'s fields for blueprint packs; fall back to `_catalog_default_skin` for Helm packs.

### `ai-accelerator-tf/vars.tf`

One boolean variable per blueprint-pack skin. The naming convention is `skin_<category>_<identifier>`:

```hcl
variable "skin_cuopt_core"    { type = bool, default = true }
variable "skin_cuopt_partner" { type = bool, default = false }
variable "skin_vss_core"      { type = bool, default = true }
variable "skin_paas_rag_core" { type = bool, default = true }
```

Defaults follow the `default_enabled` field in the catalog so local Terraform runs without ORM produce a sensible deployment.

There is **no single `frontend_skin` enum variable anymore** and **no `cuopt_frontend_enabled` flag** — both have been removed. A pack is "frontend-enabled" iff at least one of its `skin_*` booleans is true.

### Consumer Files

**Blueprint packs** (`blueprint_files.tf`, `app-vss-oracle-ux.tf`) — iterate over `local.enabled_frontend_skins` (for_each) and produce one deployment/service/ingress/blueprint job per enabled skin. The container image and port come from the skin entry (`each.value.image_uri`, `each.value.container_port`). Each skin's resources get a unique name derived from `variable_name`, except for the default skin on VSS which keeps the base name (see below).

**Helm packs** (`helm.tf`) — split `local.frontend_skin_image_uri` into `frontend.image.repository` and `frontend.image.tag` via `split(":", ...)`. Because Helm packs have no `skin_*` toggles in v1, this always resolves to the catalog default skin.

### Default-skin-keeps-base-name rule (VSS)

In `app-vss-oracle-ux.tf`, each enabled skin produces a `kubernetes_deployment_v1`, `kubernetes_service_v1`, and `kubernetes_config_map_v1`. The naming rule is:

```hcl
_vss_k8s_name_suffix = {
  for key, skin in local._enabled_vss_skins :
  key => key == local.default_skin_variable_name ? "" : "-${replace(key, "_", "-")}"
}
# name = "vss-oracle-ux${local._vss_k8s_name_suffix[each.key]}"
```

The **default skin gets an empty suffix** so its K8s resource name stays `vss-oracle-ux` across stack upgrades. Non-default skins get `vss-oracle-ux-skin-vss-<name>`. This preserves the upgrade-without-rename property for the default skin: if a user upgrades from a single-skin build to a multi-skin build with the same default, Terraform does not recreate the default skin's deployment. If the default skin were renamed too (e.g., to `vss-oracle-ux-skin-vss-core`), Terraform would destroy and recreate the pod, causing downtime.

### Schema Files

**`common_schema.yaml`** defines:
- Four scalar output definitions (`frontend_skin_name`, `frontend_skin_image_uri`, `frontend_skin_provider`, `frontend_skins_learn_more`) for back-compat with the Helm packs and the scalar primary-skin outputs.
- A "Frontend" output group.

No hidden `frontend_skin` string variable exists — the per-skin boolean variables are declared in `vars.tf` directly, and `create_final_schema.py` injects matching boolean schema entries plus the `frontend_skin_urls` map output at schema-generation time.

**`create_final_schema.py`** runs two injection functions after the common+category deep merge:

1. `inject_frontend_skin_toggles` — for each skin in the category's catalog with a `variable_name`, injects a `type: boolean` variable into the schema with title = `skin.key`, default = `skin.default_enabled`, and a "Learn more" link in the description. The toggle is inserted into the "Deployment Configuration" variable group right after `starter_pack_size`, in catalog order.
2. `inject_frontend_skin_url_map_output` — declares `frontend_skin_urls` as a `type: map` output and places it first in the "Frontend" output group, removing the now-redundant `frontend_skin_image_uri` from the group's visible outputs.

### Group-level visibility for cuOpt credentials

Several cuOpt-only variables (`cuopt_frontend_admin_username`, `cuopt_frontend_admin_password`, `google_maps_api_key`, `genai_region`) are meaningful only when at least one cuOpt frontend skin is enabled. Per-variable `visible: { or: [...] }` does **not** work in ORM (see user memory: "ORM visibility limits"), so these variables are gated at the **variable-group** level in `schemas/cuopt_schema.yaml`:

```yaml
variableGroups:
  - title: "cuOpt Frontend Credentials"
    visible:
      or:
        - skin_cuopt_core
        - skin_cuopt_partner
    variables:
      - cuopt_frontend_admin_username
      - cuopt_frontend_admin_password
      - google_maps_api_key
      - genai_region
```

When both toggles are off, ORM hides the entire group. The `or` condition is the natural multi-skin replacement for the old `cuopt_frontend_enabled` gate.

### Outputs

| Output | Type | Description |
|---|---|---|
| `frontend_skin_urls` | `map` | Map of enabled-skin `key` → `https://<subdomain>.<fqdn>`. One entry per enabled blueprint-pack skin. Empty for Helm packs and `deploy_application=false`. |
| `frontend_skin_name` | `string` | Primary skin's display name (or catalog default for Helm packs). |
| `frontend_skin_image_uri` | `copyableString` | Primary skin's container image URI (or catalog default). |
| `frontend_skin_provider` | `string` | Primary skin's provider ("Oracle" or "NVIDIA"). |
| `frontend_skins_learn_more` | `link` | Clickable URL to `docs/skins/README.md`. |

The scalar outputs are retained for back-compat; new consumers should read `frontend_skin_urls` to get all enabled skins' URLs.

## Testing

### Terraform Unit Tests

`tests/starter_pack_frontend_skins.tftest.hcl` covers:

- Default-skin resolution per category (`primary_skin` matches the catalog default when only the default toggle is on).
- Explicit non-default selection (e.g., cuopt with only `skin_cuopt_partner` enabled).
- Scalar output population.
- Multi-skin: both cuopt toggles enabled produces two entries in `frontend_skin_urls` and `enabled_frontend_skins`.

Existing per-pack tests (`starter_pack_cuopt.tftest.hcl`, etc.) also exercise skin resolution implicitly via the default toggles.

### Schema Tests

- `schema_expectations.yaml` — per-category `variable_properties` asserting each `skin_*` variable has `type: boolean`, plus the `frontend_skin_urls` map output in `required_outputs`.
- `test_schema_structure.py` — parametrized assertions that each generated schema's injected skin toggles match the catalog (names, defaults, titles).

## Adding a New Skin

1. Add a skin entry to `schemas/frontend_skins.yaml` under the category, with `variable_name` set to the matching `skin_<name>` boolean.
2. Declare `variable "skin_<name>"` in `vars.tf` with the matching default.
3. If the new skin belongs to a pack that gates credentials by group visibility (e.g., cuopt), add the new `variable_name` to the `visibleGroup.or` list in the category schema YAML.
4. Regenerate schemas:
   ```bash
   python create_final_schema.py --all
   ```
5. Update `docs/skins/README.md` with the new skin's details (provider, image, version, repo link, description).

No `blueprint_files.tf`, `app-vss-oracle-ux.tf`, or `frontend-skins.tf` changes are needed — they iterate over `enabled_frontend_skins` generically.

## Limitations

- **Helm packs are single-skin in v1.** `enterprise_rag` and `enterprise_rag_aiq` resolve via `_catalog_default_skin` only; there are no `skin_*` toggles. Multi-skin support requires per-skin ingress routing in their Helm charts.
- **Default skin rename requires care.** Changing which catalog entry is the `default:` will flip K8s resource names on VSS (the old default loses the base name; the new default takes it), causing a destroy+recreate of both deployments. Treat default changes as breaking.
- **One-to-one toggle-to-variable mapping.** Each skin needs its own variable in `vars.tf`. A catalog-only skin (no variable) is invisible to the enabled-skins filter and will not deploy.
