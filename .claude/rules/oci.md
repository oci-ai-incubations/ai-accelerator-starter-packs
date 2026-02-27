# OCI Rules

- Default region for testing: `us-sanjose-1`.
- Always set `OCI_CLI_PROFILE` before OCI CLI commands (common profiles: `SANJOSE`, `DEFAULT`).
- ORM stacks need zips with TF files at the root level, not nested in a subdirectory.
- When ORM destroy fails on k8s provider, try updating stack to terraform 1.5.x and retry.
- Customer secret keys have a quota of 2 per user — if creation fails with quota error, an existing key must be deleted first.
- For kubectl configuration, use `--kube-endpoint PUBLIC_ENDPOINT` with the OKE cluster.
