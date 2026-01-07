# Deployment Guide

Step-by-step guide for deploying the vanilla Kubernetes lab environment.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [SSH Key Setup](#ssh-key-setup)
3. [Infrastructure Deployment](#infrastructure-deployment)
4. [Kubernetes Deployment](#kubernetes-deployment)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

Install the following tools on your local machine:

```bash
# Terragrunt
brew install terragrunt  # macOS
# or download from https://terragrunt.gruntwork.io/docs/getting-started/install/

# Terraform (installed automatically by Terragrunt)
brew install terraform  # macOS

# AWS CLI
brew install awscli  # macOS

# Ansible
pip3 install ansible
```

### AWS Configuration

1. **Configure AWS SSO:**
   ```bash
   aws configure sso
   # Follow the prompts to set up your SSO profile
   ```

2. **Login to AWS:**
   ```bash
   export AWS_PROFILE=your-profile-name
   aws sso login
   ```

3. **Verify credentials:**
   ```bash
   aws sts get-caller-identity
   ```

---

## SSH Key Setup

### 1. Generate SSH Key Pair

```bash
# Generate a new RSA key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-lab-key -N ""

# Set appropriate permissions
chmod 600 ~/.ssh/k8s-lab-key
chmod 644 ~/.ssh/k8s-lab-key.pub
```

### 2. Import Key to AWS

```bash
# Import the public key to AWS
aws ec2 import-key-pair \
  --key-name k8s-lab-key \
  --public-key-material fileb://~/.ssh/k8s-lab-key.pub \
  --region ca-central-1

# Verify the key was imported
aws ec2 describe-key-pairs --key-names k8s-lab-key --region ca-central-1
```

---

## Infrastructure Deployment

### 1. Get Latest Ubuntu AMI

```bash
# Find the latest Ubuntu 22.04 LTS AMI for ca-central-1
AMI_ID=$(aws ec2 describe-images \
  --region ca-central-1 \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

echo "Latest Ubuntu 22.04 LTS AMI: $AMI_ID"
```

### 2. Update Terragrunt Configuration

Edit the AMI ID in the following files:

```bash
# Edit control plane configuration
vim aws/00-k8s/03-control-plane/terragrunt.hcl
# Update: ami_id = "ami-XXXXXXXXX"

# Edit worker node configuration
vim aws/00-k8s/04-worker-nodes/terragrunt.hcl
# Update: ami_id = "ami-XXXXXXXXX"
```

### 3. Deploy Infrastructure

**Option 1: Using the helper script (recommended)**

```bash
./scripts/deploy-infra.sh
```

**Option 2: Manual deployment**

```bash
# Navigate to the Terragrunt directory
cd aws/00-k8s

# Initialize all modules
terragrunt run-all init

# Plan the deployment
terragrunt run-all plan

# Apply the changes
terragrunt run-all apply

# Go back to project root
cd ../..
```

### 4. Verify Infrastructure

```bash
# Check control plane instance
cd aws/00-k8s/03-control-plane
terragrunt output

# Check worker node instance
cd ../04-worker-nodes
terragrunt output

# Note the public IP addresses
```

---

## Kubernetes Deployment

### 1. Generate Ansible Inventory

```bash
cd ansible
./scripts/generate-inventory.sh
```

This will create `inventory/hosts.yml` with the IP addresses of your EC2 instances.

### 2. Test Connectivity

```bash
# Test SSH connectivity to all nodes
ansible all -m ping

# Expected output:
# k8s-control-plane-01 | SUCCESS => {...}
# k8s-worker-01 | SUCCESS => {...}
```

If the ping fails, check:
- SSH key permissions (`chmod 600 ~/.ssh/k8s-lab-key`)
- Security group rules allow SSH from your IP
- Instances are running

### 3. Deploy Kubernetes

**Option 1: Using the helper script (recommended)**

```bash
cd ..  # Back to project root
./scripts/deploy-k8s.sh
```

**Option 2: Manual deployment**

```bash
cd ansible

# Step 1: Pre-flight checks
ansible-playbook playbooks/00-prerequisites.yml

# Step 2: Common setup (all nodes)
ansible-playbook playbooks/01-common.yml

# Step 3: Initialize control plane
ansible-playbook playbooks/02-control-plane.yml

# Step 4: Join worker nodes
ansible-playbook playbooks/03-worker-nodes.yml

# Step 5: Install cluster addons
ansible-playbook playbooks/99-cluster-addons.yml
```

### 4. Deployment Timeline

- **Prerequisites:** ~1 minute
- **Common setup:** ~5-10 minutes
- **Control plane initialization:** ~3-5 minutes
- **Worker node join:** ~2-3 minutes
- **Cluster addons:** ~2-3 minutes
- **Total:** ~15-25 minutes

---

## Verification

### 1. SSH to Control Plane

```bash
# Get the control plane IP
CONTROL_PLANE_IP=$(cd aws/00-k8s/03-control-plane && terragrunt output -raw public_ip)

# SSH to the control plane
ssh -i ~/.ssh/k8s-lab-key ubuntu@$CONTROL_PLANE_IP
```

### 2. Check Cluster Status

```bash
# Check nodes
kubectl get nodes
# Expected: 2 nodes in Ready state

# Check all pods
kubectl get pods -A
# Expected: All pods in Running state

# Check cluster info
kubectl cluster-info
```

### 3. Test Cluster Functionality

```bash
# Test metrics server
kubectl top nodes
kubectl top pods -A

# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Deploy a test application
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc nginx

# Access the test app
curl http://localhost:$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
```

### 4. Copy kubeconfig to Local Machine (Optional)

```bash
# Copy kubeconfig from control plane
scp -i ~/.ssh/k8s-lab-key ubuntu@$CONTROL_PLANE_IP:~/.kube/config ~/.kube/k8s-lab-config

# Update the server address
# Edit ~/.kube/k8s-lab-config and change:
# server: https://10.100.x.x:6443
# to:
# server: https://$CONTROL_PLANE_IP:6443

# Use the config
export KUBECONFIG=~/.kube/k8s-lab-config
kubectl get nodes
```

---

## Troubleshooting

### Infrastructure Deployment Issues

**Error: "backend not initialized"**
```bash
cd aws/00-k8s/<module-directory>
terragrunt init
```

**Error: "AWS credentials not configured"**
```bash
export AWS_PROFILE=your-profile-name
aws sso login
```

**Error: "Key pair 'k8s-lab-key' does not exist"**
```bash
# Re-import the key
aws ec2 import-key-pair \
  --key-name k8s-lab-key \
  --public-key-material fileb://~/.ssh/k8s-lab-key.pub \
  --region ca-central-1
```

### Ansible Connectivity Issues

**Error: "Permission denied (publickey)"**
```bash
# Check key permissions
chmod 600 ~/.ssh/k8s-lab-key

# Verify SSH manually
ssh -i ~/.ssh/k8s-lab-key ubuntu@<IP_ADDRESS>
```

**Error: "Connection timed out"**
- Check security group allows SSH (port 22) from your IP
- Verify instances are running: `aws ec2 describe-instances --region ca-central-1`

### Kubernetes Deployment Issues

**Error: "kubeadm init" fails**
```bash
# SSH to control plane
ssh -i ~/.ssh/k8s-lab-key ubuntu@<CONTROL_PLANE_IP>

# Check logs
sudo journalctl -xeu kubelet

# Reset and try again
sudo kubeadm reset -f
# Then re-run the Ansible playbook
```

**Error: Worker node can't join**
```bash
# On control plane, generate a new join command
kubeadm token create --print-join-command

# On worker node, use the new join command
sudo <join-command>
```

**Error: Calico pods not running**
```bash
# Check Calico status
kubectl get pods -n kube-system | grep calico

# Check logs
kubectl logs -n kube-system <calico-pod-name>

# Verify pod network CIDR matches
kubectl cluster-info dump | grep -i cidr
```

**Error: Metrics server not working**
```bash
# Check metrics server logs
kubectl logs -n kube-system deployment/metrics-server

# Verify it's patched for insecure TLS (lab environment)
kubectl get deployment metrics-server -n kube-system -o yaml | grep kubelet-insecure-tls
```

### General Debugging

```bash
# Check node status
kubectl describe node <node-name>

# Check pod logs
kubectl logs -n <namespace> <pod-name>

# Check events
kubectl get events -A --sort-by='.lastTimestamp'

# SSH to a node and check services
ssh -i ~/.ssh/k8s-lab-key ubuntu@<NODE_IP>
sudo systemctl status kubelet
sudo systemctl status containerd
```

---

## Cleanup

### Destroy Cluster

```bash
# Destroy infrastructure
cd aws/00-k8s
terragrunt run-all destroy

# Delete SSH key from AWS
aws ec2 delete-key-pair --key-name k8s-lab-key --region ca-central-1

# Clean local files (optional)
rm -f ~/.kube/k8s-lab-config
rm -f /tmp/kubeadm_join_command.sh
```

---

## Next Steps

1. **Explore Kubernetes:**
   - Deploy sample applications
   - Create services and ingress resources
   - Experiment with ConfigMaps and Secrets

2. **Add Monitoring:**
   - Install Prometheus and Grafana
   - Set up custom metrics

3. **Prepare for Phase 2:**
   - Review HA architecture
   - Plan load balancer setup
   - Study etcd clustering

---

For more information, see:
- [Architecture Documentation](architecture.md)
- [Kubernetes Official Docs](https://kubernetes.io/docs/)
- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
