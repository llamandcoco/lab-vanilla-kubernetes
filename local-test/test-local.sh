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
        if "${SCRIPT_DIR}/vm-exec.sh" k8s-control-plane-01 "kubectl get nodes --no-headers" 2>/dev/null | grep -q "NotReady"; then
            echo "  Attempt $i/40: Some nodes not ready yet..."
            sleep 10
        else
            echo -e "${GREEN}✓${NC} All nodes are ready!"
            "${SCRIPT_DIR}/vm-exec.sh" k8s-control-plane-01 "kubectl get nodes"
            break
        fi
    done
    echo ""

    echo -e "${GREEN}✓${NC} Playbooks completed successfully"
    echo ""
}

# ============================================================================
# Network Health and Recovery Functions
# ============================================================================

# Check network health proactively
check_network_health() {
    local quiet=${1:-false}

    [ "$quiet" = "false" ] && echo -e "${YELLOW}Checking network health...${NC}"

    local issues=0

    # Check NAT rules (macOS only)
    if [ "$(uname -s)" = "Darwin" ]; then
        if ! sudo pfctl -s nat 2>/dev/null | grep -q "192.168.73.0/24"; then
            [ "$quiet" = "false" ] && echo -e "${YELLOW}⚠${NC}  NAT rules missing"
            issues=$((issues + 1))
        fi
    fi

    # Check VM connectivity
    if ! multipass exec k8s-control-plane-01 -- echo "test" >/dev/null 2>&1; then
        [ "$quiet" = "false" ] && echo -e "${YELLOW}⚠${NC}  Control plane connectivity issue"
        issues=$((issues + 1))
    fi

    if ! multipass exec k8s-worker-01 -- echo "test" >/dev/null 2>&1; then
        [ "$quiet" = "false" ] && echo -e "${YELLOW}⚠${NC}  Worker node connectivity issue"
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        [ "$quiet" = "false" ] && echo -e "${GREEN}✓${NC} Network health: OK"
        return 0
    else
        [ "$quiet" = "false" ] && echo -e "${YELLOW}⚠${NC}  Network health: $issues issue(s) detected"
        return 1
    fi
}

# Cleanup and verify network connections at end of script
cleanup_and_verify() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Final Network Verification${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Check network health
    if check_network_health false; then
        echo -e "${GREEN}✓${NC} Network connectivity verified"
        return 0
    fi

    # Health check failed, attempt recovery
    echo -e "${YELLOW}Network issues detected. Attempting automatic recovery...${NC}"

    # Try quick fix first
    echo -e "${YELLOW}Attempting quick recovery...${NC}"

    # Restart VMs
    multipass stop k8s-control-plane-01 k8s-worker-01 2>/dev/null || true
    sleep 5
    multipass start k8s-control-plane-01 k8s-worker-01 2>/dev/null || true
    sleep 20

    # Recheck
    if check_network_health true; then
        echo -e "${GREEN}✓${NC} Network recovered after VM restart"
        return 0
    fi

    # Quick fix failed, try full network reset
    echo -e "${YELLOW}Quick recovery failed. Running full network reset...${NC}"
    if [ -f "${SCRIPT_DIR}/reset-vm-network.sh" ]; then
        if "${SCRIPT_DIR}/reset-vm-network.sh"; then
            echo -e "${GREEN}✓${NC} Network recovered after full reset"
            return 0
        fi
    fi

    # All recovery attempts failed
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}⚠  NETWORK CONNECTIVITY WARNING${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Automatic recovery was not successful.${NC}"
    echo ""
    echo "The cluster may be running, but network access is unstable."
    echo ""
    echo "Manual recovery options:"
    echo "  1. Run: ./test-local.sh fix-network"
    echo "  2. Run: ./test-local.sh diagnose (for detailed info)"
    echo "  3. Full reset: ./test-local.sh destroy && ./test-local.sh all"
    echo ""

    return 1
}

# Trap handler for cleanup on exit/error
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo -e "${YELLOW}Script interrupted or failed. Cleaning up...${NC}"
    fi
}

# Set trap for cleanup
trap cleanup_on_exit EXIT INT TERM

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
    "${SCRIPT_DIR}/vm-exec.sh" k8s-control-plane-01 "kubectl get nodes"
    echo ""

    echo -e "${YELLOW}All Pods:${NC}"
    "${SCRIPT_DIR}/vm-exec.sh" k8s-control-plane-01 "kubectl get pods -A"
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

