#!/bin/bash
# -----------------------------------------------------------------------------
# Local Kubernetes Testing with Multipass
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Local Kubernetes Testing (Multipass)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    if ! command -v multipass &> /dev/null; then
        echo -e "${RED}Error: Multipass is not installed${NC}"
        echo ""
        echo "Install with:"
        echo "  macOS:   brew install multipass"
        echo "  Linux:   snap install multipass"
        echo "  Windows: choco install multipass"
        echo ""
        echo "Or visit: https://multipass.run/"
        exit 1
    fi

    if ! command -v ansible-playbook &> /dev/null; then
        echo -e "${RED}Error: Ansible is not installed${NC}"
        echo "Install with: pip3 install ansible"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is not installed${NC}"
        echo "Install with:"
        echo "  macOS: brew install jq"
        echo "  Linux: apt-get install jq"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Prerequisites check passed"
    echo ""
}

# Create VMs
create_vms() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step 1: Creating Multipass VMs${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    cd "${SCRIPT_DIR}"
    ./setup-vms.sh
    echo ""
}

# Check and apply NAT rules (macOS only)
check_nat() {
    if [ "$(uname -s)" = "Darwin" ]; then
        echo -e "${YELLOW}Checking NAT rules...${NC}"
        if ! sudo pfctl -s nat 2>/dev/null | grep -q "192.168.73.0/24"; then
            echo -e "${YELLOW}NAT rules not found. Applying NAT configuration...${NC}"
            if [ -f "${SCRIPT_DIR}/fix-nat.sh" ]; then
                sudo "${SCRIPT_DIR}/fix-nat.sh"
                echo -e "${GREEN}✓${NC} NAT rules applied"
            else
                echo -e "${RED}Error: fix-nat.sh not found${NC}"
                echo "Please run: sudo ./fix-nat.sh"
                exit 1
            fi
        else
            echo -e "${GREEN}✓${NC} NAT rules already active"
        fi
        echo ""
    fi
}

# Generate inventory
generate_inventory() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step 2: Generating Ansible Inventory${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    cd "${SCRIPT_DIR}"
    ./generate-inventory.sh
    echo ""
}

# Test connectivity
test_connectivity() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step 3: Testing Connectivity${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    cd "${SCRIPT_DIR}"

    export ANSIBLE_CONFIG="${SCRIPT_DIR}/ansible.cfg"

    echo -e "${YELLOW}Testing Ansible connectivity...${NC}"
    ansible all -i inventory/hosts.yml -m ping

    echo ""
    echo -e "${GREEN}✓${NC} Connectivity test passed"
    echo ""
}

# Run Ansible playbooks
run_playbooks() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step 4: Running Ansible Playbooks${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    cd "${SCRIPT_DIR}"
    export ANSIBLE_CONFIG="${SCRIPT_DIR}/ansible.cfg"

    echo -e "${YELLOW}Running prerequisites check...${NC}"
    ansible-playbook -i inventory/hosts.yml ../ansible/playbooks/00-prerequisites.yml
    echo ""

    echo -e "${YELLOW}Running common setup...${NC}"
    ansible-playbook -i inventory/hosts.yml ../ansible/playbooks/01-common.yml
    echo ""

    echo -e "${YELLOW}Initializing control plane...${NC}"
    ansible-playbook -i inventory/hosts.yml ../ansible/playbooks/02-control-plane.yml
    echo ""

    echo -e "${YELLOW}Joining worker nodes...${NC}"
    ansible-playbook -i inventory/hosts.yml ../ansible/playbooks/03-worker-nodes.yml
    echo ""

    echo -e "${YELLOW}Waiting for all nodes to be ready...${NC}"
    echo "This may take 2-5 minutes while CNI initializes..."
    for i in {1..40}; do
        if multipass exec k8s-control-plane-01 -- kubectl get nodes --no-headers 2>/dev/null | grep -q "NotReady"; then
            echo "  Attempt $i/40: Some nodes not ready yet..."
            sleep 10
        else
            echo -e "${GREEN}✓${NC} All nodes are ready!"
            multipass exec k8s-control-plane-01 -- kubectl get nodes
            break
        fi
    done
    echo ""

    echo -e "${GREEN}✓${NC} Playbooks completed successfully"
    echo ""
}

# Install addons (separate function)
install_addons() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Installing Cluster Addons${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    cd "${SCRIPT_DIR}"
    export ANSIBLE_CONFIG="${SCRIPT_DIR}/ansible.cfg"

    echo -e "${YELLOW}Installing metrics-server and ingress-nginx...${NC}"
    if ansible-playbook -i inventory/hosts.yml ../ansible/playbooks/99-cluster-addons.yml; then
        echo -e "${GREEN}✓${NC} Addons installed successfully"
    else
        echo -e "${RED}✗${NC} Addon installation failed"
        return 1
    fi
    echo ""
}

# Verify cluster
verify_cluster() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step 5: Verifying Cluster${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo -e "${YELLOW}Cluster Nodes:${NC}"
    multipass exec k8s-control-plane-01 -- kubectl get nodes
    echo ""

    echo -e "${YELLOW}All Pods:${NC}"
    multipass exec k8s-control-plane-01 -- kubectl get pods -A
    echo ""

    echo -e "${GREEN}✓${NC} Cluster verification complete"
    echo ""
}

