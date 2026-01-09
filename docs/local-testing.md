# Local Testing with Multipass

Guide for testing Ansible playbooks locally using Multipass VMs before deploying to AWS.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Detailed Usage](#detailed-usage)
5. [Troubleshooting](#troubleshooting)
6. [Differences from AWS](#differences-from-aws)

---

## Overview

The local testing environment allows you to:
- Test Ansible playbooks on local VMs before deploying to AWS
- Iterate quickly without AWS costs
- Validate Kubernetes setup in a safe environment
- Use the exact same Ansible roles and playbooks as AWS deployment

**Technology:** [Multipass](https://multipass.run/) - Lightweight Ubuntu VMs using native hypervisors

---

## Prerequisites

### Install Required Tools

**Multipass:**
```bash
# macOS
brew install multipass

# Linux
snap install multipass

# Windows
choco install multipass
```

**jq (for JSON parsing):**
```bash
# macOS
brew install jq

# Linux
sudo apt-get install jq

# Windows
choco install jq
```

**Ansible:**
```bash
pip3 install ansible
```

### System Requirements

- **RAM:** 8GB minimum (4GB per VM)
- **Disk:** 60GB free space (30GB per VM)
- **CPU:** 4 cores minimum (2 cores per VM)

---

## Quick Start

### Option 1: Full Automated Test

Run everything in one command:

```bash
cd local-test
./test-local.sh all
```

This will:
1. Create 2 Multipass VMs
2. Generate Ansible inventory
3. Run all playbooks
4. Verify the cluster

**Time:** ~20-30 minutes

### Option 2: Step-by-Step

```bash
cd local-test

# Create VMs and inventory
./test-local.sh create

# Run playbooks
./test-local.sh test

# Verify cluster
./test-local.sh verify
```

---

## Detailed Usage

### Creating VMs

```bash
cd local-test
./test-local.sh create
```

**What it does:**
- Creates `k8s-control-plane-01` (2 vCPU, 4GB RAM)
- Creates `k8s-worker-01` (2 vCPU, 4GB RAM)
- Sets hostnames
- Configures /etc/hosts
- Generates Ansible inventory

**Output:**
```
VMs created successfully!
  Control Plane: 10.XXX.XXX.XXX
  Worker Node:   10.XXX.XXX.XXX
```

### Running Tests

```bash
./test-local.sh test
```

**What it does:**
1. Tests Ansible connectivity
2. Runs `00-prerequisites.yml` - Pre-flight checks
3. Runs `01-common.yml` - System setup, containerd, Kubernetes packages
4. Runs `02-control-plane.yml` - Initialize control plane, Calico
5. Runs `03-worker-nodes.yml` - Join worker to cluster
6. Runs `99-cluster-addons.yml` - metrics-server, nginx-ingress

### Verifying Cluster

```bash
./test-local.sh verify
```

**Expected Output:**
```
Cluster Nodes:
NAME                    STATUS   ROLES           AGE   VERSION
k8s-control-plane-01    Ready    control-plane   10m   v1.31.4
k8s-worker-01           Ready    <none>          5m    v1.31.4

All Pods:
NAMESPACE         NAME                                       READY   STATUS
kube-system       calico-node-xxxxx                          1/1     Running
kube-system       kube-apiserver-k8s-control-plane-01        1/1     Running
...
```

### Accessing the Cluster

**SSH to control plane:**
```bash
# Using the script
./test-local.sh ssh

# Or directly
multipass shell k8s-control-plane-01
```

**Run kubectl commands:**
```bash
# From inside the VM
kubectl get nodes
kubectl get pods -A
kubectl top nodes

# Or from your machine
multipass exec k8s-control-plane-01 -- kubectl get nodes
```

### Checking VM Status

```bash
./test-local.sh status

# Or directly
multipass list
```

### Cleaning Up

```bash
./test-local.sh destroy
```

This will:
- Delete both VMs
- Purge deleted VMs
- Free up disk space

---

## Working with VMs

### Manual VM Management

```bash
# List VMs
multipass list

# Get detailed info
multipass info k8s-control-plane-01

# Stop VMs (keep data)
multipass stop k8s-control-plane-01 k8s-worker-01

# Start stopped VMs
multipass start k8s-control-plane-01 k8s-worker-01

# Restart VMs
multipass restart k8s-control-plane-01

# Execute commands
multipass exec k8s-control-plane-01 -- kubectl get nodes

# Transfer files
multipass transfer local-file.txt k8s-control-plane-01:/tmp/
multipass transfer k8s-control-plane-01:/tmp/remote-file.txt ./
```

### Iterative Development

When modifying playbooks:

```bash
# 1. Edit Ansible playbooks/roles
vim ../ansible/roles/common/tasks/main.yml

# 2. Re-run just the playbooks (VMs stay up)
./test-local.sh test

# 3. Verify changes
./test-local.sh verify

# 4. If needed, destroy and recreate
./test-local.sh destroy
./test-local.sh all
```

---

## Troubleshooting

### VMs Won't Start

**Error:** "multipass launch failed"

**Solutions:**
```bash
# Check Multipass is running
multipass version

# Restart Multipass service (macOS)
sudo launchctl unload /Library/LaunchDaemons/com.canonical.multipassd.plist
sudo launchctl load /Library/LaunchDaemons/com.canonical.multipassd.plist

# Or reinstall
brew reinstall multipass
```

### Can't Get IP Addresses

**Error:** "Could not get IP address"

**Solutions:**
```bash
# Wait a bit for VMs to initialize
sleep 30

# Check VM status
multipass list

# Restart VMs
multipass restart k8s-control-plane-01 k8s-worker-01
```

### Ansible Can't Connect

**Error:** "SSH connection failed"

**Solutions:**
```bash
# Test SSH directly
multipass exec k8s-control-plane-01 -- whoami

# Regenerate inventory
cd local-test
./generate-inventory.sh

# Check inventory
cat inventory/hosts.yml

# Test connectivity
ansible all -i inventory/hosts.yml -m ping
```

### kubeadm Init Fails

**Error:** "kubeadm init failed"

**Solutions:**
```bash
# SSH to control plane
multipass shell k8s-control-plane-01

# Check logs
sudo journalctl -xeu kubelet

# Reset and retry
sudo kubeadm reset -f

# Exit and re-run
exit
./test-local.sh test
```

### Out of Resources

**Error:** "Not enough memory"

**Solutions:**
```bash
# Reduce VM resources in setup-vms.sh
# Change --memory 4G to --memory 2G
# Change --cpus 2 to --cpus 1

# Or free up resources
multipass delete other-vms
multipass purge
```

### Stale VMs

Sometimes VMs can get into a bad state:

```bash
# Full cleanup
multipass delete --all
multipass purge

# Start fresh
./test-local.sh all
```

---

## Differences from AWS

| Aspect | AWS | Local (Multipass) |
|--------|-----|-------------------|
| **Hypervisor** | AWS Nitro | HyperKit/QEMU/Hyper-V |
| **Networking** | VPC, public subnet, IGW | NAT network (automatic) |
| **IP Addresses** | Static/DHCP | Dynamic from Multipass |
| **SSH** | Key-based (~/.ssh/k8s-lab-key) | Auto-managed by Multipass |
| **Inventory** | Generated from Terragrunt | Generated from Multipass |
| **Cost** | ~$80/month (24/7) | Free |
| **Speed** | AWS latency | Local (fast) |
| **Persistence** | EBS volumes | Local disk |

### Important Notes

1. **Same Playbooks:** Both environments use identical Ansible playbooks and roles
2. **Different Networking:** Pod IPs work the same, but VM IPs are different
3. **No Cloud Services:** No EBS, ELB, CloudWatch, etc. in local environment
4. **Performance:** Local testing is faster for iteration, but limited by your hardware

---

## Advanced Usage

### Custom VM Specs

Edit `setup-vms.sh` to customize:

```bash
# Create larger VMs
multipass launch 22.04 \
  --name k8s-control-plane-01 \
  --cpus 4 \
  --memory 8G \
  --disk 50G
```

### Testing Different Kubernetes Versions

Edit `inventory/group_vars/all.yml`:

```yaml
kubernetes_version: "1.30.0"  # Change version
kubernetes_version_short: "1.30"
```

### Adding More Worker Nodes

1. Edit `setup-vms.sh` to create `k8s-worker-02`
2. Edit `generate-inventory.sh` to add it to inventory
3. Run playbooks

### Using Cloud-init

Create a cloud-init file for automated setup:

```bash
multipass launch 22.04 \
  --name k8s-control-plane-01 \
  --cpus 2 \
  --memory 4G \
  --cloud-init cloud-init.yml
```

---

## Integration with AWS Deployment

### Workflow

```
┌──────────────────────────────┐
│ Develop Ansible Playbooks   │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Test Locally with Multipass  │
│ ./test-local.sh all          │
└──────────────┬───────────────┘
               │
               ▼
        ┌──────────────┐
        │ Tests Pass?  │
        └──┬────────┬──┘
           │ No     │ Yes
           │        │
           ▼        ▼
    ┌──────────┐  ┌──────────────────┐
    │  Debug   │  │ Deploy to AWS    │
    │  & Fix   │  │ ./scripts/       │
    │          │  │ deploy-infra.sh  │
    └──────────┘  │ deploy-k8s.sh    │
                  └──────────────────┘
```

### Best Practices

1. **Always test locally first** before deploying to AWS
2. **Use version control** for playbook changes
3. **Document any differences** between local and AWS
4. **Keep local environment clean** - destroy VMs when done
5. **Test edge cases** - failures, retries, idempotency

---

## Cost Savings

**Local Testing vs AWS:**

| Duration | AWS Cost | Local Cost | Savings |
|----------|----------|------------|---------|
| 1 hour | $0.11 | $0 | $0.11 |
| 1 day | $2.63 | $0 | $2.63 |
| 1 week | $18.41 | $0 | $18.41 |
| 1 month | $80-85 | $0 | $80-85 |

**Time Savings:**
- Local VM creation: ~2 minutes
- AWS EC2 creation: ~5 minutes
- Local iteration: Instant
- AWS iteration: Network latency

---

## Resources

- [Multipass Documentation](https://multipass.run/docs)
- [Multipass GitHub](https://github.com/canonical/multipass)
- [Ansible Documentation](https://docs.ansible.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

---

## Next Steps

After successful local testing:

1. **Deploy to AWS:** Follow the main [deployment guide](deployment.md)
2. **Compare Results:** Verify AWS deployment matches local behavior
3. **Iterate:** Make changes locally, test, then deploy to AWS
4. **Scale Up:** Add more nodes, test HA configurations

---

For questions or issues, refer to the main [README.md](../README.md) or [deployment documentation](deployment.md).
