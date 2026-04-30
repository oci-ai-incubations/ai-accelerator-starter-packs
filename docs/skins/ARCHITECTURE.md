# Frontend Skins — Architecture

This document describes how the frontend skins system works end-to-end, from the YAML catalog to the deployed container image(s). The system supports two rendering shapes:

- **Blueprint packs** (`cuopt`, `vss`, `paas_rag`, `warehouse_pick_path`): multi-select booleans. Users enable any combination of skins; each enabled skin gets its own K8s deployment, service, ingress host, and URL.
- **Helm packs** (`enterprise_rag`, `enterprise_rag_aiq`): single-select enum. Users pick exactly one skin from the catalog; the choice is injected into the Helm chart's frontend image values. The exact key path is **chart-specific** — `enterprise_rag` uses flat `frontend.image.{repository,tag}` values; `enterprise_rag_aiq` (chart `aiq2-web` v2.0.0) uses nested `aiq.apps.frontend.image.{repository,tag}` values because the workload is a sub-chart.

## Problem

Frontend container images were hardcoded across multiple Terraform files (`blueprint_files.tf`, `app-vss-oracle-ux.tf`, Helm values). Adding a new frontend option or swapping an image required changes in several places, and there was no way for ORM users to choose which frontend UI(s) they wanted.

## Design Principle: Single Source of Truth

One YAML file defines all available skins. Two consumers read it:

1. **`create_final_schema.py`** (Python) — reads it at schema generation time. For blueprint packs, injects one boolean toggle per skin. For Helm packs, injects a single `skin_<category>` enum variable whose options are the catalog's skin keys.
2. **`frontend-skins.tf`** (Terraform) — reads it at plan/apply time to resolve the user's choices (booleans for blueprint packs, enum for Helm packs) to image URIs and K8s resources.

Adding a new blueprint skin: add a catalog entry with `variable_name` + declare `variable "skin_<name>"` in `vars.tf` + extend `local.skin_enabled_map`. Adding a new Helm skin: add a catalog entry (no `variable_name` needed) — the enum list auto-updates at schema-gen time.

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

The catalog. Each starter pack category has a `default` skin key and a list of `skins`.

**Blueprint packs** (cuopt, vss, paas_rag, warehouse_pick_path) — each skin entry has:

- `key` — the checkbox label, suffixed with `(Core App)` or `(Partner Contributed)`
- `image_uri` — full container image URI including tag
- `provider` — "Oracle" or "NVIDIA"
- `container_port` — the port the application inside the container listens on (maps to `recipe_container_port` in OCI AI Blueprints)
- `subdomain` — the per-skin ingress hostname prefix; each enabled skin gets `https://<subdomain>.<fqdn>`
- `variable_name` — the matching `skin_*` boolean variable name declared in `vars.tf`
- `default_enabled` — whether the toggle starts ticked in ORM

**Helm packs** (enterprise_rag, enterprise_rag_aiq) — each skin entry has `key`, `image_uri`, `provider`, `container_port`, and `subdomain`. It does **not** have `variable_name` or `default_enabled` because the pack uses a pack-level enum variable rather than per-skin booleans. The catalog's presence/absence of `variable_name` is what tells `create_final_schema.py` which shape to inject (booleans vs enum).

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

All skins within a pack receive the same set of environment variables
defined in pack-specific Terraform (not the catalog). Env vars are NOT
part of `frontend_skins.yaml` — this keeps the catalog simple and lets
different packs expose different contracts.

For the **per-pack list** of env vars a skin receives, including worked
examples and the ingress-path routing used by some packs, see
[BACKEND_API_CONTRACT.md](BACKEND_API_CONTRACT.md). This architecture
document only notes where env vars are SET in the Terraform; the user
contract for skin authors lives in the sibling doc.

### `ai-accelerator-tf/frontend-skins.tf`

Terraform-side resolution. Key locals:

- **`frontend_skins_catalog`** — `yamldecode(file(...))` reads the YAML.
- **`category_skins`** — the catalog's `skins` list for the current `starter_pack_category`.
- **`skin_enabled_map`** — `{ "skin_cuopt_core" = var.skin_cuopt_core, ... }`. Blueprint-pack booleans only. Must stay in sync with the bool `variable "skin_*"` declarations in `vars.tf`; referencing an undeclared var is a plan-time error, which catches mismatches.
- **`helm_skin_enum_map`** — `{ "enterprise_rag" = var.skin_enterprise_rag, "enterprise_rag_aiq" = var.skin_enterprise_rag_aiq }`. Helm-pack enum variables. Each maps the category name to the user's selected skin key (empty string when unset).
- **`helm_pack_selected_skin`** — for Helm packs, resolves the enum choice to a catalog entry. Empty selection OR unrecognized key → catalog default (via `try(...)` wrapping). For blueprint pack categories, this is `null`.
- **`enabled_frontend_skins`** — the user's effective skin list. Branches on pack type:
  - Helm packs: `[helm_pack_selected_skin]` (always singleton).
  - Blueprint packs: catalog-ordered list of skins whose `variable_name` boolean is `true`.
  Catalog order is preserved, which makes the primary-skin selection deterministic.
