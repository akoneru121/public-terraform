#!/bin/bash
set -e

echo "========================================="
echo "📦 Installing Kubernetes Add-ons"
echo "========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AWS_REGION="us-east-1"
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "public-eks")

echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo ""

# Function to wait for pod readiness
wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}
    
    echo "  Waiting for pods with label $label in namespace $namespace..."
    kubectl wait --for=condition=Ready pod \
        -l "$label" \
        -n "$namespace" \
        --timeout="${timeout}s" 2>/dev/null || {
        echo -e "${YELLOW}⚠${NC}  Timeout waiting for pods, they may still be initializing"
        return 1
    }
    return 0
}


# Install AWS Load Balancer Controller
echo -e "${BLUE}📍 Installing AWS Load Balancer Controller...${NC}"

# Get IAM role ARN
ALB_ROLE_ARN=$(terraform output -raw aws_load_balancer_controller_role_arn 2>/dev/null || echo "")

if [ -z "$ALB_ROLE_ARN" ]; then
    echo -e "${RED}✗${NC} AWS Load Balancer Controller IAM role not found"
else
    # Add Helm repo
    helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
    helm repo update
    
    # Install or upgrade
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --namespace kube-system \
        --set clusterName=$CLUSTER_NAME \
        --set serviceAccount.create=true \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ALB_ROLE_ARN \
        --set region=$AWS_REGION \
        --set vpcId=$(terraform output -raw vpc_id) \
        --wait
    
    if wait_for_pods "kube-system" "app.kubernetes.io/name=aws-load-balancer-controller" 180; then
        echo -e "${GREEN}✓${NC} AWS Load Balancer Controller installed successfully"
    fi
fi














# Install Metrics Server (always recommended)
echo -e "\n${BLUE}📊 Installing Metrics Server...${NC}"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

if wait_for_pods "kube-system" "k8s-app=metrics-server" 120; then
    echo -e "${GREEN}✓${NC} Metrics Server installed successfully"
fi

# Summary
echo ""
echo "========================================="
echo -e "${GREEN}✅ Add-on installation complete${NC}"
echo "========================================="
echo ""
echo "Installed Add-ons:"

echo "  ✓ AWS Load Balancer Controller"







echo "  ✓ Metrics Server"
echo ""
echo "Verify installations:"
echo "  kubectl get pods -A"
echo "  kubectl get svc -A"
echo ""

exit 0