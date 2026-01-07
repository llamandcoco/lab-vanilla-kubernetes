#!/bin/bash
# -----------------------------------------------------------------------------
# Generate Ansible Inventory from Terragrunt Outputs
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_DIR="${SCRIPT_DIR}/../inventory"
TERRAGRUNT_DIR="$(cd "${SCRIPT_DIR}/../../aws/00-k8s" && pwd)"

echo "Generating Ansible inventory from Terragrunt outputs..."

# Extract IP addresses from Terragrunt outputs
echo "Fetching control plane IP..."
CONTROL_PLANE_IP=$(cd "${TERRAGRUNT_DIR}/03-control-plane" && terragrunt output -raw public_ip)

echo "Fetching worker node IP..."
WORKER_IP=$(cd "${TERRAGRUNT_DIR}/04-worker-nodes" && terragrunt output -raw public_ip)

# Generate inventory file
echo "Creating inventory file..."
cat > "${INVENTORY_DIR}/hosts.yml" <<EOF
---
all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/k8s-lab-key
    ansible_python_interpreter: /usr/bin/python3

control_plane:
  hosts:
    k8s-control-plane-01:
      ansible_host: ${CONTROL_PLANE_IP}

worker_nodes:
  hosts:
    k8s-worker-01:
      ansible_host: ${WORKER_IP}
EOF

echo "✓ Inventory generated successfully at ${INVENTORY_DIR}/hosts.yml"
echo ""
echo "Control Plane: ${CONTROL_PLANE_IP}"
echo "Worker Node:   ${WORKER_IP}"
echo ""
echo "Test connectivity with: ansible all -m ping"
