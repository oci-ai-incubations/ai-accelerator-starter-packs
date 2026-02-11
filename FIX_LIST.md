# TFLint Fix List

67 issues found. Organized by rule type and file. ✅ All fixed.

## 1. terraform_deprecated_lookup (Replace with bracket notation)

Replace `lookup(map, "key")` with `map["key"]`.

### network.tf

- [x] **Line 7** — `lookup(var.network_cidrs, "VCN-CIDR")` → `var.network_cidrs["VCN-CIDR"]`
- [x] **Line 19** — `lookup(var.network_cidrs, "ENDPOINT-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["ENDPOINT-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 32** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 45** — `lookup(var.network_cidrs, "LB-SUBNET-BP-CONTROL-PLANE-REGIONAL-CIDR")` → `var.network_cidrs["LB-SUBNET-BP-CONTROL-PLANE-REGIONAL-CIDR"]`
- [x] **Line 66** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 91** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 198** — `lookup(var.network_cidrs, "ENDPOINT-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["ENDPOINT-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 209** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 216** — `lookup(var.network_cidrs, "PODS-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["PODS-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 223** — `lookup(var.network_cidrs, "DB-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["DB-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 234** — `lookup(var.network_cidrs, "DB-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["DB-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 245** — `lookup(var.network_cidrs, "DB-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["DB-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 266** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 277** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 288** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 299** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 311** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 318** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 325** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 346** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 357** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 369** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 386** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 397** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 408** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 420** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 433** — `lookup(var.network_cidrs, "BASTION-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["BASTION-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 452** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 464** — `lookup(var.network_cidrs, "OPERATOR-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["OPERATOR-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 475** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 486** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 497** — `lookup(var.network_cidrs, "OPERATOR-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["OPERATOR-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 516** — `lookup(var.network_cidrs, "BASTION-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["BASTION-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 528** — `lookup(var.network_cidrs, "ENDPOINT-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["ENDPOINT-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 539** — `lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 550** — `lookup(var.network_cidrs, "ALL-CIDR")` → `var.network_cidrs["ALL-CIDR"]`
- [x] **Line 561** — `lookup(var.network_cidrs, "DB-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["DB-SUBNET-REGIONAL-CIDR"]`

### oke.tf

- [x] **Line 35** — `lookup(var.network_cidrs, "PODS-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["PODS-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 36** — `lookup(var.network_cidrs, "SERVICES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["SERVICES-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 79** — `lookup(var.network_cidrs, "PODS-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["PODS-SUBNET-REGIONAL-CIDR"]`
- [x] **Line 80** — `lookup(var.network_cidrs, "SERVICES-SUBNET-REGIONAL-CIDR")` → `var.network_cidrs["SERVICES-SUBNET-REGIONAL-CIDR"]`

### outputs.tf

- [x] **Line 53** — `lookup(var.network_cidrs, "VCN-CIDR")` → `var.network_cidrs["VCN-CIDR"]`

### providers.tf

- [x] **Line 18** — `lookup(data.oci_identity_regions.home_region.regions[0], "name")` → `data.oci_identity_regions.home_region.regions[0]["name"]`

---

## 2. terraform_unused_declarations (Remove or wire up)

### network.tf

- [x] **Line 582** — `local.udp_protocol` — Remove the local block or reference it somewhere.

### policies.tf

- [x] **Line 26** — `data "oci_identity_compartment" "oci_compartment"` — Remove or use (e.g., in a policy or output).

### postgres_db.tf

- [x] **Line 159** — `data "kubernetes_service_v1" "postgres_service"` — Remove or use.

### providers.tf

- [x] **Line 26** — `provider "oci"` with alias `"current_region"` — Remove or use in resources.

### vars.tf (unused variables)

- [x] **Line 76** — `existing_pods_subnet_id`
- [x] **Line 82** — `existing_services_subnet_id`
- [x] **Line 128** — `cluster_workers_visibility`
- [x] **Line 222** — `apps_endpoint_visibility`
- [x] **Line 308** — `ingress_hosts`
- [x] **Line 313** — `ingress_hosts_include_nip_io`
- [x] **Line 318** — `nip_io_domain`
- [x] **Line 323** — `ingress_tls`
- [x] **Line 379** — `setup_credential_provider_for_ocir`
- [x] **Line 385** — `override_hostnames`

---

## 3. terraform_typed_variables (Add variable types)

### vars.tf

- [x] **Line 233** — `tenancy_ocid` — Add type: `variable "tenancy_ocid" { type = string }`
- [x] **Line 234** — `compartment_ocid` — Add type: `variable "compartment_ocid" { type = string }`
- [x] **Line 235** — `region` — Add type: `variable "region" { type = string }`

---

## Quick reference

| Rule                          | Total | Done |
| ----------------------------- | ----- | ---- |
| terraform_deprecated_lookup   | 41    | 41   |
| terraform_unused_declarations | 20    | 20   |
| terraform_typed_variables     | 3     | 3    |

**Note:** Before removing unused variables, locals, or data sources, confirm they are not needed for future use or external references.

_To mark an item complete, change `- [ ]` to `- [x]`._
