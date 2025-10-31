#!/bin/bash
# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.

# Bastion Bootstrap Script

# Update system
sudo dnf update -y

# Install useful tools
sudo dnf install -y wget curl git vim tmux htop

# Configure SSH for easier access to operator
cat >> /home/opc/.ssh/config << 'EOF'
Host operator
    HostName ${operator_private_ip}
    User opc
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

# Set proper permissions
chmod 600 /home/opc/.ssh/config
chown opc:opc /home/opc/.ssh/config

# Create welcome message
cat > /etc/motd << 'EOF'
===============================================
    AI Accelerator Bastion Host
===============================================

This bastion host provides secure access to:
- Operator instance (private subnet)
- OKE worker nodes (private subnet)

To connect to the operator instance:
  ssh operator

===============================================
EOF

# Log completion
echo "$(date): Bastion bootstrap completed" >> /var/log/bootstrap.log
