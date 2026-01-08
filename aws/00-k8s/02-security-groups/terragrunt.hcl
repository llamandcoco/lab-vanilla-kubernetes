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

dependencies {
  paths = ["../01-networking"]
}

dependency "networking" {
  config_path = "../01-networking"

  mock_outputs = {
    vpc_id = "vpc-12345678"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
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
  vpc_id      = var.vpc_id

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

# Control Plane Ingress Rules
resource "aws_security_group_rule" "control_plane_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "SSH access"
  security_group_id = aws_security_group.control_plane.id
}

resource "aws_security_group_rule" "control_plane_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Kubernetes API server"
  security_group_id = aws_security_group.control_plane.id
}

resource "aws_security_group_rule" "control_plane_etcd_from_worker" {
  type                     = "ingress"
  from_port                = 2379
  to_port                  = 2380
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker.id
  description              = "etcd from workers"
  security_group_id        = aws_security_group.control_plane.id
}

resource "aws_security_group_rule" "control_plane_kubelet_from_worker" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker.id
  description              = "Kubelet from workers"
  security_group_id        = aws_security_group.control_plane.id
}

resource "aws_security_group_rule" "control_plane_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  description       = "Internal control plane communication"
  security_group_id = aws_security_group.control_plane.id
}

resource "aws_security_group_rule" "control_plane_from_worker_all" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.worker.id
  description              = "Pod networking from workers"
  security_group_id        = aws_security_group.control_plane.id
}

# Worker Node Security Group
resource "aws_security_group" "worker" {
  name        = "laco-k8s-worker-sg"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = var.vpc_id

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

# Worker Ingress Rules
resource "aws_security_group_rule" "worker_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "SSH access"
  security_group_id = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_kubelet_from_control_plane" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.control_plane.id
  description              = "Kubelet from control plane"
  security_group_id        = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_nodeport" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "NodePort Services"
  security_group_id = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  description       = "Internal worker communication"
  security_group_id = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_from_control_plane_all" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.control_plane.id
  description              = "Pod networking from control plane"
  security_group_id        = aws_security_group.worker.id
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

generate "variables" {
  path      = "variables.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
variable "vpc_id" {
  description = "VPC ID from networking module"
  type        = string
}
EOF
}

inputs = {
  vpc_id = dependency.networking.outputs.vpc_id
}
