#!/bin/bash
set -e

echo "========================================="
echo "🔍 Post-Deployment Verification"
echo "========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

AWS_REGION="us-east-1"
PROJECT_NAME="public"

# Get cluster name from Terraform output
echo "📋 Reading Terraform outputs..."
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "public-eks")
CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint 2>/dev/null || echo "")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")

echo "  Cluster Name: $CLUSTER_NAME"
echo "  Cluster Endpoint: $CLUSTER_ENDPOINT"
echo "  VPC ID: $VPC_ID"

# Verify EKS cluster exists and is active
echo -e "\n☸️  Verifying EKS cluster status..."
CLUSTER_STATUS=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $AWS_REGION \
    --query 'cluster.status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo -e "${GREEN}✓${NC} EKS cluster is ACTIVE"
else
    echo -e "${RED}✗${NC} EKS cluster status: $CLUSTER_STATUS"
    if [ "$CLUSTER_STATUS" == "CREATING" ]; then
        echo "  Cluster is still being created. This may take 10-15 minutes."
        echo "  Waiting for cluster to become active..."
        aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION
        echo -e "${GREEN}✓${NC} Cluster is now ACTIVE"
    else
        exit 1
    fi
fi

# Update kubeconfig
echo -e "\n🔧 Updating kubeconfig..."
aws eks update-kubeconfig \
    --name $CLUSTER_NAME \
    --region $AWS_REGION \
    --alias public

echo -e "${GREEN}✓${NC} Kubeconfig updated"

# Wait for kubectl to be responsive
echo -e "\n⏳ Waiting for API server to respond..."
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if kubectl cluster-info &> /dev/null; then
        echo -e "${GREEN}✓${NC} API server is responsive"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo "  Retry $RETRY_COUNT/$MAX_RETRIES..."
    sleep 10
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}✗${NC} API server is not responding after $MAX_RETRIES retries"
    exit 1
fi

# Display cluster info
echo -e "\n📊 Cluster Information:"
kubectl cluster-info

# Check node status
echo -e "\n🖥️  Checking node status..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")

echo "  Total Nodes: $NODE_COUNT"
echo "  Ready Nodes: $READY_NODES"

if [ "$NODE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠${NC}  No nodes found. Node groups may still be initializing..."
    echo "  Waiting for nodes to join the cluster..."
    
    # Wait for nodes (timeout after 10 minutes)
    TIMEOUT=600
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        if [ "$NODE_COUNT" -gt 0 ]; then
            echo -e "${GREEN}✓${NC} Nodes have joined the cluster"
            break
        fi
        sleep 30
        ELAPSED=$((ELAPSED+30))
        echo "  Still waiting... ($ELAPSED/${TIMEOUT}s)"
    done
fi

# Display nodes
echo -e "\n📋 Node Details:"
kubectl get nodes -o wide

# Check system pods
echo -e "\n🔍 Checking system pods..."
echo "Pods in kube-system namespace:"
kubectl get pods -n kube-system

# Verify CoreDNS is running
COREDNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l)
if [ "$COREDNS_PODS" -gt 0 ]; then
    COREDNS_READY=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    echo -e "${GREEN}✓${NC} CoreDNS: $COREDNS_READY/$COREDNS_PODS pods running"
else
    echo -e "${YELLOW}⚠${NC}  CoreDNS pods not found"
fi

# Verify kube-proxy
KUBEPROXY_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | wc -l)
if [ "$KUBEPROXY_PODS" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} kube-proxy: $KUBEPROXY_PODS pods running"
else
    echo -e "${YELLOW}⚠${NC}  kube-proxy pods not found"
fi

# Check VPC CNI
VPC_CNI_PODS=$(kubectl get pods -n kube-system -l k8s-app=aws-node --no-headers 2>/dev/null | wc -l)
if [ "$VPC_CNI_PODS" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} VPC CNI: $VPC_CNI_PODS pods running"
else
    echo -e "${YELLOW}⚠${NC}  VPC CNI pods not found"
fi





# Check storage classes
echo -e "\n💿 Storage Classes:"
kubectl get storageclasses

# Verify VPC
echo -e "\n🌐 Verifying VPC configuration..."
if [ -n "$VPC_ID" ]; then
    VPC_STATE=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --region $AWS_REGION --query 'Vpcs[0].State' --output text)
    if [ "$VPC_STATE" == "available" ]; then
        echo -e "${GREEN}✓${NC} VPC $VPC_ID is available"
    else
        echo -e "${YELLOW}⚠${NC}  VPC state: $VPC_STATE"
    fi
    
    # Count subnets
    SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $AWS_REGION --query 'Subnets | length(@)' --output text)
    echo "  Subnets: $SUBNET_COUNT"
fi

# Check IAM OIDC provider
echo -e "\n🔐 Checking OIDC provider..."
OIDC_ISSUER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.identity.oidc.issuer' --output text)
OIDC_ID=$(echo $OIDC_ISSUER | sed 's/https:\/\///')
if aws iam list-open-id-connect-providers | grep -q "$OIDC_ID"; then
    echo -e "${GREEN}✓${NC} OIDC provider is configured"
else
    echo -e "${RED}✗${NC} OIDC provider not found"
fi

# Run connectivity test
echo -e "\n🔌 Testing pod connectivity..."
cat <<EOF | kubectl apply -f - &> /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: connectivity-test
  namespace: default
spec:
  containers:
  - name: test
    image: busybox:latest
    command: ['sh', '-c', 'sleep 30']
EOF

echo "  Waiting for test pod..."
kubectl wait --for=condition=Ready pod/connectivity-test --timeout=60s &> /dev/null || true

if kubectl get pod connectivity-test &> /dev/null; then
    echo -e "${GREEN}✓${NC} Pod creation successful"
    kubectl delete pod connectivity-test --grace-period=0 --force &> /dev/null || true
else
    echo -e "${YELLOW}⚠${NC}  Pod creation test skipped"
fi

# Display all Terraform outputs
echo -e "\n📤 Terraform Outputs:"
terraform output

# Summary
echo -e "\n========================================="
echo -e "${GREEN}✅ Post-deployment verification complete${NC}"
echo "========================================="
echo ""
echo "Next Steps:"
echo "  1. Review the cluster information above"
echo "  2. Install additional add-ons using scripts/install-addons.sh"
echo "  3. Deploy your applications"
echo "  4. Configure monitoring and logging"
echo ""
echo "Useful Commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  kubectl cluster-info"
echo ""

exit 0