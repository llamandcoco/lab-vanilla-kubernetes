# Architecture Documentation

Technical architecture and design decisions for the vanilla Kubernetes lab environment.

## Table of Contents

1. [Overview](#overview)
2. [Network Architecture](#network-architecture)
3. [Compute Resources](#compute-resources)
4. [Security](#security)
5. [Kubernetes Components](#kubernetes-components)
6. [Design Decisions](#design-decisions)
7. [Phase 2: HA Architecture](#phase-2-ha-architecture)

---

## Overview

This lab deploys a **vanilla Kubernetes cluster** on AWS EC2 instances in a single availability zone using public subnets for simplicity.

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Region                          │
│                      (ca-central-1)                         │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │                  VPC (10.100.0.0/16)                  │ │
│  │                                                       │ │
│  │  ┌─────────────────────────────────────────────────┐ │ │
│  │  │        Availability Zone (ca-central-1a)        │ │ │
│  │  │                                                 │ │ │
│  │  │  Public Subnet (10.100.0.0/20)                 │ │ │
│  │  │  ┌─────────────────┐  ┌────────────────┐      │ │ │
│  │  │  │  Control Plane  │  │  Worker Node   │      │ │ │
│  │  │  │  t3.medium      │  │  t3.medium     │      │ │ │
│  │  │  │  10.100.x.x     │  │  10.100.y.y    │      │ │ │
│  │  │  │  Public IP      │  │  Public IP     │      │ │ │
│  │  │  └─────────────────┘  └────────────────┘      │ │ │
│  │  │                                                 │ │ │
│  │  └─────────────────────────────────────────────────┘ │ │
│  │                                                       │ │
│  │  Internet Gateway ──────────────> Internet           │ │
│  │                                                       │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Technology Stack

| Component | Technology | Version |
|-----------|------------|---------|
| Infrastructure | Terragrunt | Latest |
| Configuration | Ansible | Latest |
| Kubernetes | kubeadm | 1.31.4 |
| Container Runtime | containerd | 1.7.13 |
| CNI Plugin | Calico | 3.27.0 |
| Metrics | metrics-server | Latest |
| Ingress | nginx-ingress | 1.10.0 |
| OS | Ubuntu Server | 22.04 LTS |

---

## Network Architecture

### VPC Configuration

- **CIDR Block:** `10.100.0.0/16`
- **DNS Support:** Enabled
- **DNS Hostnames:** Enabled
- **Availability Zones:** 1 (ca-central-1a)

### Subnets

| Type | CIDR | Auto-assign Public IP | Use |
|------|------|----------------------|-----|
| Public | 10.100.0.0/20 | Yes | All Kubernetes nodes |

**Design Decision:** Using only public subnets to avoid NAT Gateway costs (~$32/month). This is acceptable for a lab environment but **not recommended for production**.

### Internet Connectivity

- **Internet Gateway (IGW):** Attached to VPC for outbound internet access
- **NAT Gateway:** Not deployed (cost savings)
- **Route Table:** Public subnet routes `0.0.0.0/0` to IGW

### Pod Network

- **CIDR:** `192.168.0.0/16`
- **CNI:** Calico (VXLAN mode)
- **Network Policy:** Supported by Calico

---

## Compute Resources

### Instance Specifications

| Role | Instance Type | vCPUs | Memory | Storage | Public IP |
|------|---------------|-------|--------|---------|-----------|
| Control Plane | t3.medium | 2 | 4 GB | 30 GB gp3 | Yes |
| Worker Node | t3.medium | 2 | 4 GB | 30 GB gp3 | Yes |

### Instance Sizing Rationale

**Minimum Requirements:**
- **Control Plane:** 2 vCPU, 2 GB RAM (official minimum)
- **Worker Node:** 2 vCPU, 2 GB RAM

**Chosen Specs (t3.medium):**
- **vCPU:** 2 (meets minimum)
- **Memory:** 4 GB (2x minimum for better performance)
- **Storage:** 30 GB (sufficient for OS + container images + logs)

### AMI Selection

- **OS:** Ubuntu Server 22.04 LTS
- **Architecture:** amd64
- **Virtualization:** HVM with SSD
- **Rationale:**
  - LTS version with long-term support
  - Wide Kubernetes ecosystem support
  - Familiar package management (apt)
  - Good documentation

---

## Security

### Security Groups

#### Control Plane Security Group

**Inbound Rules:**

| Port | Protocol | Source | Description |
|------|----------|--------|-------------|
| 22 | TCP | 0.0.0.0/0 | SSH access |
| 6443 | TCP | 0.0.0.0/0 | Kubernetes API server |
| 2379-2380 | TCP | Worker SG | etcd server client API |
| 10250 | TCP | Worker SG | Kubelet API |
| 10257 | TCP | Self | kube-controller-manager |
| 10259 | TCP | Self | kube-scheduler |
| All | All | Self | Control plane inter-communication |
| All | All | Worker SG | Pod networking |

**Outbound Rules:**
- All traffic to 0.0.0.0/0

**Production Recommendations:**
- Restrict SSH (port 22) to specific IP ranges
- Restrict API server (6443) to known networks or use VPN
- Use AWS Systems Manager Session Manager instead of SSH

#### Worker Node Security Group

**Inbound Rules:**

| Port | Protocol | Source | Description |
|------|----------|--------|-------------|
| 22 | TCP | 0.0.0.0/0 | SSH access |
| 10250 | TCP | Control Plane SG | Kubelet API |
| 30000-32767 | TCP | 0.0.0.0/0 | NodePort Services |
| All | All | Self | Worker inter-communication |
| All | All | Control Plane SG | Pod networking |

**Outbound Rules:**
- All traffic to 0.0.0.0/0

### IAM Roles

**Instance Profile Policies:**
- `AmazonSSMManagedInstanceCore` - Enables AWS Systems Manager access

**Rationale:**
- SSM provides secure shell access without opening port 22
- Useful for troubleshooting and management
- No additional Kubernetes-specific permissions needed (vanilla deployment)

### SSH Key Management

- **Key Type:** RSA 4096-bit
- **Storage:** Local (`~/.ssh/k8s-lab-key`)
- **AWS:** Imported to EC2 Key Pairs
- **Access:** Only ubuntu user on instances

---

## Kubernetes Components

### Control Plane Components

Deployed on the control plane node:

| Component | Port | Description |
|-----------|------|-------------|
| **kube-apiserver** | 6443 | Kubernetes API server |
| **etcd** | 2379-2380 | Key-value store for cluster data |
| **kube-scheduler** | 10259 | Schedules pods to nodes |
| **kube-controller-manager** | 10257 | Manages controllers |
| **kubelet** | 10250 | Node agent |
| **kube-proxy** | | Network proxy (iptables mode) |

### Node Components

Deployed on all nodes (control plane + workers):

| Component | Description |
|-----------|-------------|
| **kubelet** | Ensures containers are running in pods |
| **kube-proxy** | Maintains network rules for services |
| **containerd** | Container runtime |

### Add-ons

| Add-on | Namespace | Purpose |
|--------|-----------|---------|
| **Calico** | kube-system | CNI for pod networking |
| **CoreDNS** | kube-system | DNS server for service discovery |
| **metrics-server** | kube-system | Resource metrics for HPA and `kubectl top` |
| **nginx-ingress** | ingress-nginx | HTTP/HTTPS ingress controller |

### CNI: Calico

**Configuration:**
- **Mode:** VXLAN overlay network
- **IP Pool:** 192.168.0.0/16
- **MTU:** Default (1500)
- **Network Policy:** Enabled

**Why Calico:**
- Production-grade CNI
- Supports network policies
- Good performance
- Widely used and well-documented
- More features than Flannel (alternative considered)

---

## Design Decisions

### 1. Public Subnets Only

**Decision:** Deploy all instances in public subnets

**Rationale:**
- Cost savings: No NAT Gateway (~$32/month)
- Simplified networking for learning
- Direct internet access for instances

**Trade-offs:**
- Less secure than private subnets
- Instances exposed to internet (mitigated by security groups)
- Not production-ready

### 2. Single Availability Zone

**Decision:** Use only one AZ (ca-central-1a)

**Rationale:**
- Simplified architecture for Phase 1
- Lower costs
- Easier to understand for learning

**Trade-offs:**
- No high availability
- Risk of complete outage if AZ fails
- Will be addressed in Phase 2

### 3. t3.medium Instance Type

**Decision:** Use t3.medium (2 vCPU, 4 GB RAM)

**Rationale:**
- 2x the minimum RAM for better performance
- Burstable performance suitable for lab workloads
- Cost-effective (~$38/month per instance)

**Alternatives Considered:**
- **t3.small (1 vCPU, 2 GB):** Too close to minimum, might struggle
- **t3.large (2 vCPU, 8 GB):** Overkill for basic lab, 2x cost

### 4. Terragrunt Over Plain Terraform

**Decision:** Use Terragrunt for infrastructure orchestration

**Rationale:**
- DRY principle: Avoid repeating backend configuration
- Dependency management between modules
- Consistent with organization's cloud-sandbox pattern
- Easier to manage multiple environments

### 5. Calico Over Flannel

**Decision:** Use Calico as the CNI plugin

**Rationale:**
- Network policy support (Flannel doesn't support this natively)
- Better performance at scale
- More production-relevant experience
- Widely used in enterprise environments

**Alternatives Considered:**
- **Flannel:** Simpler, but lacks network policies
- **Weave Net:** Good balance, but less common than Calico

### 6. kubeadm Over Manual Installation

**Decision:** Use kubeadm for cluster bootstrap

**Rationale:**
- Standard tool for Kubernetes installation
- Good balance between learning and automation
- Production-ready approach (vs. minikube, kind)
- Transferable knowledge to real deployments

### 7. Metrics Server with Insecure TLS

**Decision:** Patch metrics-server with `--kubelet-insecure-tls`

**Rationale:**
- Lab environment doesn't need strict TLS validation
- Simpler than setting up proper certificates
- Common practice in learning environments

**Production Note:** Would use proper TLS certificates in production

---

## Phase 2: HA Architecture

### Planned Changes for High Availability

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS Region (ca-central-1)              │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │                  VPC (10.100.0.0/16)                  │ │
│  │                                                       │ │
│  │  ┌──────────────────────────────────────────────┐    │ │
│  │  │         Network Load Balancer                │    │ │
│  │  │         (k8s-api:6443)                       │    │ │
│  │  └──────────────────────────────────────────────┘    │ │
│  │          │           │           │                    │ │
│  │  ┌───────┴───┐ ┌─────┴─────┐ ┌──┴──────┐            │ │
│  │  │ AZ-1a     │ │ AZ-1b     │ │ AZ-1a   │            │ │
│  │  │           │ │           │ │         │            │ │
│  │  │ Control-1 │ │ Control-2 │ │ Control-3            │ │
│  │  │ + etcd    │ │ + etcd    │ │ + etcd  │            │ │
│  │  └───────────┘ └───────────┘ └─────────┘            │ │
│  │                                                       │ │
│  │  Workers across AZs...                                │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Key Additions

1. **Network Load Balancer (NLB)**
   - Frontend for Kubernetes API (port 6443)
   - Health checks on /healthz
   - Load balance across 3 control plane nodes

2. **3 Control Plane Nodes**
   - Distribute across 2-3 availability zones
   - Stacked etcd topology (etcd on control plane nodes)
   - `--control-plane-endpoint` set to NLB DNS

3. **etcd Cluster**
   - 3-node quorum (tolerates 1 failure)
   - Automatic leader election
   - Data replication across nodes

4. **Worker Nodes**
   - Distribute across multiple AZs
   - Connect to API via NLB

### Infrastructure Changes Required

**Terragrunt:**
- Add `05-load-balancer/` module (NLB)
- Rename `03-control-plane/` to `03-control-plane-01/`
- Add `04-control-plane-02/` and `05-control-plane-03/`
- Update dependencies to include NLB

**Ansible:**
- Update `control_plane` role for HA
- First node: `kubeadm init --control-plane-endpoint=<NLB_DNS>:6443 --upload-certs`
- Additional nodes: `kubeadm join --control-plane --certificate-key <KEY>`
- Update inventory with 3 control plane hosts

**Estimated Additional Costs:**
- 2 additional t3.medium instances: ~$76/month
- Network Load Balancer: ~$16/month
- **Total HA Premium:** ~$92/month

---

## Monitoring and Observability

### Current State (Phase 1)

- **Metrics:** metrics-server for basic resource metrics
- **Logs:** Available via `kubectl logs`
- **Events:** `kubectl get events`

### Future Enhancements (Phase 3+)

- **Prometheus + Grafana:** Comprehensive monitoring
- **EFK/Loki Stack:** Centralized logging
- **Jaeger:** Distributed tracing
- **AlertManager:** Alerting and notifications

---

## Cost Analysis

### Phase 1 (Current)

**Compute:**
- 2x t3.medium (on-demand, 24/7): 2 × $0.0528/hour × 730 hours = $77.09/month

**Storage:**
- 2x 30GB gp3 volumes: 2 × 30 × $0.08 = $4.80/month

**Data Transfer:**
- Minimal (lab environment): ~$1-2/month

**Total:** ~$82-84/month

### Phase 2 (HA)

**Additional Compute:**
- 2x t3.medium: +$77/month

**Network Load Balancer:**
- NLB: $0.0225/hour × 730 = $16.43/month
- LCU charges: ~$5-10/month (estimated)

**Total:** ~$180-195/month

### Cost Optimization Options

1. **Stop instances when not in use:**
   - Only pay for storage: ~$5/month
   - Terminate instances, keep infrastructure code

2. **Use spot instances:**
   - 50-70% savings on compute
   - Risk of interruption (acceptable for lab)

3. **Downsize to t3.small:**
   - 50% compute cost reduction
   - May impact performance

4. **Use AWS Free Tier (first 12 months):**
   - 750 hours/month of t2/t3.micro
   - Not enough for t3.medium, but can offset costs

---

## References

- [Kubernetes Components](https://kubernetes.io/docs/concepts/overview/components/)
- [kubeadm HA Topology](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/)
- [Calico Documentation](https://docs.tigera.io/calico/latest/about)
- [AWS VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
