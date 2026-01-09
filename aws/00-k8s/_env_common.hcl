# -----------------------------------------------------------------------------
# Environment Configuration - Kubernetes Lab
# lab-vanilla-kubernetes/aws/00-k8s/_env_common.hcl
#
# This file defines common settings for the Kubernetes lab environment.
# It is included by layer-level terragrunt.hcl files.
# -----------------------------------------------------------------------------

locals {
  # Environment metadata
  environment = "k8s"
  provider    = "aws"
  team        = "learning"
  owner       = "llama"

  # Common tags for this environment
  common_tags = {
    Environment = local.environment
    Provider    = local.provider
    Team        = local.team
    Owner       = local.owner
  }

  # Reference to infra-modules commit SHA or branch
  # Using 'main' for latest, or specify a commit SHA for reproducibility
  networking_stack_ref = "main"
  ec2_ref              = "main"
  security_group_ref   = "175504bb841e131b7442c4194678de82ee52aa45"
  key_pair_ref         = "main"

  # AMI IDs (centralized)
  # NOTE: AMI IDs are region-specific and may be deprecated over time.
  #       Verify and update this value for your target region before deployment
  #       (see docs/deployment.md for instructions on fetching the latest AMI).
  ubuntu_2204_ami_id = "ami-02502825b39f7c669" # Ubuntu Server Pro 22.04 LTS (ca-central-1)
}
