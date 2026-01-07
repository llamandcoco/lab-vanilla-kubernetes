# labs-vanilla-kubernetes

Hands-on lab repository for deploying vanilla Kubernetes on AWS using Terragrunt and Ansible.

## Overview

This project provides infrastructure-as-code for deploying a vanilla Kubernetes cluster on AWS EC2 instances. It's designed for learning and experimentation with Kubernetes fundamentals.

**Architecture:**
- **Phase 1:** 1 control plane + 1 worker node (current)
- **Phase 2:** HA control plane with 3 nodes (planned)
- **Phase 3+:** Advanced features (storage, monitoring, service mesh)

**Technology Stack:**
- **Infrastructure:** Terragrunt + Terraform
- **Configuration Management:** Ansible
- **Kubernetes:** v1.31.4 with containerd
- **CNI:** Calico v3.27.0
- **Addons:** Metrics Server, nginx-ingress controller

## Quick Start

### Prerequisites

1. **Tools installed:**
   - [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/)
   - [Terraform](https://www.terraform.io/downloads)
   - [AWS CLI](https://aws.amazon.com/cli/)
   - [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)

2. **AWS Configuration:**
   - AWS account with appropriate permissions
   - AWS SSO configured (`aws sso login`)

3. **SSH Key:**
   ```bash
   # Generate SSH key
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-lab-key -N ""

   # Import to AWS
   aws ec2 import-key-pair \
     --key-name k8s-lab-key \
     --public-key-material fileb://~/.ssh/k8s-lab-key.pub \
     --region ca-central-1
   ```

4. **Update AMI ID:**
   ```bash
   # Find latest Ubuntu 22.04 LTS AMI
   aws ec2 describe-images \
     --region ca-central-1 \
     --owners 099720109477 \
     --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
     --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
     --output text

   # Update the ami_id in:
   # - aws/00-k8s/03-control-plane/terragrunt.hcl
   # - aws/00-k8s/04-worker-nodes/terragrunt.hcl
   ```

### Deployment

```bash
# 1. Deploy infrastructure
./scripts/deploy-infra.sh

# 2. Deploy Kubernetes
./scripts/deploy-k8s.sh
```

That's it! Your Kubernetes cluster is now ready.

## Project Structure

```
lab-vanilla-kubernetes/
├── root.hcl                    # Root Terragrunt configuration
├── aws/00-k8s/                 # AWS infrastructure
│   ├── 01-networking/          # VPC, subnets, IGW
│   ├── 02-security-groups/     # Security groups
│   ├── 03-control-plane/       # Control plane EC2
│   └── 04-worker-nodes/        # Worker node EC2
├── ansible/                    # Ansible automation
│   ├── roles/                  # Ansible roles
│   ├── playbooks/              # Playbooks
│   └── inventory/              # Inventory and variables
├── scripts/                    # Helper scripts
│   ├── deploy-infra.sh         # Infrastructure deployment
│   └── deploy-k8s.sh           # Kubernetes deployment
└── docs/                       # Documentation
    ├── deployment.md           # Detailed deployment guide
    └── architecture.md         # Architecture documentation
```

## Accessing the Cluster

### SSH Access

```bash
# Get control plane IP
cd aws/00-k8s/03-control-plane
terragrunt output public_ip

# SSH to control plane
ssh -i ~/.ssh/k8s-lab-key ubuntu@<CONTROL_PLANE_IP>
```

### kubectl Commands

```bash
# From control plane
kubectl get nodes
kubectl get pods -A
kubectl top nodes

# From local machine (after copying kubeconfig)
scp -i ~/.ssh/k8s-lab-key ubuntu@<CONTROL_PLANE_IP>:~/.kube/config ~/.kube/k8s-lab-config
export KUBECONFIG=~/.kube/k8s-lab-config
kubectl get nodes
```

## Verification

```bash
# Check nodes are Ready
kubectl get nodes

# Check all pods are Running
kubectl get pods -A

# Test metrics server
kubectl top nodes

# Test nginx-ingress
kubectl get pods -n ingress-nginx
```

## Cost Estimate

**Running 24/7:**
- 2x t3.medium instances: ~$76/month
- 2x 30GB gp3 volumes: ~$2.40/month
- Data transfer: ~$0-5/month
- **Total:** ~$80-85/month

**Cost Optimization:**
- Stop instances when not in use (only pay for storage: ~$2.40/month)
- Use spot instances (50-70% savings)
- Use t3.small instead of t3.medium

## Cleanup

```bash
# Destroy Kubernetes cluster (just the software)
cd ansible
# No cleanup needed, just destroy the infrastructure

# Destroy all infrastructure
cd ../aws/00-k8s
terragrunt run-all destroy

# Remove SSH key from AWS
aws ec2 delete-key-pair --key-name k8s-lab-key --region ca-central-1
```

## Local Testing

**NEW:** Test Ansible playbooks locally before deploying to AWS!

```bash
cd local-test
./test-local.sh all  # Create VMs, deploy Kubernetes, verify cluster
```

Uses [Multipass](https://multipass.run/) for lightweight local VMs. See [Local Testing Guide](docs/local-testing.md) for details.

**Benefits:**
- ✅ Cost-free testing (no AWS charges)
- ✅ Fast iteration (2-3 minutes to create VMs)
- ✅ Same playbooks as AWS deployment
- ✅ Safe experimentation

## Documentation

- [Local Testing Guide](docs/local-testing.md) - **NEW:** Test locally with Multipass
- [Deployment Guide](docs/deployment.md) - Detailed step-by-step instructions
- [Architecture](docs/architecture.md) - Technical architecture and design decisions

## Phase Roadmap

### Phase 1 ✅ (Current)
- Single control plane + single worker
- Basic Kubernetes functionality
- Calico CNI
- Metrics Server
- nginx-ingress controller

### Phase 2 (Planned)
- HA control plane (3 nodes)
- Network Load Balancer for API server
- etcd clustering

### Phase 3+ (Future)
- Persistent storage (EBS CSI driver)
- Monitoring (Prometheus + Grafana)
- Logging (EFK/Loki)
- GitOps (ArgoCD/Flux)
- Service mesh (Istio/Linkerd)
- Autoscaling (HPA, VPA, Cluster Autoscaler)

## Contributing

This is a learning lab repository. Feel free to experiment and modify as needed.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Calico Documentation](https://docs.tigera.io/calico/latest/about)
- [infra-modules](https://github.com/llamandcoco/infra-modules)