- **`primary_skin`** — the first element of `enabled_frontend_skins`. For Helm packs: always non-null (enum defaults to catalog default). For blueprint packs: non-null when `deploy_application=true` (the `skin_validation` precondition requires ≥1 enabled skin).
- **`_catalog_default_skin`** — the catalog entry whose `key` matches the pack's top-level `default:` key. Used in two places:
  1. **Helm-pack enum fallback.** When the user's enum var is empty OR points at a key that doesn't exist, `helm_pack_selected_skin` falls back to this entry.
  2. **VSS K8s naming rule.** The default skin keeps the base resource name (`vss-oracle-ux`) while non-default skins get a suffix (`vss-oracle-ux-skin-vss-foo`).
  Correctness of the top-level `default:` matching is enforced by pytest tests (`test_default_enabled_matches_top_level_default`, `test_helm_packs_expose_single_skin_enum`) — no plan-time assertion is needed.
- **`default_skin_variable_name`** — the `variable_name` of `_catalog_default_skin`, used by `app-vss-oracle-ux.tf` for the naming rule.
- **`frontend_skin_image_uri` / `_provider` / `_name`** — scalar back-compat locals used by `helm.tf` (split into image repo+tag) and scalar outputs. Return `primary_skin`'s fields; fall back to `_catalog_default_skin` only when `primary_skin` is null (never happens for Helm packs post-enum; can only happen for blueprint packs in infra-only mode).

### `ai-accelerator-tf/vars.tf`

Two variable shapes:

**Blueprint packs — one boolean per skin.** Naming: `skin_<category>_<identifier>`:

```hcl
variable "skin_cuopt_core"    { type = bool, default = true }
variable "skin_cuopt_partner" { type = bool, default = false }
variable "skin_vss_core"      { type = bool, default = true }
variable "skin_paas_rag_core" { type = bool, default = true }
variable "skin_wpp_core"      { type = bool, default = true }
```

Defaults follow the `default_enabled` field in the catalog so local Terraform runs without ORM produce a sensible deployment.

**Helm packs — one string enum per pack.** Naming: `skin_<category>`:

```hcl
variable "skin_enterprise_rag"     { type = string, default = "" }
variable "skin_enterprise_rag_aiq" { type = string, default = "" }
```

Empty default means "use the catalog's top-level `default:` key" at plan time. The ORM wizard sets the actual default when rendering.

There is **no single `frontend_skin` enum variable anymore** and **no `cuopt_frontend_enabled` flag** — both have been removed. A blueprint pack is "frontend-enabled" iff at least one of its `skin_*` booleans is true; a Helm pack is always frontend-enabled and uses whichever skin the user (or catalog default) picked.

### Consumer Files

**Blueprint packs** (`blueprint_files.tf`, `app-vss-oracle-ux.tf`) — iterate over `local.enabled_frontend_skins` (for_each) and produce one deployment/service/ingress/blueprint job per enabled skin. The container image and port come from the skin entry (`each.value.image_uri`, `each.value.container_port`). Each skin's resources get a unique name derived from `variable_name`, except for the default skin on VSS which keeps the base name (see below). The `_cuopt_frontend_deployments`, `_paas_rag_frontend_deployments`, and `_wpp_frontend_deployments` list comprehensions filter with `if try(skin.variable_name, "") != ""` so Helm-pack entries (no `variable_name`) don't crash plan evaluation.

**Helm packs** (`helm.tf`) — split `local.frontend_skin_image_uri` into a `repository` and `tag` set entry via `split(":", ...)`. The image URI resolves from the user's enum selection via `primary_skin → helm_pack_selected_skin`, with catalog default as the fallback when the enum var is unset. The exact `set` key path is chart-specific: `enterprise_rag`'s `rag` release uses flat `frontend.image.*`; `enterprise_rag_aiq`'s `aiq` release uses nested `aiq.apps.frontend.image.*` (the `aiq2-web` v2.0.0 chart restructured its values from flat to a sub-chart layout). The structural test `test_helm_skin_override.py` enforces both per-release.

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
- Four scalar output definitions (`frontend_skin_name`, `frontend_skin_image_uri`, `frontend_skin_provider`, `frontend_skins_learn_more`) for back-compat with the scalar primary-skin outputs.
- A "Frontend" output group.
- Hidden (`visible: false`) entries for every `skin_*` variable so no undeclared ORM TF var auto-renders as a raw form field in the wrong category. Blueprint skin vars are `type: boolean`; Helm enum vars are `type: enum`. Category-specific schemas override the relevant entries to become visible.

**`create_final_schema.py`** runs two injection functions after the common+category deep merge:

