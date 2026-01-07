#!/bin/bash
# -----------------------------------------------------------------------------
# Setup Multipass VMs for Local Kubernetes Testing (DHCP - ARM Mac Compatible)
# -----------------------------------------------------------------------------

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Detect platform and architecture
ARCH=$(uname -m)
OS=$(uname -s)
DRIVER=$(multipass get local.driver 2>/dev/null || echo "unknown")

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Creating Multipass VMs for Kubernetes Testing (DHCP)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Platform Info:${NC}"
echo "  Architecture: $ARCH"
echo "  OS: $OS"
echo "  Multipass Driver: $DRIVER"
echo ""

# Set platform-specific configurations
if [ "$ARCH" = "arm64" ] && [ "$OS" = "Darwin" ]; then
    echo -e "${YELLOW}Detected ARM Mac - Using optimized settings for QEMU${NC}"
    UBUNTU_VERSION="20.04"
    VM_CPUS="2"
    VM_MEMORY="3G"
    VM_DISK="20G"
    WAIT_TIME=30
elif [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then
    echo -e "${YELLOW}Detected AMD64 architecture - Using standard settings${NC}"
    UBUNTU_VERSION="22.04"
    VM_CPUS="2"
    VM_MEMORY="4G"
    VM_DISK="30G"
    WAIT_TIME=10
else
    echo -e "${YELLOW}Unknown architecture - Using conservative settings${NC}"
    UBUNTU_VERSION="20.04"
    VM_CPUS="2"
    VM_MEMORY="2G"
    VM_DISK="20G"
    WAIT_TIME=20
fi

echo ""

# Check if VMs already exist
if multipass list | grep -q "k8s-control-plane-01"; then
    echo -e "${YELLOW}Warning: k8s-control-plane-01 already exists${NC}"
    read -p "Do you want to delete and recreate it? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        echo "Deleting existing k8s-control-plane-01..."
        multipass delete k8s-control-plane-01
        multipass purge
    else
        echo "Keeping existing k8s-control-plane-01"
    fi
fi

if multipass list | grep -q "k8s-worker-01"; then
    echo -e "${YELLOW}Warning: k8s-worker-01 already exists${NC}"
    read -p "Do you want to delete and recreate it? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        echo "Deleting existing k8s-worker-01..."
        multipass delete k8s-worker-01
        multipass purge
    else
        echo "Keeping existing k8s-worker-01"
    fi
fi

# Create control plane VM (DHCP)
if ! multipass list | grep -q "k8s-control-plane-01"; then
    echo -e "${YELLOW}Creating control plane VM (Ubuntu $UBUNTU_VERSION, ${VM_CPUS} CPUs, ${VM_MEMORY} RAM)...${NC}"
    echo -e "${YELLOW}Using DHCP for IP assignment${NC}"

    multipass launch $UBUNTU_VERSION \
      --name k8s-control-plane-01 \
      --cpus $VM_CPUS \
      --memory $VM_MEMORY \
      --disk $VM_DISK

    echo -e "${GREEN}✓${NC} Control plane VM created"
fi

# Create worker node VM (DHCP)
if ! multipass list | grep -q "k8s-worker-01"; then
    echo -e "${YELLOW}Creating worker node VM (Ubuntu $UBUNTU_VERSION, ${VM_CPUS} CPUs, ${VM_MEMORY} RAM)...${NC}"
    echo -e "${YELLOW}Using DHCP for IP assignment${NC}"

    multipass launch $UBUNTU_VERSION \
      --name k8s-worker-01 \
      --cpus $VM_CPUS \
      --memory $VM_MEMORY \
      --disk $VM_DISK

    echo -e "${GREEN}✓${NC} Worker node VM created"
fi

# Wait for VMs to fully start
echo -e "${YELLOW}Waiting for VMs to initialize...${NC}"
sleep $WAIT_TIME

# Set hostnames
echo -e "${YELLOW}Configuring hostnames...${NC}"
multipass exec k8s-control-plane-01 -- sudo hostnamectl set-hostname k8s-control-plane-01
multipass exec k8s-worker-01 -- sudo hostnamectl set-hostname k8s-worker-01
echo -e "${GREEN}✓${NC} Hostnames configured"

# Get IP addresses
echo -e "${YELLOW}Getting IP addresses...${NC}"
CONTROL_PLANE_IP=$(multipass info k8s-control-plane-01 --format json | jq -r '.info["k8s-control-plane-01"].ipv4[0]')
WORKER_IP=$(multipass info k8s-worker-01 --format json | jq -r '.info["k8s-worker-01"].ipv4[0]')

# Update /etc/hosts in both VMs
echo -e "${YELLOW}Updating /etc/hosts...${NC}"
multipass exec k8s-control-plane-01 -- bash -c "echo '$CONTROL_PLANE_IP k8s-control-plane-01' | sudo tee -a /etc/hosts"
multipass exec k8s-control-plane-01 -- bash -c "echo '$WORKER_IP k8s-worker-01' | sudo tee -a /etc/hosts"
multipass exec k8s-worker-01 -- bash -c "echo '$CONTROL_PLANE_IP k8s-control-plane-01' | sudo tee -a /etc/hosts"
multipass exec k8s-worker-01 -- bash -c "echo '$WORKER_IP k8s-worker-01' | sudo tee -a /etc/hosts"
echo -e "${GREEN}✓${NC} /etc/hosts updated"

# Setup SSH keys for Ansible
echo -e "${YELLOW}Setting up SSH keys for Ansible...${NC}"

# Check if SSH key exists
if [ ! -f ~/.ssh/id_ed25519.pub ]; then
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        echo -e "${RED}Error: No SSH public key found${NC}"
        echo "Generate one with: ssh-keygen -t ed25519"
        exit 1
    fi
    SSH_PUB_KEY=$(cat ~/.ssh/id_rsa.pub)
else
    SSH_PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)
fi

# Copy SSH key to VMs
multipass exec k8s-control-plane-01 -- bash -c "echo '$SSH_PUB_KEY' | sudo tee -a /home/ubuntu/.ssh/authorized_keys"
multipass exec k8s-worker-01 -- bash -c "echo '$SSH_PUB_KEY' | sudo tee -a /home/ubuntu/.ssh/authorized_keys"

# Set correct permissions
multipass exec k8s-control-plane-01 -- sudo chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
multipass exec k8s-control-plane-01 -- sudo chmod 600 /home/ubuntu/.ssh/authorized_keys
multipass exec k8s-worker-01 -- sudo chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
multipass exec k8s-worker-01 -- sudo chmod 600 /home/ubuntu/.ssh/authorized_keys

echo -e "${GREEN}✓${NC} SSH keys configured"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  VMs created successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Control Plane: $CONTROL_PLANE_IP"
echo "  Worker Node:   $WORKER_IP"
echo ""

# Auto-apply NAT rules for macOS
if [ "$OS" = "Darwin" ]; then
    echo -e "${YELLOW}Please run fix-nat.sh to apply NAT rules:${NC}"
    echo "  sudo ./fix-nat.sh"
    echo ""
    echo -e "${BLUE}TIP:${NC} To avoid running fix-nat.sh every time:"
    echo "  Run ./install-nat-service.sh to install automatic NAT service"
    echo ""
fi

echo "Next step: Run ./generate-inventory.sh"