# SSH to control plane
ssh_control_plane() {
    echo "Connecting to control plane..."
    multipass shell k8s-control-plane-01
}

# Show status
show_status() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Multipass VMs Status${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    multipass list
    echo ""
}

# Restart VMs
restart_vms() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Restarting VMs${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if multipass list | grep -q "k8s-control-plane-01"; then
        echo -e "${YELLOW}Restarting k8s-control-plane-01...${NC}"
        multipass restart k8s-control-plane-01
    fi

    if multipass list | grep -q "k8s-worker-01"; then
        echo -e "${YELLOW}Restarting k8s-worker-01...${NC}"
        multipass restart k8s-worker-01
    fi

    echo ""
    echo -e "${GREEN}✓${NC} VMs restarted"
    echo ""
}

# Stop VMs
stop_vms() {
    echo -e "${YELLOW}Stopping VMs...${NC}"

    if multipass list | grep -q "k8s-control-plane-01.*Running"; then
        multipass stop k8s-control-plane-01
    fi

    if multipass list | grep -q "k8s-worker-01.*Running"; then
        multipass stop k8s-worker-01
    fi

    echo -e "${GREEN}✓${NC} VMs stopped"
    echo ""
}

# Start VMs
start_vms() {
    echo -e "${YELLOW}Starting VMs...${NC}"

    if multipass list | grep -q "k8s-control-plane-01"; then
        multipass start k8s-control-plane-01
    fi

    if multipass list | grep -q "k8s-worker-01"; then
        multipass start k8s-worker-01
    fi

    echo -e "${GREEN}✓${NC} VMs started"
    echo ""
}

# Destroy VMs
destroy_vms() {
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  WARNING: This will delete all VMs!${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -p "Are you sure you want to destroy the VMs? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${YELLOW}Destroying VMs...${NC}"
    cd "${SCRIPT_DIR}"

    if multipass list | grep -q "k8s-control-plane-01"; then
        multipass delete k8s-control-plane-01
    fi

    if multipass list | grep -q "k8s-worker-01"; then
        multipass delete k8s-worker-01
    fi

    multipass purge

    echo -e "${GREEN}✓${NC} VMs destroyed"
    echo ""
}

# Show help
show_help() {
    cat <<EOF
Usage: $0 {command}

Commands:
  create      Create VMs and generate inventory
  test        Run Ansible playbooks (assumes VMs exist)
  addons      Install cluster addons (metrics-server, ingress)
  verify      Verify cluster is working
  ssh         SSH to control plane
  status      Show VM status
  start       Start VMs
  stop        Stop VMs
  restart     Restart VMs
  destroy     Destroy all VMs
  all         Run all steps (create, test, verify)
  full        Run all steps including addons

Examples:
  $0 all          # Create VMs and deploy Kubernetes (no addons)
  $0 full         # Full workflow with addons
  $0 create       # Just create VMs
  $0 test         # Run playbooks on existing VMs
  $0 addons       # Install addons on existing cluster
  $0 verify       # Check cluster status
  $0 ssh          # SSH to control plane
  $0 restart      # Restart VMs (useful for network issues)
  $0 stop         # Stop VMs to save resources
  $0 start        # Start stopped VMs
  $0 destroy      # Clean up

Note: Addons (metrics-server, ingress-nginx) are optional.
      The cluster works without them. Install separately with: $0 addons

EOF
}

# Main execution
main() {
    case "${1:-help}" in
        create)
            check_prerequisites
            create_vms
            check_nat
            generate_inventory
            ;;
        test)
            check_prerequisites
            check_nat
            test_connectivity
            run_playbooks
            verify_cluster
            ;;
        addons)
            check_prerequisites
            check_nat
            install_addons
            ;;
        verify)
            verify_cluster
            ;;
        ssh)
            ssh_control_plane
            ;;
        status)
            show_status
            ;;
        start)
            start_vms
            check_nat
            ;;
        stop)
            stop_vms
            ;;
        restart)
            restart_vms
            check_nat
            ;;
        destroy)
            destroy_vms
            ;;
        all)
            check_prerequisites
            create_vms
            check_nat
            generate_inventory
            test_connectivity
            run_playbooks
            verify_cluster
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}  Local Kubernetes cluster is ready!${NC}"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo "Access the cluster:"
            echo "  $0 ssh          # SSH to control plane"
            echo "  $0 addons       # Install addons (optional)"
            echo "  $0 verify       # Check cluster status"
            echo "  $0 destroy      # Clean up VMs"
            echo ""
            ;;
        full)
            check_prerequisites
            create_vms
            check_nat
            generate_inventory
            test_connectivity
            run_playbooks
            verify_cluster
            echo ""
            echo -e "${YELLOW}Installing addons...${NC}"
            install_addons
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}  Local Kubernetes cluster with addons is ready!${NC}"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo "Access the cluster:"
            echo "  $0 ssh          # SSH to control plane"
            echo "  $0 verify       # Check cluster status"
            echo "  $0 destroy      # Clean up VMs"
            echo ""
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Error: Unknown command '$1'"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
