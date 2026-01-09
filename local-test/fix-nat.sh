#!/bin/bash
# ============================================================================
# NAT Rule Management with Auto-Recovery for Multipass VMs
# ============================================================================
# Provides intelligent NAT rule application and monitoring for macOS Multipass
# VMs using the Packet Filter (pfctl) to enable internet connectivity.
#
# Usage:
#   ./fix-nat.sh              - Apply NAT rules once
#   ./fix-nat.sh --verify     - Verify existing rules
#   ./fix-nat.sh --monitor    - Continuously monitor and auto-reapply
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MULTIPASS_NETWORK="192.168.73.0/24"
CHECK_INTERVAL=30  # seconds between checks in monitor mode

# Logging functions
log_info() { echo -e "${BLUE}[fix-nat]${NC} $*"; }
log_success() { echo -e "${GREEN}[fix-nat]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[fix-nat]${NC} $*"; }
log_error() { echo -e "${RED}[fix-nat]${NC} $*" >&2; }

# Get primary network interface
get_primary_interface() {
    route -n get default 2>/dev/null | grep interface | awk '{print $2}' || echo ""
}

# Check if NAT rules are active
check_nat_rules() {
    if sudo pfctl -s nat 2>/dev/null | grep -q "$MULTIPASS_NETWORK"; then
        return 0
    fi
    return 1
}

# Check if packet filter is enabled
is_pf_enabled() {
    if sudo pfctl -s info 2>/dev/null | grep -q "Status: Enabled"; then
        return 0
    fi
    return 1
}

# Apply NAT rules
apply_nat_rules() {
    local primary_if
    primary_if=$(get_primary_interface)

    if [ -z "$primary_if" ]; then
        log_error "Cannot determine primary network interface"
        return 1
    fi

    log_info "Primary interface: $primary_if"

    # Enable IP forwarding
    log_info "Enabling IP forwarding..."
    if sudo sysctl -w net.inet.ip.forwarding=1 >/dev/null 2>&1; then
        log_success "IP forwarding enabled"
    else
        log_warning "Could not enable IP forwarding (may already be enabled)"
    fi

    # Create temporary pf config
    log_info "Creating NAT rule for $MULTIPASS_NETWORK → $primary_if..."

    cat > /tmp/multipass-nat.conf <<EOF
# NAT for Multipass VMs
nat on $primary_if from $MULTIPASS_NETWORK to any -> ($primary_if)
pass from {lo0, $MULTIPASS_NETWORK} to any keep state
EOF

    # Load the NAT rule
    log_info "Loading NAT rules..."
    if sudo pfctl -f /tmp/multipass-nat.conf -e 2>/dev/null; then
        log_success "NAT rules loaded and enabled"
    else
        # pfctl might already be enabled
        if sudo pfctl -f /tmp/multipass-nat.conf 2>/dev/null; then
            log_success "NAT rules loaded"
        else
            log_error "Failed to load NAT rules"
            return 1
        fi
    fi

    # Verify rules were applied
    if check_nat_rules; then
        log_success "NAT rules verified and active"
        return 0
    else
        log_error "NAT rules not found after application"
        return 1
    fi
}

# Verify NAT setup
verify_nat() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "NAT Configuration Verification"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check primary interface
    local primary_if
    primary_if=$(get_primary_interface)
    if [ -n "$primary_if" ]; then
        log_success "Primary interface: $primary_if"
    else
        log_error "Cannot determine primary interface"
        return 1
    fi

    # Check IP forwarding
    local ip_fwd
    ip_fwd=$(sysctl -n net.inet.ip.forwarding 2>/dev/null || echo "0")
    if [ "$ip_fwd" = "1" ]; then
        log_success "IP forwarding: enabled"
    else
        log_warning "IP forwarding: disabled"
    fi

    # Check pf status
    if is_pf_enabled; then
        log_success "Packet Filter: enabled"
    else
        log_warning "Packet Filter: disabled"
    fi

    # Check NAT rules
    if check_nat_rules; then
        log_success "NAT rules: active for $MULTIPASS_NETWORK"
        echo ""
        log_info "Active NAT rules:"
        sudo pfctl -s nat 2>/dev/null | grep "$MULTIPASS_NETWORK" | sed 's/^/  /'
    else
        log_error "NAT rules: not found for $MULTIPASS_NETWORK"
        return 1
    fi

    # Test VM connectivity (if VMs are running)
    echo ""
    log_info "Testing VM connectivity..."

    local test_vm="k8s-control-plane-01"
    if multipass list 2>/dev/null | grep -q "$test_vm.*Running"; then
        if multipass exec "$test_vm" -- ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            log_success "$test_vm: Internet connectivity OK"
        else
            log_warning "$test_vm: Cannot reach internet (NAT may not be working)"
            return 1
        fi
    else
        log_info "No running VMs to test"
    fi

    echo ""
    log_success "NAT configuration is correct"
    return 0
}

# Monitor and auto-reapply NAT rules
monitor_nat() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Starting NAT Monitor (checking every ${CHECK_INTERVAL}s)"
    log_info "Press Ctrl+C to stop"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Ensure rules are applied initially
    if ! check_nat_rules; then
        log_warning "NAT rules not active, applying..."
        apply_nat_rules
    fi

    local check_count=0
    local reapply_count=0

    while true; do
        sleep "$CHECK_INTERVAL"
        check_count=$((check_count + 1))

        if ! check_nat_rules; then
            log_warning "NAT rules disappeared! (check #$check_count)"
            log_info "Attempting automatic recovery..."

            if apply_nat_rules; then
                reapply_count=$((reapply_count + 1))
                log_success "Rules reapplied successfully (recovery #$reapply_count)"
            else
                log_error "Failed to reapply rules"
            fi
        else
            log_info "NAT rules OK (check #$check_count, recoveries: $reapply_count)"
        fi
    done
}

# Show usage
show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Manage NAT rules for Multipass VMs on macOS

Options:
    (none)          Apply NAT rules and exit
    --verify        Verify current NAT configuration
    --monitor       Continuously monitor and auto-reapply rules
    --help          Show this help message

Examples:
    $0                    # Apply NAT rules once
    $0 --verify           # Check if NAT is configured correctly
    $0 --monitor          # Run as monitoring daemon

Note: This script requires sudo privileges for pfctl operations.
EOF
}

# Main execution
main() {
    # Check if running on macOS
    if [ "$(uname -s)" != "Darwin" ]; then
        log_error "This script is only for macOS (Darwin)"
        exit 1
    fi

    case "${1:-apply}" in
        --verify)
            verify_nat
            ;;
        --monitor)
            monitor_nat
            ;;
        --help)
            show_usage
            exit 0
            ;;
        apply|*)
            echo ""
            log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_info "Applying NAT Rules for Multipass VMs"
            log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            if apply_nat_rules; then
                echo ""
                log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                log_success "NAT rules applied successfully!"
                log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                echo "Verify with:"
                echo "  $0 --verify"
                echo ""
                echo "Monitor continuously:"
                echo "  $0 --monitor"
                echo ""
                echo "Test VM internet:"
                echo "  multipass exec k8s-control-plane-01 -- curl -I http://google.com"
                echo ""
            else
                exit 1
            fi
            ;;
    esac
}

main "$@"
