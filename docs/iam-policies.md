# IAM Policies for the AI Accelerator Stack

This document describes the OCI IAM policies required to deploy and operate the AI Accelerator Starter Packs. Policies are organized by deployment phase and feature.

---

## Overview

Policies can be created in two ways:

1. **Automatic (default):** Set `create_policies = true` in `terraform.tfvars`. The stack creates the required policies automatically during `terraform apply`. This requires that your OCI user has permission to manage policies in the tenancy.

2. **Manual (pre-created):** Have a tenancy administrator create the policies before deployment, then set `create_policies = false`. Use this when your deployment user does not have policy management permissions.

### Dynamic Group

All policies grant permissions to a **dynamic group** that matches the OKE cluster's instance principal. The stack creates this dynamic group automatically when `create_policies = true`.

If creating the dynamic group manually, the matching rule should be:

```
All {instance.compartment.id = '<your-compartment-ocid>'}
```

Replace `'Default'/'DynamicGroupName'` in the policy examples below with your actual identity domain and dynamic group name. Replace `Dennis-Compartment` with your compartment name. For nested compartments, use: `ParentCompartment:ChildCompartment:GrandchildCompartment`.

---

## Stack Creation Policies

These policies are required during `terraform apply` to create the OKE cluster and supporting infrastructure.

### OKE Cluster — Bring Your Own VCN

Use these policies when `network_configuration_mode = "bring_your_own"`. Since Terraform is not creating the VCN, only read permissions are needed for the network family.

```
Allow dynamic-group 'Default'/'DynamicGroupName' to inspect all-resources in tenancy
Allow dynamic-group 'Default'/'DynamicGroupName' to manage clusters in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage cluster-node-pools in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read virtual-network-family in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use subnets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use vnics in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use network-security-groups in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use private-ips in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read cluster-work-requests in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage instance-family in compartment Dennis-Compartment
```

> **Why `inspect all-resources in tenancy`?** The `GetNodePoolOptions` API — which returns available node images and shapes — is a tenancy-scoped operation. It cannot be scoped to a compartment.

### OKE Cluster — Create New VCN

Use these policies when `network_configuration_mode = "create_new"`. The broader `manage virtual-network-family` replaces the individual `use` and `read` permissions above.

```
Allow dynamic-group 'Default'/'DynamicGroupName' to inspect all-resources in tenancy
Allow dynamic-group 'Default'/'DynamicGroupName' to manage clusters in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage cluster-node-pools in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage virtual-network-family in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read cluster-work-requests in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage instance-family in compartment Dennis-Compartment
```

### OCI AI Blueprints Platform Stack

The Blueprints (Corrino) platform needs to provision its own resources on top of the existing OKE cluster. These policies are required in addition to the OKE policies above.

```
Allow dynamic-group 'Default'/'DynamicGroupName' to inspect all-resources in tenancy
Allow dynamic-group 'Default'/'DynamicGroupName' to use virtual-network-family in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage volumes in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage volume-attachments in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage load-balancers in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use clusters in compartment Dennis-Compartment
```

---

## Blueprints Feature Policies

These policies are required for specific OCI AI Blueprints platform features. The **Full Feature Policies** section below is the minimum required to use all features. If you want to restrict policies, refer to the individual feature sections to selectively enable only what you need.

### Full Feature Policies (Recommended)

```
Allow dynamic-group 'Default'/'DynamicGroupName' to manage clusters in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage cluster-node-pools in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage instance-family in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use vnics in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use subnets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read instance-images in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage compute-capacity-reports in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read cluster-work-requests in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read file-systems in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read mount-targets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read export-sets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to inspect private-ips in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read buckets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage objects in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use volumes in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage instance-configurations in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage instance-pools in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage cluster-networks in compartment Dennis-Compartment
```

---

## Feature-Specific Policies

Use the sections below to understand exactly why each permission is needed, or to enable only the features you need.

### Shared Node Pools

Required when using blueprints that provision or resize shared OKE node pools.

Reference: [OKE Policy Reference](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/contengpolicyreference.htm)

```
Allow dynamic-group 'Default'/'DynamicGroupName' to manage cluster-node-pools in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage instance-family in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use subnets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use vnics in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read instance-images in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage compute-capacity-reports in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read clusters in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read cluster-work-requests in compartment Dennis-Compartment
```

### RDMA-Enabled Cluster Networks (High-Performance GPU)

Required for blueprints that use cluster networks with RDMA-enabled GPU shapes (e.g., `BM.GPU.H100.8`, `BM.GPU4.8`).

