# -----------------------------------------------------------------------------
# Security Groups - Kubernetes Lab
# lab-vanilla-kubernetes/aws/00-k8s/02-security-groups/terragrunt.hcl
#
# Creates security groups for Kubernetes control plane and worker nodes.
# -----------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("_env_common.hcl")
  expose = true
}

dependency "networking" {
  config_path = "../01-networking"
}

# Using Terraform directly since we need to create multiple security groups
# and reference them to each other
terraform {
  source = "."
}

# Generate a local Terraform configuration for security groups
generate "security_groups" {
  path      = "security_groups.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
# Control Plane Security Group
resource "aws_security_group" "control_plane" {
  name        = "laco-k8s-control-plane-sg"
  description = "Security group for Kubernetes control plane nodes"
  vpc_id      = "${dependency.networking.outputs.vpc_id}"

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # TODO: Restrict to your IP
  }

  # Kubernetes API server
  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # etcd server client API
  ingress {
    description     = "etcd server client API"
    from_port       = 2379
    to_port         = 2380
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  # Kubelet API
  ingress {
    description     = "Kubelet API"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  # kube-scheduler
  ingress {
    description = "kube-scheduler"
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    self        = true
  }

  # kube-controller-manager
  ingress {
    description = "kube-controller-manager"
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    self        = true
  }

  # Allow all traffic from control plane nodes
  ingress {
    description = "Internal control plane communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow all traffic from worker nodes (for pod networking)
  ingress {
    description     = "Pod networking from workers"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.worker.id]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.default_tags,
    {
      Name        = "laco-k8s-control-plane-sg"
      Environment = "k8s"
      Role        = "kubernetes-control-plane"
    }
  )
}

# Worker Node Security Group
resource "aws_security_group" "worker" {
  name        = "laco-k8s-worker-sg"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = "${dependency.networking.outputs.vpc_id}"

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # TODO: Restrict to your IP
  }

  # Kubelet API
  ingress {
    description     = "Kubelet API"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.control_plane.id]
  }

  # NodePort Services
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic from worker nodes
  ingress {
    description = "Internal worker communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow all traffic from control plane (for pod networking)
  ingress {
    description     = "Pod networking from control plane"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.control_plane.id]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.default_tags,
    {
      Name        = "laco-k8s-worker-sg"
      Environment = "k8s"
      Role        = "kubernetes-worker"
    }
  )
}

# Outputs
output "control_plane_sg_id" {
  description = "Security group ID for control plane nodes"
  value       = aws_security_group.control_plane.id
}

output "worker_sg_id" {
  description = "Security group ID for worker nodes"
  value       = aws_security_group.worker.id
}
EOF
}

inputs = {}
