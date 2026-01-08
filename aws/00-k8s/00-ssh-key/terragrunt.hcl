# -----------------------------------------------------------------------------
# SSH Key Pair - Kubernetes Lab
# lab-vanilla-kubernetes/aws/00-k8s/00-ssh-key/terragrunt.hcl
#
# Creates an SSH key pair for accessing Kubernetes cluster instances.
# The private key will be saved to ~/.ssh/k8s-lab-key.pem
# -----------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("_env_common.hcl")
  expose = true
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/key-pair?ref=${include.env.locals.key_pair_ref}"
}

inputs = {
  # Key pair configuration
  key_name = "k8s-lab-key"

  # Generate a new RSA key pair
  public_key = null
  algorithm  = "RSA"
  rsa_bits   = 4096

  # Save keys to SSH directory
  save_private_key     = true
  save_public_key      = true
  private_key_filename = pathexpand("~/.ssh/k8s-lab-key.pem")
  public_key_filename  = pathexpand("~/.ssh/k8s-lab-key.pub")

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Name      = "k8s-lab-key"
      Component = "ssh-access"
      Purpose   = "kubernetes-cluster-access"
    }
  )
}