# Fix network connectivity issues
fix_network() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Fixing Network Connectivity${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Run full network reset
    if [ -f "${SCRIPT_DIR}/reset-vm-network.sh" ]; then
        "${SCRIPT_DIR}/reset-vm-network.sh"
    else
        echo -e "${RED}Error: reset-vm-network.sh not found${NC}"
        exit 1
    fi

    echo ""
    echo "Testing connectivity..."
    "${SCRIPT_DIR}/vm-exec.sh" k8s-control-plane-01 "kubectl get nodes"
}

# Diagnose network and VM state
diagnose() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  System Diagnostics${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo -e "${YELLOW}=== Multipass VMs ===${NC}"
    multipass list
    echo ""

    echo -e "${YELLOW}=== VM IP Addresses ===${NC}"
    multipass info k8s-control-plane-01 --format json 2>/dev/null | jq -r '.info["k8s-control-plane-01"].ipv4[]' || echo "Cannot retrieve"
    multipass info k8s-worker-01 --format json 2>/dev/null | jq -r '.info["k8s-worker-01"].ipv4[]' || echo "Cannot retrieve"
    echo ""

    if [ "$(uname -s)" = "Darwin" ]; then
        echo -e "${YELLOW}=== NAT Rules (macOS) ===${NC}"
        sudo pfctl -s nat 2>/dev/null | grep "192.168.73" || echo "No NAT rules found for 192.168.73.0/24"
        echo ""

        echo -e "${YELLOW}=== ARP Cache ===${NC}"
        arp -an | grep "192.168.73" || echo "No ARP entries for 192.168.73.0/24"
        echo ""

        echo -e "${YELLOW}=== Bridge Interface ===${NC}"
        ifconfig bridge100 2>/dev/null || echo "bridge100 not found"
        echo ""
    fi

    echo -e "${YELLOW}=== SSH Control Sockets ===${NC}"
    ls -la /tmp/ansible-ssh-* 2>/dev/null || echo "No Ansible SSH control sockets"
    ls -la /tmp/ssh-* 2>/dev/null || echo "No SSH control sockets"
    echo ""

    echo -e "${YELLOW}=== Connectivity Tests ===${NC}"
    echo -n "Control plane (multipass exec): "
    if multipass exec k8s-control-plane-01 -- echo "OK" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi

    echo -n "Worker node (multipass exec): "
    if multipass exec k8s-worker-01 -- echo "OK" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi

    local cp_ip
    cp_ip=$(multipass info k8s-control-plane-01 --format json 2>/dev/null | jq -r '.info["k8s-control-plane-01"].ipv4[0]')
    if [ -n "$cp_ip" ] && [ "$cp_ip" != "null" ]; then
        echo -n "Control plane (SSH to $cp_ip): "
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@"$cp_ip" "echo OK" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
        fi
    fi
    echo ""

    echo -e "${YELLOW}=== Kubernetes Cluster Status ===${NC}"
    if multipass exec k8s-control-plane-01 -- kubectl get nodes 2>/dev/null; then
        echo ""
        multipass exec k8s-control-plane-01 -- kubectl get pods -A 2>/dev/null || true
    else
        echo -e "${RED}Cannot access Kubernetes cluster${NC}"
    fi
}

# Show help
show_help() {
    cat <<EOF
Usage: $0 {command}

Commands:
  create       Create VMs and generate inventory
  test         Run Ansible playbooks (assumes VMs exist)
  addons       Install cluster addons (metrics-server, ingress)
  verify       Verify cluster is working
  fix-network  Fix VM network connectivity issues
  diagnose     Show detailed diagnostic information
  ssh          SSH to control plane
  status       Show VM status
  start        Start VMs
  stop         Stop VMs
  restart      Restart VMs
  destroy      Destroy all VMs
  all          Run all steps (create, test, verify)
  full         Run all steps including addons

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
        fix-network)
            fix_network
            ;;
        diagnose)
            diagnose
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
            echo -e "${YELLOW}Note: ARM Mac + Multipass can have network instability.${NC}"
            echo -e "${YELLOW}If SSH timeouts occur:${NC}"
            echo "  1. Wait 1-2 minutes for VMs to stabilize"
            echo "  2. Use: ./vm-exec.sh k8s-control-plane-01 \"<command>\""
            echo "  3. Or recreate: ./test-local.sh destroy && ./test-local.sh all"
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
            echo -e "${YELLOW}Note: ARM Mac + Multipass can have network instability.${NC}"
            echo -e "${YELLOW}If SSH timeouts occur: wait or use ./vm-exec.sh wrapper${NC}"
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
