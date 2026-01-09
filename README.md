# Vanilla Kubernetes on AWS

> Production-grade Kubernetes cluster deployment using Infrastructure as Code (Terragrunt + Terraform) and automated configuration management (Ansible).

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31.4-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-Automation-EE0000?logo=ansible&logoColor=white)](https://www.ansible.com/)
[![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)

## 🎯 Project Overview

A hands-on implementation of Kubernetes cluster deployment on AWS, demonstrating:
- **Infrastructure as Code** with Terragrunt/Terraform for AWS resources
- **Configuration Management** with Ansible for cluster provisioning
- **Sequential deployment** with proper dependency management
- **Automated SSH key generation** and secure credential handling
- **Local testing environment** with Multipass for cost-free experimentation

## ✨ Key Features

### Infrastructure Automation
- 🔄 **Sequential Deployment**: Dependency-aware infrastructure provisioning (SSH keys → Network → Security → EC2)
- 🔑 **Automated Key Management**: TLS provider generates and manages SSH keys with proper permissions
- 🏗️ **Modular Design**: Reusable Terraform modules from [infra-modules](https://github.com/llamandcoco/infra-modules)
- 📦 **DRY Configuration**: Terragrunt eliminates code duplication across environments

### Cluster Configuration
- ⚙️ **Kubeadm-based Setup**: Production-grade cluster initialization
- 🌐 **Calico CNI**: Network policy enforcement and pod networking
- 📊 **Metrics Server**: Resource usage monitoring
- 🚪 **NGINX Ingress**: HTTP/HTTPS routing to services
- 🔧 **Bash Automation Scripts**: Automated deployment and management

### Development Workflow
- 💻 **Local Testing**: Multipass VMs for AWS-identical playbook testing
- 🔍 **Network Interface Detection**: Dynamic interface discovery for multi-platform support (AWS/Multipass/Vagrant)
- 🎯 **Single-command Deployment**: Automated end-to-end provisioning

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS VPC                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Public Subnet (ca-central-1a/1b)                      │ │
│  │                                                         │ │
│  │  ┌──────────────────┐      ┌──────────────────┐       │ │
│  │  │  Control Plane   │      │  Worker Node     │       │ │
│  │  │   (t3.medium)    │◄────►│   (t3.medium)    │       │ │
│  │  │                  │      │                  │       │ │
│  │  │  • kube-api      │      │  • kubelet       │       │ │
│  │  │  • etcd          │      │  • container-d   │       │ │
│  │  │  • scheduler     │      │  • calico        │       │ │
│  │  │  • controller    │      │                  │       │ │
│  │  └──────────────────┘      └──────────────────┘       │ │
│  │         :6443                     :10250               │ │
│  └────────────────────────────────────────────────────────┘ │
│                           │                                  │
│                    Internet Gateway                          │
└───────────────────────────┼──────────────────────────────────┘
                            │
                      ┌─────▼─────┐
                      │  kubectl  │
                      └───────────┘
```

**Tech Stack:**
- **Container Runtime**: containerd
- **CNI**: Calico v3.27.0
- **Kubernetes**: v1.31.4
- **OS**: Ubuntu 22.04 LTS
- **Cluster Addons**: Metrics Server, NGINX Ingress Controller

> [!NOTE]
> **Why Public Subnets?**
> This is a learning/lab environment designed for quick setup and easy troubleshooting. Public subnets allow direct SSH access and kubectl connectivity without additional bastion hosts or VPN setup. Production environments should use private subnets with proper bastion/NAT configuration.

## 🚀 Quick Start

### Prerequisites

```bash
# Required tools
brew install terragrunt terraform awscli ansible

# AWS SSO login
aws sso login --profile <your-profile>
```

### Deploy to AWS

```bash
# 1. Clone repository
git clone <repository-url>
cd lab-vanilla-kubernetes

# 2. Deploy infrastructure (creates SSH keys automatically)
./scripts/deploy-infra.sh

# 3. Deploy Kubernetes cluster
./scripts/deploy-k8s.sh
```

**That's it!** Your cluster is ready in ~10 minutes.

### Access the Cluster

```bash
# Get control plane IP
cd aws/00-k8s/03-control-plane && terragrunt output public_ip

# SSH to control plane
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@<CONTROL_PLANE_IP>

# Verify cluster
kubectl get nodes
kubectl get pods -A
kubectl top nodes
```

### Local Testing (No AWS Costs)

```bash
cd local-test
./test-local.sh all  # Creates Multipass VMs, deploys K8s, verifies cluster
```

- ✅ Same Ansible playbooks as AWS
- ✅ Test changes before cloud deployment
- ✅ Complete cluster in ~10-15 minutes

> [!WARNING]
> **Multipass Limitations on ARM Macs (M1/M2/M3)**
>
> Due to networking issues with Multipass on Apple Silicon, local testing is verified only up to **worker node join**. After cluster initialization, you may encounter SSH connectivity errors:
> ```
> exec failed: ssh connection failed: 'Timeout connecting to <control-plane-ip>'
> ```
> This is a known limitation of Multipass's networking stack on ARM architecture. For production-like local testing, consider using AWS deployment instead.

## 📁 Project Structure

```
lab-vanilla-kubernetes/
├── aws/00-k8s/                    # AWS Infrastructure (Terragrunt)
│   ├── 00-ssh-key/                # SSH key pair generation
│   ├── 01-networking/             # VPC, subnets, IGW, NAT
│   ├── 02-security-groups/        # Security groups with rules
│   ├── 03-control-plane/          # Control plane EC2 instance
│   └── 04-worker-nodes/           # Worker node EC2 instance
├── ansible/                       # Cluster Configuration
│   ├── roles/
│   │   ├── common/                # Docker, containerd, kubeadm
│   │   ├── control_plane/         # Cluster initialization
│   │   └── worker/                # Node joining
│   ├── playbooks/                 # Deployment playbooks
│   └── inventory/                 # Dynamic inventory
├── scripts/
│   ├── deploy-infra.sh            # Infrastructure deployment
│   ├── deploy-k8s.sh              # Kubernetes deployment
│   └── destroy-infra.sh           # Cleanup script
└── local-test/                    # Local testing with Multipass
    └── test-local.sh              # End-to-end local deployment
```

## 💰 Cost Management

**Running Costs (24/7):**
- 2x t3.medium instances: ~$76/month
- 2x 30GB gp3 volumes: ~$2.40/month
- **Total: ~$80/month**

**Optimization:**
```bash
# Stop instances when not in use (pay only for storage: ~$2.40/month)
./scripts/destroy-infra.sh
```

## 🧹 Cleanup

```bash
# Destroy all AWS resources
./scripts/destroy-infra.sh

# Or manually
cd aws/00-k8s
terragrunt run-all destroy
```

## 📚 Learning Outcomes

This repository demonstrates practical skills in:

- Infrastructure as Code with Terragrunt/Terraform
- Kubernetes cluster bootstrapping with kubeadm
- Ansible role design and playbook organization
- AWS networking (VPC, subnets, security groups)
- Container networking with Calico CNI
- Sequential deployment with dependency management
- Shell scripting with bash for automation
- Automated SSH key management with Terraform TLS provider
- Local development environments for cost-effective testing

## 🗺️ Roadmap

- [x] Phase 1: Single control plane + worker
- [ ] Phase 2: HA control plane (3 nodes) with load balancer
- [ ] Phase 3: Persistent storage (EBS CSI driver)
- [ ] Phase 4: Observability (Prometheus/Grafana/Loki)
- [ ] Phase 5: GitOps with ArgoCD

## 📖 Documentation

- [Deployment Guide](docs/deployment.md) - Detailed step-by-step instructions
- [Architecture](docs/architecture.md) - Design decisions and technical details
- [Local Testing](docs/local-testing.md) - Multipass setup and usage

## 🔗 References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubeadm Best Practices](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Calico Documentation](https://docs.tigera.io/calico/latest/about)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/)
- [infra-modules](https://github.com/llamandcoco/infra-modules) - Reusable Terraform modules

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.
