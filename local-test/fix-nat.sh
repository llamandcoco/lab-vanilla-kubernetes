#!/bin/bash
# Fix Multipass NAT routing on macOS

set -e

echo "Fixing Multipass NAT routing..."
echo ""

# Get primary network interface
PRIMARY_IF=$(route -n get default | grep interface | awk '{print $2}')
echo "Primary interface: $PRIMARY_IF"

# Enable IP forwarding
echo "Enabling IP forwarding..."
sudo sysctl -w net.inet.ip.forwarding=1

# Create pf NAT rule
echo "Creating NAT rule for bridge100 → $PRIMARY_IF..."

# Create temporary pf config
cat > /tmp/multipass-nat.conf <<EOF
# NAT for Multipass VMs
nat on $PRIMARY_IF from 192.168.73.0/24 to any -> ($PRIMARY_IF)
pass from {lo0, 192.168.73.0/24} to any keep state
EOF

# Load the NAT rule
echo "Loading NAT rules..."
sudo pfctl -f /tmp/multipass-nat.conf -e 2>/dev/null || sudo pfctl -f /tmp/multipass-nat.conf

echo ""
echo "✓ NAT rules applied!"
echo ""
echo "Verify with:"
echo "  sudo pfctl -s nat"
echo ""
echo "Test VM internet:"
echo "  multipass exec k8s-control-plane-01 -- curl -I http://google.com"
echo ""
