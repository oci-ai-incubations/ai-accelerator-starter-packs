# Pack Roles and Permissions

When `enable_auth_service = true`, each AI Accelerator pack ships a per-pack
RBAC model that controls what users can do inside that pack's frontend
and backend. This page documents the roles and permissions for the packs
that currently have auth integration: **cuopt** and **vss**.

The auth-service selects the active model from the `AUTH_PACK` env var
(set by Terraform from `var.starter_pack_category`). The model is published
to frontends at `GET /auth/pack/model` so the admin panel can render only
the tabs and actions a deployment actually supports.

## How users acquire permissions

Two stacking sources:

1. **Primary role** (`User.role` — a strict 4-enum: `admin`, `user`,
   `reader`, `pending`). Set at registration or via `PATCH /auth/users/{id}`.
   Each primary role maps to a static set of permissions defined in the
   pack model.
2. **Additional roles** (custom `DbRole` rows created via `/auth/roles` and
   assigned to users via `POST /auth/users/{id}/roles`). Each custom role
   carries its own permission set.

The auth-service unions both sources into the JWT `scope` claim at token
issue time, so frontends gating UI on the scope claim see every permission
the backend would authorize. The `allowed_scopes` column on `User` is an
explicit narrowing override that, when set, takes precedence over the union
(use it to lock a specific user below their role's default scope set).

## Cuopt — Vehicle Route Optimizer

Pack ID: `cuopt`. Three primary roles. No collection-style fine-grained
permissions; cuopt has no per-tenant resources.

| Role | Permissions |
|---|---|
| `admin` | wildcard — every codename the pack declares |
| `user` | `cuopt.solve`, `cuopt.view`, `chat.use`, `weather.view`, `config.read` |
| `reader` | `cuopt.view`, `config.read` |
| `pending` | none (default for newly self-registered users until an admin promotes them) |

### Permission catalog

| Codename | Purpose |
|---|---|
| `cuopt.solve` | Submit routing problems to the cuopt backend (the core action) |
| `cuopt.view` | Read solver outputs, browse historical solves, view dashboards |
| `chat.use` | Use the in-app chat assistant (LlamaStack-backed) |
| `weather.view` | Pull weather-aware routing context (admin-gated feature flag) |
| `config.read` | Read pack-level configuration the frontend renders |
| `admin.users.manage` | Add/remove users, change their primary role, narrow `allowed_scopes` |
| `admin.config.write` | Mutate pack-level configuration |
| `admin.features.toggle` | Flip feature flags (e.g., enable `weather.view` UI) |
| `admin.audit.view` | Read the audit log |

## Vss — Video Search and Summarization

Pack ID: `vss`. Three primary roles.

| Role | Permissions |
|---|---|
| `admin` | wildcard — every codename the pack declares |
| `user` | `vss.summarize`, `vss.view`, `vss.review` |
| `reader` | `vss.view` |
| `pending` | none |

### Permission catalog

| Codename | Purpose |
|---|---|
| `vss.summarize` | Submit a video for processing (the core action — runs the VSS engine pipeline) |
| `vss.view` | Browse completed summaries, watch processed clips, query saved alerts |
| `vss.review` | Edit row-level annotations on `app/content-review` — gate for the "reviewer" cohort that curates the dataset |
| `admin.users.manage` | Add/remove users, change their primary role, narrow `allowed_scopes` |
| `admin.roles.manage` | CRUD `/auth/roles` — create custom roles with arbitrary permission sets |
| `admin.groups.manage` | CRUD `/auth/groups` — group memberships → role assignments |
| `admin.providers.manage` | CRUD `/auth/providers` — OIDC/SAML identity provider configuration |
| `admin.collections.manage` | CRUD `/auth/collections` — legacy collection-style permissions |
| `admin.features.toggle` | Flip feature flags |
| `admin.config.write` | Mutate pack-level configuration |
| `admin.audit.view` | Read the audit log |

### Backend route protection

The vss-oci backend (the NVIDIA blueprint fork) is reached only through the
vss-oracle-ux Next.js server — never directly from the browser. Backend
route scope checks therefore live on the Next.js auth-aware fetch client
plus the ingress `auth-url` annotation that points at the auth-service.
The vss-oci pod itself does not enforce JWT validation per-route.

## Custom (Additional) Roles

An admin can create deployment-specific roles via the FE Admin > Roles
panel (or `POST /auth/roles`). Each role takes:

- A `name` (max 100 chars)
- An optional `description` (max 500 chars)
- A set of permission codenames drawn from the active pack model's
  permission catalog

Assign a custom role to a user via Admin > Users > Additional Roles
(or `POST /auth/users/{id}/roles`). The user's effective scope set
becomes (primary-role permissions) ∪ (custom-role permissions),
provided `allowed_scopes` is not set.

Example: a Reader user is granted a custom "analyst" role that carries
`vss.summarize` and `vss.review`. Their next JWT will advertise
`vss.view vss.review vss.summarize`, and they'll be able to run the
summarization pipeline and edit review-grid rows even though their
primary role is Reader.

## Related Docs

- Parent repo `AUTH-INTEGRATION.md` — end-to-end pack auth-integration guide
- `docs/oci-idcs.md` — OCI IAM Identity Domains (IDCS) as an OIDC provider
- `accelerator-pack-auth-service/CLAUDE.md` — auth-service routes, settings, and database shapes
