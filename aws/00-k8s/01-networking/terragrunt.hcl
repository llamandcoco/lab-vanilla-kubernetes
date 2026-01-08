# -----------------------------------------------------------------------------
# Networking Stack - Kubernetes Lab
# lab-vanilla-kubernetes/aws/00-k8s/01-networking/terragrunt.hcl
#
# Deploys the Kubernetes lab VPC using infra-modules/stack/networking.
# Creates a VPC with public subnets only (no NAT Gateway needed).
# -----------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("_env_common.hcl")
  expose = true
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/stack/networking?ref=${include.env.locals.networking_stack_ref}"
}

# All networking configuration
inputs = {
  # Basic VPC settings
  name       = "laco-k8s"
  cidr_block = "10.100.0.0/16"
  azs        = ["ca-central-1a", "ca-central-1b"] # Two AZs for HA requirement

  # IPv6 and DNS
  enable_ipv6          = false
  enable_dns_support   = true
  enable_dns_hostnames = true

  # VPC settings
  enable_network_address_usage_metrics = false
  instance_tenancy                     = "default"

  # Subnets - public subnets only (no private or database subnets)
  # Public subnet will be auto-created based on azs
  private_subnet_cidrs    = []
  database_subnet_cidrs   = []
  map_public_ip_on_launch = true

  # NAT Gateway - disabled (using public subnets only)
  nat_gateway_mode       = "none"
  database_route_via_nat = false

  # Internet Gateway - enabled for public internet access
  internet_gateway_enabled = true

  # Security Groups - will be created separately
  workload_security_group_ingress = []
  workload_security_group_egress  = []

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Workload  = "kubernetes-lab"
      Component = "networking"
      Module    = "stack/networking"
      GitRepo   = "llamandcoco/infra-modules"
    }
  )
}
