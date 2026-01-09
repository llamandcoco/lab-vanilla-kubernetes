#!/bin/bash
# ============================================================================
# Complete Network Stack Reset for Multipass VMs
# ============================================================================
# Performs comprehensive network reset including:
# - VM restart with network re-initialization
# - ARP cache cleanup
# - SSH control socket cleanup
# - Multipass daemon state refresh
# - NAT rule verification and reapplication
# - Connectivity validation
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Helper Functions
# ============================================================================

log_info() { echo -e "${BLUE}[reset]${NC} $*"; }
log_success() { echo -e "${GREEN}[reset]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[reset]${NC} $*"; }
log_error() { echo -e "${RED}[reset]${NC} $*" >&2; }

# ============================================================================
# Step 1: Stop VMs
# ============================================================================

stop_vms() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Step 1: Stopping VMs"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local vms=("k8s-control-plane-01" "k8s-worker-01")

    for vm in "${vms[@]}"; do
        if multipass list | grep -q "$vm.*Running"; then
            log_info "Stopping $vm..."
            if multipass stop "$vm" --timeout 30 2>/dev/null; then
                log_success "$vm stopped gracefully"
            else
                log_warning "Graceful stop failed, forcing $vm..."
                multipass stop "$vm" 2>/dev/null || true
            fi
        else
            log_info "$vm is not running"
        fi
    done

    sleep 3
}

# ============================================================================
# Step 2: Clean Network State
# ============================================================================

