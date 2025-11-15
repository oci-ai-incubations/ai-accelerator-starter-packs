# Helm Values Files

This directory contains the Helm values files for all the applications deployed by Terraform.

## Structure

- `ingress-nginx-values.yaml` - Configuration for the NGINX Ingress Controller
- `cert-manager-values.yaml` - Configuration for cert-manager (TLS certificate management)
- `prometheus-values.yaml` - Configuration for Prometheus monitoring
- `grafana-values.yaml` - Configuration for Grafana dashboards and datasources
- `nvidia-dcgm-values.yaml` - Configuration for NVIDIA DCGM Exporter (when enabled)

## Benefits of Using Values Files

1. **Maintainability**: Easier to read and modify configurations
2. **Version Control**: Better diff tracking for configuration changes
3. **Reusability**: Values files can be used with `helm install` directly
4. **Separation of Concerns**: Infrastructure code (Terraform) separated from application configuration (Helm values)

## Usage

These files are automatically loaded by the Terraform Helm resources. Some files use Terraform templating to inject dynamic values like:

- OCI tenancy OCID
- Region
- Namespace names
- Load balancer configurations

## Manual Helm Usage

You can also use these values files directly with Helm CLI:

```bash
# Install ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace cluster-tools \
  --values helm-values/ingress-nginx-values.yaml

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cluster-tools \
  --values helm-values/cert-manager-values.yaml

# Install prometheus
helm install prometheus prometheus-community/prometheus \
  --namespace cluster-tools \
  --values helm-values/prometheus-values.yaml

# Install grafana (requires templating for OCI values)
helm install grafana grafana/grafana \
  --namespace cluster-tools \
  --values helm-values/grafana-values.yaml \
  --set oci.tenancyOCID="your-tenancy-ocid" \
  --set oci.region="your-region"
```

