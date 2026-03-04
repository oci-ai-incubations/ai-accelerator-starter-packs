---
name: oci-cli
description: Run OCI CLI commands — list resources, check container images, manage compartments, query services.
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
argument-hint: <command description or OCI CLI command>
---

# OCI CLI

Run OCI CLI commands against the configured tenancy.

## Arguments

- `$0` - A natural language description of what to do, or a raw OCI CLI command to execute.

## Configuration

- Always set `OCI_CLI_PROFILE` before running commands. Default profile: `aiincubations`.
- Default region: `us-sanjose-1`. Override with `--region <region>` when needed.
- Test compartment: `ocid1.compartment.oc1..aaaaaaaa5rwhi5wj3grdiqzvz244gwzycpfl2ctlb4nvl7vi7wu55tqi375a`

## Common Operations

### Container Registry (OCIR)
```bash
# List repositories
OCI_CLI_PROFILE=aiincubations oci artifacts container repository list -c <compartment_ocid> --region <region>

# List image tags in a repository
OCI_CLI_PROFILE=aiincubations oci artifacts container image list -c <compartment_ocid> --repository-name <repo_name> --region <region>

# Check if a specific image tag exists
OCI_CLI_PROFILE=aiincubations oci artifacts container image list -c <compartment_ocid> --repository-name <repo_name> --display-name "<repo_name>:<tag>" --region <region>
```

### Compute
```bash
# List instances
OCI_CLI_PROFILE=aiincubations oci compute instance list -c <compartment_ocid> --region <region>

# List shapes available
OCI_CLI_PROFILE=aiincubations oci compute shape list -c <compartment_ocid> --region <region>

# Check capacity
OCI_CLI_PROFILE=aiincubations oci compute compute-capacity-report create --compartment-id <compartment_ocid> --availability-domain <ad> --shape-availabilities '[{"instanceShape": "<shape>"}]' --region <region>
```

### Resource Manager (ORM)
```bash
# List stacks
OCI_CLI_PROFILE=aiincubations oci resource-manager stack list -c <compartment_ocid> --region <region>

# Get stack details
OCI_CLI_PROFILE=aiincubations oci resource-manager stack get --stack-id <stack_ocid> --region <region>

# List jobs for a stack
OCI_CLI_PROFILE=aiincubations oci resource-manager job list -c <compartment_ocid> --stack-id <stack_ocid> --region <region>
```

### Kubernetes (OKE)
```bash
# List clusters
OCI_CLI_PROFILE=aiincubations oci ce cluster list -c <compartment_ocid> --region <region>

# Get kubeconfig
OCI_CLI_PROFILE=aiincubations oci ce cluster create-kubeconfig --cluster-id <cluster_ocid> --region <region> --kube-endpoint PUBLIC_ENDPOINT --file $HOME/.kube/config --token-version 2.0.0
```

### IAM
```bash
# List availability domains
OCI_CLI_PROFILE=aiincubations oci iam availability-domain list -c <tenancy_ocid> --region <region>

# List compartments
OCI_CLI_PROFILE=aiincubations oci iam compartment list -c <tenancy_ocid>
```

### Networking
```bash
# List VCNs
OCI_CLI_PROFILE=aiincubations oci network vcn list -c <compartment_ocid> --region <region>

# List subnets
OCI_CLI_PROFILE=aiincubations oci network subnet list -c <compartment_ocid> --region <region>
```

## Guidelines

- Always use `--query` and `--output table` for readable output when listing resources.
- Use `--all` for paginated results when needed.
- For destructive operations (delete, terminate), always confirm with the user first.
- If a command fails with auth errors, verify the OCI_CLI_PROFILE is correct.
