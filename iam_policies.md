# IAM Policies for Resource Creation and Management

Optionally, create these on deployment if you are the admin. Otherwise, these will need to be created before deployment.

## Operator Policies

dynamic-group: Instance serves as Kubernetes operator, has full access to cluster resources.
```
# operator-dg
ALL {instance.id = <operator instance ocid>}
```

policy: instance can manage cluster resources
```
# operator-policy
Allow dynamic-group 'operator_dg' to manage cluster-family in compartment id <compartment ocid>
```
