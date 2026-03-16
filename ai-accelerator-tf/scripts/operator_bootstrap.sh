#!/bin/bash
# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.

# Operator Bootstrap Script

# Install useful tools (skip dnf update - it can take hours and is not needed)
sudo dnf install -y wget curl git vim tmux htop python3 python3-pip

# Install OCI CLI
sudo dnf -y install oraclelinux-developer-release-el8
sudo dnf -y install python36-oci-cli

# Add OCI CLI to PATH for all users
echo 'export PATH=$PATH:/home/opc/bin' >> /etc/profile
echo 'export PATH=$PATH:/home/opc/bin' >> /home/opc/.bashrc

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Create OCI config directory
sudo -u opc mkdir -p /home/opc/.oci

# Create kubeconfig directory
sudo -u opc mkdir -p /home/opc/.kube

# Create script to configure OKE access
cat > /home/opc/configure_oke.sh << 'EOF'
#!/bin/bash
# Configure OKE access

echo "Configuring OKE cluster access..."

# Get kubeconfig
oci --auth instance_principal ce cluster create-kubeconfig \
    --cluster-id ${cluster_id} \
    --file /home/opc/.kube/config \
    --region ${region} \
    --token-version 2.0.0

# Modify kubeconfig to add --auth instance_principal arguments
python3 << 'PYTHON_EOF'
import yaml
import sys

try:
    # Read the kubeconfig file
    with open('/home/opc/.kube/config', 'r') as f:
        config = yaml.safe_load(f)
    
    # Find the user with exec configuration and modify args
    for user in config.get('users', []):
        if 'exec' in user.get('user', {}):
            exec_config = user['user']['exec']
            if exec_config.get('command') == 'oci':
                # Insert --auth instance_principal at the beginning of args
                current_args = exec_config.get('args', [])
                new_args = ['--auth', 'instance_principal'] + current_args
                exec_config['args'] = new_args
    
    # Write the modified config back
    with open('/home/opc/.kube/config', 'w') as f:
        yaml.dump(config, f, default_flow_style=False)
    
    print("Successfully updated kubeconfig with instance principal authentication")
    
except Exception as e:
    print(f"Error updating kubeconfig: {e}")
    sys.exit(1)
PYTHON_EOF

# Set proper permissions
chmod 600 /home/opc/.kube/config

echo "OKE configuration completed!"
echo "You can now use kubectl to manage your cluster:"
echo "  kubectl get nodes"
echo "  kubectl get pods --all-namespaces"
EOF

chmod +x /home/opc/configure_oke.sh
chown opc:opc /home/opc/configure_oke.sh

# Create welcome message
cat > /etc/motd << 'EOF'
===============================================
    AI Accelerator Operator Instance
===============================================

This operator instance provides management access to:
- OKE Kubernetes cluster
- OCI resources

Tools installed:
- kubectl (Kubernetes CLI)
- oci (OCI CLI)
- helm (Kubernetes package manager)

To configure OKE access:
  ./configure_oke.sh

After configuration, test with:
  kubectl get nodes

===============================================
EOF

%{ if auto_configure_oke }
# Auto-configure OKE access for operator deployment mode
echo "Auto-configuring OKE cluster access..."
MAX_RETRIES=30
for i in $(seq 1 $MAX_RETRIES); do
  if sudo -u opc bash /home/opc/configure_oke.sh 2>/dev/null; then
    echo "OKE access configured successfully"
    # Verify kubectl works
    if sudo -u opc kubectl get nodes >/dev/null 2>&1; then
      echo "kubectl verified - cluster accessible"
      break
    fi
  fi
  echo "Attempt $i/$MAX_RETRIES: Waiting for OKE cluster..."
  sleep 30
done
%{ endif }

# Log completion
echo "$(date): Operator bootstrap completed" >> /var/log/bootstrap.log