Reference: [Compute Management Family Policy Reference](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/corepolicyreference.htm#compute-management-family)

```
Allow dynamic-group 'Default'/'DynamicGroupName' to manage instances in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use vnics in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use subnets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use network-security-groups in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read instance-images in tenancy
Allow dynamic-group 'Default'/'DynamicGroupName' to manage volume-attachments in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use volumes in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage instance-configurations in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage instance-pools in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage cluster-networks in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to use clusters in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to {CLUSTER_JOIN} in compartment Dennis-Compartment
```

### Object Storage (Read)

Required when blueprints read configuration or model files from Object Storage.

Reference: [Object Storage Policy Reference](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/objectstoragepolicyreference.htm)

```
Allow dynamic-group 'Default'/'DynamicGroupName' to read buckets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read objects in compartment Dennis-Compartment
```

### Object Storage (Read + Write)

Required when blueprints read from and write to Object Storage (e.g., storing inference results, checkpoints).

```
Allow dynamic-group 'Default'/'DynamicGroupName' to read buckets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to manage objects in compartment Dennis-Compartment
```

### Block Volume (Persistent Volume Claims)

Required for blueprints that provision OCI Block Volumes as Kubernetes Persistent Volumes. These must be tenancy-scoped due to how the OKE cluster principal mounts volumes.

Reference: [Provisioning PVCs on Block Volume](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingpersistentvolumeclaim_topic-Provisioning_PVCs_on_BV.htm)

```
Allow dynamic-group 'Default'/'DynamicGroupName' to manage volumes in tenancy where request.principal.type = 'cluster'
Allow dynamic-group 'Default'/'DynamicGroupName' to manage volume-attachments in tenancy where request.principal.type = 'cluster'
```

### File Storage (NFS)

Required when blueprints mount OCI File Storage as NFS volumes in Kubernetes pods.

Reference: [File Storage Policy Reference](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/filestoragepolicyreference.htm)

```
Allow dynamic-group 'Default'/'DynamicGroupName' to read file-systems in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read mount-targets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to read export-sets in compartment Dennis-Compartment
Allow dynamic-group 'Default'/'DynamicGroupName' to inspect private-ips in compartment Dennis-Compartment
```

> Also configure VCN security rules for NFS traffic. See [Configuring VCN Security Rules for File Storage](https://docs.oracle.com/en-us/iaas/Content/File/Tasks/securitylistsfilestorage.htm).

### Node Autoscaling

Required when blueprints autoscale the number of cluster nodes (not just pods). Pod-level autoscaling (HPA) does not require these policies.

`manage clusters` is required because the OKE Cluster Autoscaler uses `InstallAddon`, `UpdateAddon`, and `DeleteAddon` APIs which require cluster management permissions.

Reference: [OKE Policy Reference](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/contengpolicyreference.htm)

```
Allow dynamic-group 'Default'/'DynamicGroupName' to manage clusters in compartment Dennis-Compartment
```

---

## Tenancy-Scoped Policy Requirements

The following policies cannot be scoped to a compartment and must be tenancy-level:

| Policy | Reason |
|--------|--------|
| `inspect all-resources in tenancy` | `GetNodePoolOptions` API is tenancy-scoped |
| `read instance-images in tenancy` | Required for cluster network RDMA shapes |
| `manage volumes in tenancy where request.principal.type = 'cluster'` | OKE PVC provisioner requires tenancy scope |
| `manage volume-attachments in tenancy where request.principal.type = 'cluster'` | OKE volume attachment requires tenancy scope |
| `manage dynamic-groups in tenancy` | Dynamic groups are tenancy-level IAM resources |
| `manage policies in tenancy` | Policies are tenancy-level IAM resources |

---

## Verb Reference

OCI IAM verbs, from least to most permissive:

| Verb | Allowed Operations |
|------|--------------------|
| `inspect` | List resources, read metadata |
| `read` | `inspect` + read resource content |
| `use` | `read` + perform most operations (no create/delete) |
| `manage` | Full CRUD access |

When in doubt, use the least permissive verb that satisfies the API calls being made.

**Reference documentation:**
- [Core Services (VCN, Compute)](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/corepolicyreference.htm)
- [Container Engine / OKE](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/contengpolicyreference.htm)
- [Object Storage](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/objectstoragepolicyreference.htm)
- [File Storage](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/filestoragepolicyreference.htm)
- [Autonomous Database](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/adbpolicyreference.htm)
- [IAM (identity, dynamic groups, policies)](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/iampolicyreference.htm)
