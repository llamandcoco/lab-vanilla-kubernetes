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

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/security_groups?ref=${include.env.locals.security_group_ref}"
}

locals {
  tags = include.env.locals.common_tags
}

inputs = {
  vpc_id = dependency.networking.outputs.vpc_id

  security_groups = {
    control = {
      name        = "laco-k8s-control-plane-sg"
      description = "Security group for Kubernetes control plane nodes"
      tags = merge(local.tags, {
        Component = "security-groups"
        Role      = "kubernetes-control-plane"
      })
      ingress_rules = [
        {
          # SSH open for lab convenience - allows direct access from anywhere.
          # Production: Restrict to specific IPs, use bastion host, or AWS Systems Manager.
          description = "SSH"
          from_port   = 22
          to_port     = 22
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
        },
        {
          # Kubernetes API open for kubectl access from anywhere.
          # This is intentional for lab environment convenience.
          # Production: Restrict to specific IP ranges or use a VPN.
          description = "Kubernetes API"
          from_port   = 6443
          to_port     = 6443
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
        },
        {
          description   = "etcd from workers"
          from_port     = 2379
          to_port       = 2380
          protocol      = "tcp"
          source_sg_key = "worker"
        },
        {
          description   = "kubelet from workers"
          from_port     = 10250
          to_port       = 10250
          protocol      = "tcp"
          source_sg_key = "worker"
        },
        {
          description = "control plane self"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          self        = true
        },
        {
          description   = "pods from workers"
          from_port     = 0
          to_port       = 0
          protocol      = "-1"
          source_sg_key = "worker"
        }
      ]
      egress_rules = [
        {
          description = "Allow all egress"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_blocks = ["0.0.0.0/0"]
        }
      ]
    }

    worker = {
      name        = "laco-k8s-worker-sg"
      description = "Security group for Kubernetes worker nodes"
      tags = merge(local.tags, {
        Component = "security-groups"
        Role      = "kubernetes-worker"
      })
      ingress_rules = [
        {
          # SSH open for lab convenience - allows direct access from anywhere.
          # Production: Restrict to specific IPs, use bastion host, or AWS Systems Manager.
          description = "SSH"
          from_port   = 22
          to_port     = 22
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
        },
        {
          description   = "kubelet from control"
          from_port     = 10250
          to_port       = 10250
          protocol      = "tcp"
          source_sg_key = "control"
        },
        {
          # NodePort open for lab convenience - allows testing NodePort services directly.
          # This is intentional for learning about different Kubernetes service types.
          # Production: Use Ingress Controller or LoadBalancer, restrict NodePort access.
          description = "NodePort"
          from_port   = 30000
          to_port     = 32767
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
        },
        {
          description = "worker self"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          self        = true
        },
        {
          description   = "pods from control"
          from_port     = 0
          to_port       = 0
          protocol      = "-1"
          source_sg_key = "control"
        }
      ]
      egress_rules = [
        {
          description = "Allow all egress"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_blocks = ["0.0.0.0/0"]
        }
      ]
    }
  }
}
