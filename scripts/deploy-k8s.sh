#!/bin/bash
# -----------------------------------------------------------------------------
# Deploy Kubernetes Cluster
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/hosts.yml"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Deploying Kubernetes Cluster${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v ansible-playbook &> /dev/null; then
    echo "Error: ansible is not installed"
    echo "Install with: pip install ansible"
    exit 1
fi

if [ ! -f ~/.ssh/k8s-lab-key.pem ]; then
    echo "Error: SSH key not found at ~/.ssh/k8s-lab-key.pem"
    echo "Create it first with the instructions in docs/deployment.md"
    exit 1
fi

# Force Ansible to use the project-local config/inventory to avoid accidentally
# picking up local-test or global defaults.
export ANSIBLE_CONFIG

echo -e "${GREEN}✓${NC} Prerequisites check passed"
echo ""

# Navigate to Ansible directory
cd "${ANSIBLE_DIR}"

# Generate inventory
echo -e "${YELLOW}Generating Ansible inventory...${NC}"
./scripts/generate-inventory.sh

echo ""
echo -e "${YELLOW}Testing connectivity...${NC}"
ansible -i "${INVENTORY_FILE}" all -m ping

echo ""
echo -e "${GREEN}✓${NC} Connectivity test passed"
echo ""

# Run playbooks
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Step 1: Pre-flight checks${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ansible-playbook -i "${INVENTORY_FILE}" playbooks/00-prerequisites.yml

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Step 2: Common setup (all nodes)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ansible-playbook -i "${INVENTORY_FILE}" playbooks/01-common.yml

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Step 3: Initialize control plane${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ansible-playbook -i "${INVENTORY_FILE}" playbooks/02-control-plane.yml

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Step 4: Join worker nodes${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ansible-playbook -i "${INVENTORY_FILE}" playbooks/03-worker-nodes.yml

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Step 5: Install cluster addons${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ansible-playbook -i "${INVENTORY_FILE}" playbooks/99-cluster-addons.yml

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Kubernetes cluster deployed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get control plane IP
CONTROL_PLANE_IP=$(grep -m1 "ansible_host:" "${INVENTORY_FILE}" | awk '{print $2}')

if [ -z "${CONTROL_PLANE_IP}" ]; then
    echo "Error: could not read control plane IP from ${INVENTORY_FILE}"
    echo "Ensure generate-inventory.sh succeeded and Terragrunt outputs are available."
    exit 1
fi

echo -e "${BLUE}Access your cluster:${NC}"
echo ""
echo "  1. SSH to control plane:"
echo "     ssh -i ~/.ssh/k8s-lab-key ubuntu@${CONTROL_PLANE_IP}"
echo ""
echo "  2. Run kubectl commands:"
echo "     kubectl get nodes"
echo "     kubectl get pods -A"
echo ""
echo "  3. Copy kubeconfig to local machine (optional):"
echo "     scp -i ~/.ssh/k8s-lab-key ubuntu@${CONTROL_PLANE_IP}:~/.kube/config ~/.kube/k8s-lab-config"
echo "     export KUBECONFIG=~/.kube/k8s-lab-config"
echo ""
