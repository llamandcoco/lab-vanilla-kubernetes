#!/bin/bash
# -----------------------------------------------------------------------------
# Generate Ansible Inventory from Multipass VMs
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Generating inventory from Multipass VMs...${NC}"
echo ""

# Check if VMs exist
if ! multipass list | grep -q "k8s-control-plane-01"; then
    echo -e "${RED}Error: k8s-control-plane-01 VM not found${NC}"
    echo "Run ./setup-vms.sh first"
    exit 1
fi

if ! multipass list | grep -q "k8s-worker-01"; then
    echo -e "${RED}Error: k8s-worker-01 VM not found${NC}"
    echo "Run ./setup-vms.sh first"
    exit 1
fi

# Get IP addresses
echo -e "${YELLOW}Retrieving IP addresses...${NC}"
CONTROL_PLANE_IP=$(multipass info k8s-control-plane-01 --format json | jq -r '.info["k8s-control-plane-01"].ipv4[0]')
WORKER_IP=$(multipass info k8s-worker-01 --format json | jq -r '.info["k8s-worker-01"].ipv4[0]')

if [ -z "$CONTROL_PLANE_IP" ] || [ "$CONTROL_PLANE_IP" = "null" ]; then
    echo -e "${RED}Error: Could not get IP address for k8s-control-plane-01${NC}"
    exit 1
fi

if [ -z "$WORKER_IP" ] || [ "$WORKER_IP" = "null" ]; then
    echo -e "${RED}Error: Could not get IP address for k8s-worker-01${NC}"
    exit 1
fi

# Create inventory directory if it doesn't exist
mkdir -p "${SCRIPT_DIR}/inventory"

# Generate inventory file
echo -e "${YELLOW}Generating inventory file...${NC}"
cat > "${SCRIPT_DIR}/inventory/hosts.yml" <<EOF
---
all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
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

echo ""
echo -e "${GREEN}✓ Inventory generated at ${SCRIPT_DIR}/inventory/hosts.yml${NC}"
echo ""
echo "  Control Plane: ${CONTROL_PLANE_IP}"
echo "  Worker Node:   ${WORKER_IP}"
echo ""
echo "Next step: Test connectivity with 'ansible all -i inventory/hosts.yml -m ping'"
