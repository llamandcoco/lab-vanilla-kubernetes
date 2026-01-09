#!/bin/bash
# -----------------------------------------------------------------------------
# Destroy Kubernetes Lab Infrastructure
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
echo -e "${BLUE}  Destroying Kubernetes Lab Infrastructure${NC}"
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

# Destroy order (reverse of create)
MODULES=(
    "04-worker-nodes"
    "03-control-plane"
    "02-security-groups"
    "01-networking"
    "00-ssh-key"
)

echo -e "${YELLOW}You are about to destroy all lab resources in ${TERRAGRUNT_DIR}${NC}"
read -p "Type 'yes' to continue: " confirm
if [ "$confirm" != "yes" ]; then
    echo "Destroy cancelled"
    exit 0
fi

# Destroy modules in reverse dependency order
for module in "${MODULES[@]}"; do
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Destroying ${module}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cd "${TERRAGRUNT_DIR}/${module}"
    terragrunt destroy -auto-approve
    echo -e "${GREEN}✓${NC} ${module} destroyed"
    cd "${TERRAGRUNT_DIR}"
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Infrastructure destroyed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
