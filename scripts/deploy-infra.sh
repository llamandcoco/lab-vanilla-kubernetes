#!/bin/bash
# -----------------------------------------------------------------------------
# Deploy Kubernetes Lab Infrastructure
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAGRUNT_DIR="${PROJECT_ROOT}/aws/00-k8s"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Deploying Kubernetes Lab Infrastructure${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v terragrunt &> /dev/null; then
    echo "Error: terragrunt is not installed"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "Error: aws CLI is not installed"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured"
    echo "Run: aws sso login --profile <your-profile>"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites check passed"
echo ""

# Navigate to Terragrunt directory
cd "${TERRAGRUNT_DIR}"

# Define deployment order based on dependencies
MODULES=(
    "00-ssh-key"
    "01-networking"
    "02-security-groups"
    "03-control-plane"
    "04-worker-nodes"
)

# Initialize all modules first
echo -e "${YELLOW}Initializing all modules...${NC}"
for module in "${MODULES[@]}"; do
    echo -e "${BLUE}→ Initializing ${module}${NC}"
    cd "${TERRAGRUNT_DIR}/${module}"
    terragrunt init
done

echo ""
echo -e "${YELLOW}Deploying infrastructure sequentially...${NC}"
echo -e "${YELLOW}Note: Planning and applying each module in dependency order${NC}"
read -p "Do you want to proceed with deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

# Deploy modules in order (plan + apply for each module sequentially)
for module in "${MODULES[@]}"; do
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Deploying ${module}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cd "${TERRAGRUNT_DIR}/${module}"

    # Plan first
    echo -e "${YELLOW}→ Planning ${module}${NC}"
    terragrunt plan

    # Then apply
    echo ""
    echo -e "${YELLOW}→ Applying ${module}${NC}"
    terragrunt apply -auto-approve

    echo -e "${GREEN}✓${NC} ${module} deployed successfully"
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Infrastructure deployed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Display outputs
echo "Control Plane IP:"
cd "${TERRAGRUNT_DIR}/03-control-plane" && terragrunt output public_ip

echo ""
echo "Worker Node IP:"
cd "${TERRAGRUNT_DIR}/04-worker-nodes" && terragrunt output public_ip

echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Run: cd ${PROJECT_ROOT}/ansible"
echo "2. Run: ./scripts/generate-inventory.sh"
echo "3. Run: ${SCRIPT_DIR}/deploy-k8s.sh"
