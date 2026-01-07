#!/bin/bash
# Check and fix VM network connectivity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Checking VM network connectivity..."

# Test VM connectivity
echo -n "  Testing gateway... "
multipass exec k8s-control-plane-01 -- ping -c 1 -W 1 192.168.73.1 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓"
else
    echo "❌"
    echo "VM cannot reach gateway"
    exit 1
fi

# Test internet connectivity (quick timeout)
echo -n "  Testing internet... "
if timeout 5 multipass exec k8s-control-plane-01 -- sh -c "curl -s --connect-timeout 2 --max-time 3 http://google.com >/dev/null 2>&1" >/dev/null 2>&1; then
    echo "✓"
    echo "Network check passed!"
    exit 0
fi

echo "❌"
echo "VM cannot reach internet - NAT issue detected"
echo "Applying NAT fix..."
cd "${SCRIPT_DIR}"
./fix-nat.sh

# Test again
echo -n "  Retesting internet... "
sleep 1
if timeout 5 multipass exec k8s-control-plane-01 -- sh -c "curl -s --connect-timeout 2 --max-time 3 http://google.com >/dev/null 2>&1" >/dev/null 2>&1; then
    echo "✓"
    echo "NAT fix applied successfully"
    echo "Network check passed!"
    exit 0
else
    echo "❌"
    echo "NAT fix failed - please check manually"
    echo "Debug: sudo pfctl -s nat"
    exit 1
fi
