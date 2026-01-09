#!/bin/bash
# -----------------------------------------------------------------------------
# Detect primary network interface for Kubernetes API server
# -----------------------------------------------------------------------------
# This script dynamically detects the correct network interface to use for
# kubeadm initialization, supporting multiple VM providers (Vagrant, Multipass, AWS)
#
# Strategy:
# 1. If internal_ip variable provided, find interface with that IP
# 2. Use default route interface
# 3. Fallback to first non-loopback interface with IP
#
# Usage:
#   detect-network-interface.sh [internal_ip]
#
# Returns: interface name (e.g., eth0, ens33, enp0s1)
# -----------------------------------------------------------------------------

set -e

TARGET_IP="$1"

# Strategy 1: If internal_ip provided, find interface with that IP
if [ -n "$TARGET_IP" ]; then
    INTERFACE=$(ip -4 addr show | grep "inet ${TARGET_IP}" | awk '{print $NF}' | head -1)
    if [ -n "$INTERFACE" ]; then
        echo "$INTERFACE"
        exit 0
    fi
fi

# Strategy 2: Use default route interface
DEFAULT_INTERFACE=$(ip route | grep '^default' | awk '{print $5}' | head -1)
if [ -n "$DEFAULT_INTERFACE" ]; then
    # Verify it has an IPv4 address
    if ip -4 addr show "$DEFAULT_INTERFACE" | grep -q 'inet '; then
        echo "$DEFAULT_INTERFACE"
        exit 0
    fi
fi

# Strategy 3: Fallback - first non-loopback interface with IPv4
FALLBACK_INTERFACE=$(ip -4 addr show | grep -v 'lo' | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $NF}' | head -1)
if [ -n "$FALLBACK_INTERFACE" ]; then
    echo "$FALLBACK_INTERFACE"
    exit 0
fi

# No suitable interface found
echo "ERROR: Could not detect network interface" >&2
echo "ERROR: Tried:" >&2
[ -n "$TARGET_IP" ] && echo "ERROR:   - Interface with IP $TARGET_IP" >&2
echo "ERROR:   - Default route interface" >&2
echo "ERROR:   - First non-loopback interface" >&2
exit 1
