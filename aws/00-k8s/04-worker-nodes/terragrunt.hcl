# -----------------------------------------------------------------------------
# Worker Node EC2 Instance - Kubernetes Lab
# lab-vanilla-kubernetes/aws/00-k8s/04-worker-nodes/terragrunt.hcl
#
# Deploys the Kubernetes worker node EC2 instance.
# NOTE: Update ami_id with the Ubuntu 22.04 LTS AMI for ca-central-1
# -----------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("_env_common.hcl")
  expose = true
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/ec2?ref=${include.env.locals.ec2_ref}"
}

dependencies {
  paths = ["../01-networking", "../02-security-groups"]
}

dependency "networking" {
  config_path = "../01-networking"

  mock_outputs = {
    public_subnet_ids = ["subnet-12345678"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "security_groups" {
  config_path = "../02-security-groups"

  mock_outputs = {
    security_group_ids = {
      control = "sg-12345678"
      worker  = "sg-87654321"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  # Instance configuration
  instance_name = "k8s-worker-01"
  ami_id        = "ami-02502825b39f7c669" # Ubuntu Server Pro 22.04 LTS (ca-central-1)
  instance_type = "t3.medium"             # 2 vCPU, 4GB RAM

  # Network configuration
  subnet_id = dependency.networking.outputs.public_subnet_ids[0]

  vpc_security_group_ids = [
    dependency.security_groups.outputs.security_group_ids["worker"]
  ]

  associate_public_ip_address = true

  # SSH key
  key_name = "k8s-lab-key" # Must be created in AWS first

  # Root volume configuration
  root_block_device = {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # IAM configuration (for SSM access)
  create_iam_instance_profile = true
  iam_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]

  # User data for initial setup
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Set hostname
    hostnamectl set-hostname k8s-worker-01

    # Update /etc/hosts
    echo "127.0.1.1 k8s-worker-01" >> /etc/hosts
  EOF

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Name              = "k8s-worker-01"
      Role              = "kubernetes-worker"
      KubernetesCluster = "vanilla-k8s-lab"
      Component         = "worker"
    }
  )
}
