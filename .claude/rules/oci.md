---
globs: ["ai-accelerator-tf/**/*.tf", "iam_policies.md"]
---

# OCI Rules

- Default region for testing: `us-sanjose-1`.
- Always set `OCI_CLI_PROFILE` before OCI CLI commands (common profiles: `SANJOSE`, `DEFAULT`).
- ORM stacks need zips with TF files at the root level, not nested in a subdirectory.
- When ORM destroy fails on k8s provider, try updating stack to terraform 1.5.x and retry.
- Customer secret keys have a quota of 2 per user — if creation fails with quota error, an existing key must be deleted first.
- For kubectl configuration, use `--kube-endpoint PUBLIC_ENDPOINT` with the OKE cluster.

## IAM Policy Rules

When creating or modifying `oci_identity_policy` resources, always use **minimum required permissions**. Never use broad policies like `manage all-resources` or `use all-resources`. Instead, determine the exact resource types and minimum verbs needed for each API call.

**Reference:** `iam_policies.md` contains the full breakdown of stack creation and feature policies. The OCI policy reference docs list every verb-to-API mapping:
- [Core Services (networking, compute)](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/corepolicyreference.htm)
- [Container Engine / OKE](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/contengpolicyreference.htm)
- [Object Storage](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/objectstoragepolicyreference.htm)
- [File Storage](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/filestoragepolicyreference.htm)
- [Autonomous Database](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/adbpolicyreference.htm)
- [IAM (identity, dynamic groups, policies)](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/iampolicyreference.htm)

**Process for determining policies:**
1. Identify every OCI API call the principal will make (from `resource` and `data` blocks).
2. Look up the resource type and minimum verb for each API in the relevant policy reference page.
3. Use the most restrictive verb that covers the needed operations (`inspect` < `read` < `use` < `manage`).
4. Scope policies to the compartment level whenever possible. Only use tenancy scope when required (e.g., `inspect all-resources in tenancy` for `GetNodePoolOptions`, or volume operations with `where request.principal.type = 'cluster'`).
5. Prefer individual resource types over aggregate families when only a subset of the family is needed (e.g., `manage clusters` instead of `manage cluster-family` if node pools aren't needed).

**Verb-to-operation quick reference for this stack's resources:**

| Resource Type | Verb for Create/Manage | Verb for Read/List | Verb for Data Sources |
|---|---|---|---|
| `vcns`, `subnets`, `security-lists`, `route-tables`, `internet-gateways`, `nat-gateways`, `service-gateways`, `dhcp-options` | `manage` | `read` | `read` |
| `clusters` | `manage` (create, addons) | `read` (list) | `use` (kubeconfig) |
| `cluster-node-pools` | `manage` | `read` | `read` |
| `instances` | `manage` | `read` | `read` |
| `instance-images` | `manage` (import) | `read` (list) | `read` |
| `instance-configurations`, `instance-pools`, `cluster-networks` | `manage` | `read` | N/A |
| `compute-capacity-reports` | `manage` | N/A | N/A |
| `autonomous-databases` | `manage` (create) | `read` |
| `file-systems`, `mount-targets`, `export-sets` | `manage` | `read` | `read` |
| `buckets` | `manage` (create) | `read` | `read` |
| `objects` | `use` (put) | `read` (get) | `inspect` (list) |
| `objectstorage-namespaces` | N/A | `read` | `read` |
| `dynamic-groups`, `policies` | `manage` | `read` | `read` |
| `users` (for customer-secret-keys) | `manage` | N/A | N/A |
| `volume-attachments`, `volumes` | `manage` | `read` | N/A |

**Key tenancy-scoped policies (cannot be compartment-scoped):**
- `inspect all-resources in tenancy` — required for `GetNodePoolOptions` API
- `manage volumes in tenancy where request.principal.type = 'cluster'` — OKE persistent volume provisioning
- `manage volume-attachments in tenancy where request.principal.type = 'cluster'` — OKE volume attachment
- `manage dynamic-groups in tenancy` — dynamic groups are tenancy-level resources
- `manage policies in tenancy` — policies are tenancy-level resources