1. `inject_frontend_skin_toggles` — branches on catalog shape:
   - Blueprint packs (entries have `variable_name`): injects one `type: boolean` variable per skin with title = `skin.key`, default = `skin.default_enabled`, and a "Learn more" link in the description.
   - Helm packs (no entries have `variable_name`): injects a single `type: enum` variable named `skin_<category>`, with the catalog's skin keys as the `enum` list and the catalog's top-level `default:` as the default. Validates that `default:` is in the `enum` list — raises `ValueError` at generation time if not.
   Both shapes land in a dedicated **"Frontend Skins" variableGroup** inserted right after "Deployment Configuration", in catalog order.
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

- Default-skin resolution per blueprint pack (`primary_skin` matches the catalog default when only the default toggle is on).
- Explicit non-default selection (e.g., cuopt with only `skin_cuopt_partner` enabled).
- Scalar output population.
- Multi-skin: both cuopt toggles enabled produces two entries in `frontend_skin_urls` and `enabled_frontend_skins`.
- Helm-pack default selection (`primary_skin` resolves to catalog default when `skin_<category>` is empty).
- Helm-pack explicit skin selection (setting the enum var to a valid key resolves to that skin).
- Helm-pack invalid-selection fallback (setting the enum var to a non-matching key falls back to catalog default instead of crashing).

Existing per-pack tests (`starter_pack_cuopt.tftest.hcl`, etc.) also exercise skin resolution implicitly via the default toggles.

### Schema Tests

- `schema_expectations.yaml` — per-category `variable_properties` asserting each `skin_*` variable has the expected type.
- `test_schema_structure.py::test_frontend_skin_booleans_match_catalog` — blueprint packs: booleans match catalog defaults.
- `test_schema_structure.py::test_helm_packs_expose_single_skin_enum` — Helm packs: single enum variable with enum list + default matching the catalog.
- `test_schema_structure.py::test_skin_catalog_matches_terraform` — bidirectional drift check across both shapes.
- `test_blueprint_structure.py::test_every_backend_recipe_has_annotation` — every backend recipe carries `recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino` (PR #102 feature). Allowlists the frontend list comprehensions.

## Adding a New Skin

### Blueprint pack (multi-select)

1. Add a skin entry to `schemas/frontend_skins.yaml` under the category, with `variable_name` set to the matching `skin_<name>` boolean.
2. Declare `variable "skin_<name>"` (type `bool`) in `vars.tf` with the matching default.
3. Add `"skin_<name>" = var.skin_<name>` to `local.skin_enabled_map` in `frontend-skins.tf`.
4. If the new skin belongs to a pack that gates credentials by group visibility (e.g., cuopt), add the new `variable_name` to the `visibleGroup.or` list in the category schema YAML.
5. Regenerate schemas:
   ```bash
   python create_final_schema.py --all
   ```
6. Update `docs/skins/README.md` with the new skin's details (provider, image, version, repo link, description).

No `blueprint_files.tf`, `app-vss-oracle-ux.tf`, or `frontend-skins.tf` downstream-consumer changes are needed — they iterate over `enabled_frontend_skins` generically.

### Helm pack (single-select enum)

1. Add a skin entry to `schemas/frontend_skins.yaml` under the Helm category. **Omit** `variable_name` and `default_enabled` — the enum list is auto-populated from all entries' `key` fields.
2. If the new skin changes the pack's `default:` key, update the catalog's top-level `default:` accordingly. Changing defaults has the same rename-caution as blueprint packs for VSS-style K8s naming, but Helm packs don't use that rule so it's safe.
3. No `vars.tf` or `frontend-skins.tf` changes needed if the pack's `skin_<category>` enum variable already exists (it does for `enterprise_rag` and `enterprise_rag_aiq`).
4. Regenerate schemas:
   ```bash
   python create_final_schema.py --all
   ```
5. Update `docs/skins/README.md`.

If you're adding a brand-new Helm pack, also:
- Declare `variable "skin_<category>" { type = string, default = "" }` in `vars.tf`.
- Add `"<category>" = var.skin_<category>` to `local.helm_skin_enum_map` in `frontend-skins.tf`.
- Add a `visible: false` fallback entry in `common_schema.yaml`.

## Limitations

- **Helm packs are single-skin at a time.** Users can pick one skin from the catalog via the dropdown, but only one runs. Running multiple skins simultaneously on a Helm pack would require the Helm chart's frontend sub-chart to accept a list of images, which it doesn't.
- **Default skin rename requires care.** Changing which catalog entry is the `default:` will flip K8s resource names on VSS (the old default loses the base name; the new default takes it), causing a destroy+recreate of both deployments. Treat default changes as breaking. Helm packs don't use this naming rule so the caveat doesn't apply there.
- **One-to-one toggle-to-variable mapping for blueprint packs.** Each blueprint skin needs its own boolean in `vars.tf`. A catalog-only skin (no `variable_name`) is treated as a Helm-pack entry by the injection logic and would not deploy as a blueprint.
