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

# Initialize and deploy
echo -e "${YELLOW}Initializing Terragrunt...${NC}"
terragrunt run-all init

echo ""
echo -e "${YELLOW}Planning infrastructure changes...${NC}"
terragrunt run-all plan

echo ""
echo -e "${YELLOW}Applying infrastructure changes...${NC}"
read -p "Do you want to apply these changes? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

terragrunt run-all apply

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Infrastructure deployed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Display outputs
echo "Control Plane IP:"
cd 03-control-plane && terragrunt output public_ip
cd ..

echo ""
echo "Worker Node IP:"
cd 04-worker-nodes && terragrunt output public_ip
cd ..

echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Run: cd ${PROJECT_ROOT}/ansible"
echo "2. Run: ./scripts/generate-inventory.sh"
echo "3. Run: ${SCRIPT_DIR}/deploy-k8s.sh"
