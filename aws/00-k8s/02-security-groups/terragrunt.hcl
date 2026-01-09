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
          description = "SSH from VPC only"
          from_port   = 22
          to_port     = 22
          protocol    = "tcp"
          cidr_blocks = ["10.100.0.0/16"]
        },
        {
          # Kubernetes API accessible from anywhere for kubectl access.
          # SECURITY WARNING: This exposes the API server to the internet.
          # For production: Restrict cidr_blocks below to specific IP ranges or use a VPN.
          # For this lab: Ensure strong authentication (RBAC, certificates) is in place.
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
          description = "SSH from VPC only"
          from_port   = 22
          to_port     = 22
          protocol    = "tcp"
          cidr_blocks = ["10.100.0.0/16"]
        },
        {
          description   = "kubelet from control"
          from_port     = 10250
          to_port       = 10250
          protocol      = "tcp"
          source_sg_key = "control"
        },
        {
          # NodePort services restricted to VPC for security.
          # To expose services externally, use an Ingress Controller or LoadBalancer.
          # If direct NodePort access is needed, update the cidr_blocks parameter below
          # to your specific IP range instead of the VPC CIDR.
          description = "NodePort from VPC only"
          from_port   = 30000
          to_port     = 32767
          protocol    = "tcp"
          cidr_blocks = ["10.100.0.0/16"]
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