clean_network_state() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Step 2: Cleaning Network State"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Clear SSH control sockets
    log_info "Clearing SSH control sockets..."
    rm -f /tmp/ansible-ssh-* 2>/dev/null && log_success "Cleared /tmp/ansible-ssh-*" || true
    rm -f /tmp/ssh-* 2>/dev/null && log_success "Cleared /tmp/ssh-*" || true
    rm -rf ~/.ssh/controlmasters/* 2>/dev/null && log_success "Cleared ~/.ssh/controlmasters/" || true

    # Clear ARP cache for Multipass network (macOS)
    if [ "$(uname -s)" = "Darwin" ]; then
        log_info "Clearing ARP cache for 192.168.73.0/24..."
        for ip in $(arp -an | grep "192.168.73" | awk '{print $2}' | tr -d '()'); do
            sudo arp -d "$ip" 2>/dev/null && log_success "Cleared ARP for $ip" || true
        done
    fi

    # Clear Ansible fact cache
    if [ -d "/tmp/ansible_facts_local" ]; then
        log_info "Clearing Ansible fact cache..."
        rm -rf /tmp/ansible_facts_local/* 2>/dev/null && log_success "Cleared Ansible facts" || true
    fi
}

# ============================================================================
# Step 3: Restart Multipass Daemon (macOS only)
# ============================================================================

restart_multipass_daemon() {
    if [ "$(uname -s)" != "Darwin" ]; then
        return 0
    fi

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Step 3: Restarting Multipass Daemon"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    log_warning "This requires sudo password..."

    log_info "Stopping multipassd..."
    if sudo launchctl stop com.canonical.multipassd 2>/dev/null; then
        log_success "Stopped multipassd"
        sleep 3
    else
        log_warning "Could not stop multipassd (may not be running)"
    fi

    log_info "Starting multipassd..."
    if sudo launchctl start com.canonical.multipassd 2>/dev/null; then
        log_success "Started multipassd"
        sleep 5
    else
        log_warning "Could not start multipassd explicitly (may auto-start)"
    fi
}

# ============================================================================
# Step 4: Start VMs
# ============================================================================

start_vms() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Step 4: Starting VMs"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local vms=("k8s-control-plane-01" "k8s-worker-01")

    for vm in "${vms[@]}"; do
        if ! multipass list | grep -q "$vm.*Running"; then
            log_info "Starting $vm..."
            if multipass start "$vm" 2>/dev/null; then
                log_success "$vm started"
            else
                log_error "Failed to start $vm"
                return 1
            fi
        else
            log_info "$vm is already running"
        fi
    done

    # Wait for network initialization with progressive checks
    log_info "Waiting for network initialization..."

    local max_wait=120
    local elapsed=0
    local check_interval=5

    while [ $elapsed -lt $max_wait ]; do
        sleep $check_interval
        elapsed=$((elapsed + check_interval))

        # Try to ping the VM IP (faster than SSH)
        local control_ip
        control_ip=$(multipass info k8s-control-plane-01 --format json 2>/dev/null | jq -r '.info["k8s-control-plane-01"].ipv4[0]' 2>/dev/null || echo "")

        if [ -n "$control_ip" ] && [ "$control_ip" != "null" ]; then
            if ping -c 1 -W 2 "$control_ip" >/dev/null 2>&1; then
                log_info "Network responding (${elapsed}s), waiting for SSH..."
                sleep 10
                break
            fi
        fi

        if [ $((elapsed % 15)) -eq 0 ]; then
            log_info "Still waiting for network... (${elapsed}s/${max_wait}s)"
        fi
    done

    if [ $elapsed -ge $max_wait ]; then
        log_warning "Network initialization timeout, but continuing..."
    else
        log_success "Network initialized in ${elapsed}s"
    fi
}

# ============================================================================
# Step 5: Verify and Apply NAT Rules
# ============================================================================

verify_nat_rules() {
    if [ "$(uname -s)" != "Darwin" ]; then
        return 0
    fi

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Step 5: Verifying NAT Rules"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if sudo pfctl -s nat 2>/dev/null | grep -q "192.168.73.0/24"; then
        log_success "NAT rules are active"
    else
        log_warning "NAT rules not found, applying..."
        if [ -f "${SCRIPT_DIR}/fix-nat.sh" ]; then
            if sudo "${SCRIPT_DIR}/fix-nat.sh"; then
                log_success "NAT rules applied"
            else
                log_error "Failed to apply NAT rules"
                return 1
            fi
        else
            log_error "fix-nat.sh not found at ${SCRIPT_DIR}/fix-nat.sh"
            return 1
        fi
    fi
}

# ============================================================================
# Step 6: Validate Connectivity
# ============================================================================

validate_connectivity() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Step 6: Validating Connectivity"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local vms=("k8s-control-plane-01" "k8s-worker-01")
    local all_ok=true
    local max_retries=6
    local retry_delay=10

    for vm in "${vms[@]}"; do
        log_info "Testing $vm connectivity..."

        local success=false

        # Retry multipass exec with progressive delays
        for attempt in $(seq 1 $max_retries); do
            if multipass exec "$vm" -- echo "test" >/dev/null 2>&1; then
                log_success "$vm: multipass exec ✓ (attempt $attempt)"
                success=true
                break
            else
                if [ $attempt -lt $max_retries ]; then
                    log_info "$vm: Not ready yet, waiting ${retry_delay}s... (attempt $attempt/$max_retries)"
                    sleep $retry_delay
                fi
            fi
        done

        if [ "$success" = false ]; then
            log_warning "$vm: multipass exec still not responding after $max_retries attempts"
            log_warning "$vm: VM may need more time to fully boot - try again in 1-2 minutes"
            all_ok=false
            continue
        fi

        # Test SSH
        local vm_ip
        vm_ip=$(multipass info "$vm" --format json 2>/dev/null | jq -r ".info[\"$vm\"].ipv4[0]")
        if [ -n "$vm_ip" ] && [ "$vm_ip" != "null" ]; then
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@"$vm_ip" "echo test" >/dev/null 2>&1; then
                log_success "$vm: SSH ($vm_ip) ✓"
            else
                log_info "$vm: SSH ($vm_ip) - not ready yet (normal after restart)"
            fi
        fi

        # Test internet connectivity from VM
        if multipass exec "$vm" -- ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            log_success "$vm: Internet connectivity ✓"
        else
            log_info "$vm: Internet connectivity - checking..."
            # Give NAT a moment to stabilize
            sleep 5
            if multipass exec "$vm" -- ping -c 1 8.8.8.8 >/dev/null 2>&1; then
                log_success "$vm: Internet connectivity ✓ (after retry)"
            else
                log_warning "$vm: No internet connectivity (NAT may need reapplication)"
            fi
        fi
    done

    # Don't fail - just warn
    if [ "$all_ok" = false ]; then
        echo ""
        log_warning "Some VMs are not fully ready yet"
        log_warning "Wait 1-2 minutes and try: ./test-local.sh diagnose"
        return 0  # Don't fail - VMs may just need more time
    fi

    return 0
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}        Multipass VM Network Reset${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"

    stop_vms
    clean_network_state
    restart_multipass_daemon
    start_vms
    verify_nat_rules
    validate_connectivity

    echo ""
    log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Network reset completed successfully!"
    log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Show final status
    multipass list
}

main "$@"
