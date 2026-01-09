# -----------------------------------------------------------------------------
# Root Terragrunt Configuration
# lab-vanilla-kubernetes/root.hcl
#
# Shared backend and provider configuration for Kubernetes lab infrastructure.
# -----------------------------------------------------------------------------

locals {
  # AWS Account ID
  account_id = run_cmd("--terragrunt-quiet", "aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text")

  # Default region
  default_region = "ca-central-1"

  # Organization
  organization = "llamandcoco"
  org_prefix   = "laco"
}

# Local state configuration (simpler for single-user learning environment)
# State files stored locally - ensure .terraform/ and *.tfstate are in .gitignore

# Generate AWS provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.default_tags
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default     = {}
}
EOF
}

# Common inputs for all stacks
inputs = {
  aws_region = local.default_region

  default_tags = {
    ManagedBy    = "terragrunt"
    Repository   = "github.com/llamandcoco/lab-vanilla-kubernetes"
    Organization = local.organization
    Project      = "kubernetes-lab"
  }
}
