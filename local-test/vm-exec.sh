#!/bin/bash
# ============================================================================
# Smart VM Execution Wrapper with Comprehensive Recovery
# ============================================================================
# Provides multi-method VM command execution with automatic recovery from
# network failures, connection issues, and VM state problems.
#
# Usage: ./vm-exec.sh <vm-name> <command> [args...]
# Example: ./vm-exec.sh k8s-control-plane-01 kubectl get nodes
# ============================================================================

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

# Configuration
MAX_ATTEMPTS=3
INITIAL_RETRY_DELAY=2
VM_START_TIMEOUT=60
SSH_TIMEOUT=10

# Logging functions
log_info() { echo -e "${BLUE}[vm-exec]${NC} $*"; }
log_success() { echo -e "${GREEN}[vm-exec]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[vm-exec]${NC} $*"; }
log_error() { echo -e "${RED}[vm-exec]${NC} $*" >&2; }
log_debug() { [ "${DEBUG:-0}" = "1" ] && echo -e "${GRAY}[vm-exec:debug]${NC} $*" >&2; }

# Get VM IP address
get_vm_ip() {
    local vm_name=$1
    multipass info "$vm_name" --format json 2>/dev/null | \
        jq -r ".info[\"$vm_name\"].ipv4[0]" 2>/dev/null || echo ""
}

# Check VM state
is_vm_running() {
    local vm_name=$1
    multipass list --format json 2>/dev/null | \
        jq -r ".list[] | select(.name == \"$vm_name\") | .state" 2>/dev/null | \
        grep -q "Running"
}

# Wait for VM readiness with validation
wait_for_vm_ready() {
    local vm_name=$1
    local timeout=${2:-$VM_START_TIMEOUT}
    local elapsed=0

    log_info "Waiting for $vm_name to be ready..."

    while [ $elapsed -lt $timeout ]; do
        if is_vm_running "$vm_name"; then
            sleep 3
            # Test actual connectivity
            if multipass exec "$vm_name" -- echo "ready" >/dev/null 2>&1; then
                log_success "$vm_name is ready (${elapsed}s)"
                return 0
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        [ $((elapsed % 10)) -eq 0 ] && log_debug "Still waiting... (${elapsed}s/${timeout}s)"
    done

    log_error "Timeout waiting for $vm_name (${timeout}s elapsed)"
    return 1
}

# Method 1: multipass exec (QMP/serial - most reliable when working)
try_multipass_exec() {
    local vm_name=$1
    shift
    local command="$*"

    log_debug "Trying: multipass exec"
    if multipass exec "$vm_name" -- bash -c "$command" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Method 2: Direct SSH to VM IP
try_direct_ssh() {
    local vm_name=$1
    shift
    local command="$*"

    local vm_ip
    vm_ip=$(get_vm_ip "$vm_name")

    if [ -z "$vm_ip" ] || [ "$vm_ip" = "null" ]; then
        log_debug "Cannot get IP for $vm_name"
        return 1
    fi

    log_debug "Trying: SSH to $vm_ip"
    if ssh -o ConnectTimeout=$SSH_TIMEOUT \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o LogLevel=ERROR \
           -o BatchMode=yes \
           ubuntu@"$vm_ip" "$command" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Method 3: multipass shell with command injection
try_multipass_shell() {
    local vm_name=$1
    shift
    local command="$*"

    log_debug "Trying: multipass shell"
    if echo "$command" | multipass shell "$vm_name" 2>/dev/null | tail -n +2; then
        return 0
    fi
    return 1
}

# Recovery: Restart VM gracefully
restart_vm_gracefully() {
    local vm_name=$1

    log_warning "Initiating graceful VM restart for $vm_name..."

    # Try graceful stop
    if multipass stop "$vm_name" --timeout 30 2>/dev/null; then
        log_debug "Graceful stop succeeded"
    else
        log_warning "Graceful stop failed, forcing..."
        multipass stop "$vm_name" 2>/dev/null || true
    fi

    sleep 3

    # Start VM
    if ! multipass start "$vm_name" 2>/dev/null; then
        log_error "Failed to start $vm_name"
        return 1
    fi

    # Wait for readiness
    if ! wait_for_vm_ready "$vm_name"; then
        return 1
    fi

    log_success "VM restart completed"
    return 0
}

# Recovery: Full network reset
reset_vm_network() {
    local vm_name=$1

    log_warning "Performing full network reset..."

    # Clear SSH control sockets
    rm -f /tmp/ansible-ssh-* 2>/dev/null || true
    rm -f ~/.ssh/controlmasters/* 2>/dev/null || true

    # Restart VM
    if ! restart_vm_gracefully "$vm_name"; then
        return 1
    fi

    # On macOS, verify NAT rules
    if [ "$(uname -s)" = "Darwin" ]; then
        if ! sudo pfctl -s nat 2>/dev/null | grep -q "192.168.73.0/24"; then
            log_warning "NAT rules missing, reapplying..."
            if [ -f "./fix-nat.sh" ]; then
                sudo ./fix-nat.sh >/dev/null 2>&1 || true
            fi
        fi
    fi

    log_success "Network reset completed"
    return 0
}

# Main execution with comprehensive retry logic
main() {
    if [ $# -lt 2 ]; then
        log_error "Usage: $0 <vm-name> <command> [args...]"
        exit 1
    fi

    local vm_name=$1
    shift
    local command="$*"

    # Validate VM exists
    if ! multipass list --format json 2>/dev/null | jq -r '.list[].name' | grep -q "^${vm_name}$"; then
        log_error "VM '$vm_name' does not exist"
        exit 1
    fi

    # Ensure VM is running
    if ! is_vm_running "$vm_name"; then
        log_warning "VM is not running, starting..."
        multipass start "$vm_name" 2>/dev/null || true
        wait_for_vm_ready "$vm_name" || exit 1
    fi

    # Try execution methods in order of reliability
    local methods=("try_multipass_exec" "try_direct_ssh" "try_multipass_shell")

    for attempt in $(seq 1 $MAX_ATTEMPTS); do
        if [ $attempt -gt 1 ]; then
            local delay=$((INITIAL_RETRY_DELAY * attempt))
            log_info "Retry attempt $attempt/$MAX_ATTEMPTS (waiting ${delay}s)..."
            sleep $delay
        fi

        # Try each method
        for method in "${methods[@]}"; do
            if $method "$vm_name" "$command"; then
                [ $attempt -gt 1 ] && log_success "Command succeeded on attempt $attempt using $method"
                exit 0
            fi
        done

        # Progressive recovery on failures
        if [ $attempt -lt $MAX_ATTEMPTS ]; then
            if [ $attempt -eq 1 ]; then
                restart_vm_gracefully "$vm_name" || true
            elif [ $attempt -eq 2 ]; then
                reset_vm_network "$vm_name" || true
            fi
        fi
    done

    # All attempts exhausted
    log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_error "ALL EXECUTION METHODS FAILED"
    log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_error "VM: $vm_name"
    log_error "Command: $command"
    log_error ""
    log_error "Diagnostic Information:"
    log_error "  Status: $(multipass list | grep "$vm_name" | awk '{print $2}' || echo "Unknown")"
    log_error "  IP: $(get_vm_ip "$vm_name" || echo "Cannot retrieve")"
    log_error ""
    log_error "Recovery Options:"
    log_error "  1. Run: ./test-local.sh fix-network"
    log_error "  2. Run: ./test-local.sh diagnose"
    log_error "  3. Restart VMs: multipass restart $vm_name"
    log_error "  4. Full reset: ./test-local.sh destroy && ./test-local.sh all"

    exit 1
}

main "$@"
