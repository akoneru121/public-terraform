# CI/CD Deployment Guide

This guide explains how to set up and use the included CI/CD pipelines for deploying your EKS cluster with Terraform.

## 📋 Table of Contents

- [GitHub Actions Setup](#github-actions-setup)
- [Jenkins Setup](#jenkins-setup)
- [Pre-deployment Steps](#pre-deployment-steps)
- [Post-deployment Steps](#post-deployment-steps)
- [Workflows Overview](#workflows-overview)
- [Troubleshooting](#troubleshooting)

---

## 🚀 GitHub Actions Setup

### Prerequisites

1. **AWS Credentials**: Configure AWS credentials using OIDC (recommended) or access keys
2. **Terraform Backend**: Create S3 bucket and DynamoDB table for state management
3. **Repository Secrets**: Configure required secrets in GitHub

### Required GitHub Secrets

Navigate to **Settings → Secrets and variables → Actions** and add:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `AWS_ROLE_ARN` | IAM role ARN for GitHub Actions (OIDC) | `arn:aws:iam::123456789:role/github-actions` |
| `TF_STATE_BUCKET` | S3 bucket for Terraform state | `my-terraform-state-bucket` |
| `TF_STATE_LOCK_TABLE` | DynamoDB table for state locking | `terraform-state-lock` |
| `INFRACOST_API_KEY` | Infracost API key for cost estimation | `ico-xxx` |
| `SLACK_WEBHOOK_URL` | Slack webhook for notifications (optional) | `https://hooks.slack.com/...` |

### AWS OIDC Setup (Recommended)

Create an IAM OIDC provider for GitHub Actions:

```bash
# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create IAM role with trust policy
cat > github-actions-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name github-actions-terraform \
  --assume-role-policy-document file://github-actions-trust-policy.json

# Attach necessary policies
aws iam attach-role-policy \
  --role-name github-actions-terraform \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### Terraform Backend Setup

Create the S3 bucket and DynamoDB table:

```bash
# Create S3 bucket for state
aws s3 mb s3://my-terraform-state-bucket --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket my-terraform-state-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

### GitHub Workflows

The project includes 4 GitHub Actions workflows:

#### 1. Terraform Validate (`terraform-validate.yml`)
- **Trigger**: Pull requests and pushes to main/develop
- **Purpose**: Validate Terraform syntax and run security scans
- **Steps**:
  - Terraform format check
  - Terraform validate
  - Security scanning (tfsec, Checkov, Trivy)
  - Cost estimation with Infracost
  - TFLint validation

#### 2. Terraform Plan (`terraform-plan.yml`)
- **Trigger**: Pull requests to main
- **Purpose**: Generate and preview infrastructure changes
- **Steps**:
  - Pre-deployment validation
  - Terraform init with remote backend
  - Terraform plan
  - Comment plan output on PR

#### 3. Terraform Apply (`terraform-apply.yml`)
- **Trigger**: Pushes to main or manual workflow dispatch
- **Purpose**: Apply infrastructure changes
- **Steps**:
  - Pre-deployment validation
  - Terraform init
  - Terraform plan
  - Terraform apply (with approval gate)
  - Post-deployment verification
  - Add-ons installation
  - Slack notification

#### 4. Terraform Drift Detection (`terraform-drift.yml`)
- **Trigger**: Scheduled (Mon-Fri 8 AM UTC) or manual
- **Purpose**: Detect configuration drift
- **Steps**:
  - Terraform plan (detect drift)
  - Create GitHub issue if drift detected
  - Summary report

### Usage

1. **Create a branch** and make infrastructure changes
2. **Open a pull request** → Validation and plan workflows run automatically
3. **Review the plan** output in PR comments
4. **Merge to main** → Apply workflow runs (with approval gate)
5. **Monitor** drift detection runs daily

---

## 🔧 Jenkins Setup

### Prerequisites

1. Jenkins with Docker support
2. Required Jenkins plugins:
   - Pipeline
   - AWS Credentials
   - Slack Notification
   - Email Extension
3. AWS credentials configured in Jenkins

### Required Jenkins Credentials

Create the following credentials in **Jenkins → Manage Jenkins → Credentials**:

| Credential ID | Type | Description |
|---------------|------|-------------|
| `aws-credentials` | AWS Credentials | AWS access key and secret key |
| `tf-state-bucket` | Secret text | S3 bucket name for Terraform state |
| `tf-state-lock-table` | Secret text | DynamoDB table name for locking |
| `slack-webhook-url` | Secret text | Slack webhook URL (optional) |

### Jenkins Pipeline Parameters

The Jenkinsfile includes configurable parameters:

- **ACTION**: Choose `plan`, `apply`, or `destroy`
- **AUTO_APPROVE**: Skip manual approval step (default: false)

### Pipeline Stages

1. **Checkout**: Clone repository and get commit info
2. **Pre-deployment Validation**: Run validation scripts
3. **Terraform Format Check**: Verify code formatting
4. **Security Scanning**: Run tfsec and Checkov in parallel
5. **Terraform Init**: Initialize with remote backend
6. **Terraform Validate**: Validate configuration
7. **Terraform Plan**: Generate execution plan
8. **Cost Estimation**: Estimate costs with Infracost
9. **Manual Approval**: Wait for user approval (unless AUTO_APPROVE)
10. **Terraform Apply/Destroy**: Execute changes
11. **Post-deployment Verification**: Verify cluster health
12. **Install Add-ons**: Deploy Kubernetes add-ons

### Usage

1. **Create a new Pipeline job** in Jenkins
2. **Configure** to use the Jenkinsfile from your repository
3. **Build with Parameters** and select desired action
4. **Monitor** the pipeline execution
5. **Approve** manual steps when prompted

### Jenkins Agent Requirements

The Jenkins agent needs:
- Docker installed
- AWS CLI installed
- Terraform 1.6.0 or later
- kubectl installed
- helm installed

---

## ✅ Pre-deployment Steps

The `scripts/pre-deploy.sh` script performs comprehensive validation:

### Checks Performed

- ✓ Required tools installed (terraform, aws, jq)
- ✓ AWS credentials valid
- ✓ AWS region accessible
- ✓ Service quotas sufficient
- ✓ Terraform syntax valid
- ✓ terraform.tfvars exists
- ✓ CIDR blocks don't conflict
- ✓ Kubernetes version available
- ✓ Backend S3 bucket exists and configured
- ✓ Backend DynamoDB table exists
- ✓ IAM permissions (basic check)

### Manual Execution

```bash
chmod +x scripts/pre-deploy.sh
bash scripts/pre-deploy.sh
```

---

## 🔍 Post-deployment Steps

The `scripts/post-deploy.sh` script verifies successful deployment:

### Verifications Performed

- ✓ EKS cluster is ACTIVE
- ✓ API server is responsive
- ✓ Nodes have joined and are Ready
- ✓ System pods are running (CoreDNS, kube-proxy, VPC CNI)


- ✓ Storage classes available
- ✓ VPC configured correctly
- ✓ OIDC provider configured
- ✓ Pod connectivity test

### Manual Execution

```bash
chmod +x scripts/post-deploy.sh
bash scripts/post-deploy.sh
```

---

## 📦 Add-ons Installation

The `scripts/install-addons.sh` script installs all configured add-ons:

### Add-ons Installed


- ✓ AWS Load Balancer Controller







- ✓ Metrics Server (always installed)

### Manual Execution

```bash
chmod +x scripts/install-addons.sh
bash scripts/install-addons.sh
```

---

## 📊 Workflows Overview

### Standard Workflow

```
┌─────────────────┐
│ Create PR       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Validate + Scan │ ← terraform-validate.yml
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Terraform Plan  │ ← terraform-plan.yml
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Code Review     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Merge to Main   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Pre-Deploy      │ ← scripts/pre-deploy.sh
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Terraform Apply │ ← terraform-apply.yml
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Post-Deploy     │ ← scripts/post-deploy.sh
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Install Add-ons │ ← scripts/install-addons.sh
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Notifications   │
└─────────────────┘
```

### Drift Detection Workflow

```
┌─────────────────┐
│ Scheduled Run   │ (Mon-Fri 8 AM)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Terraform Plan  │ (detect changes)
└────────┬────────┘
         │
         ▼
  ┌─────┴─────┐
  │           │
  ▼           ▼
┌────┐      ┌──────┐
│ No │      │ Drift│
│Drift│      │Found │
└────┘      └───┬──┘
                │
                ▼
         ┌──────────────┐
         │ Create Issue │
         └──────────────┘
```

---

## 🔧 Troubleshooting

### Common Issues

#### 1. Authentication Errors

**Error**: `Error: Invalid AWS credentials`

**Solution**:
```bash
# For GitHub Actions - verify OIDC setup
aws sts assume-role-with-web-identity \
  --role-arn $AWS_ROLE_ARN \
  --role-session-name test \
  --web-identity-token $(curl -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL" | jq -r .value)

# For Jenkins - verify credentials
aws sts get-caller-identity
```

#### 2. State Locking Errors

**Error**: `Error locking state: ConditionalCheckFailedException`

**Solution**:
```bash
# Force unlock (use carefully!)
terraform force-unlock LOCK_ID

# Or delete stuck lock from DynamoDB
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"LOCK_ID"}}'
```

#### 3. Plan Failures

**Error**: `Error: ... already exists`

**Solution**:
```bash
# Import existing resource
terraform import aws_vpc.main vpc-xxxxx

# Or refresh state
terraform refresh
```

#### 4. Add-on Installation Failures

**Error**: `Error: timed out waiting for the condition`

**Solution**:
```bash
# Check pod status
kubectl get pods -A

# Check pod logs
kubectl logs -n NAMESPACE POD_NAME

# Describe pod for events
kubectl describe pod -n NAMESPACE POD_NAME
```

### Getting Help

- **Logs**: Check workflow logs in GitHub Actions or Jenkins console
- **AWS Console**: Verify resources in AWS Console
- **kubectl**: Use kubectl commands to debug cluster issues
- **Terraform**: Run `terraform plan` locally to test changes

### Useful Commands

```bash
# Check GitHub Actions workflow runs
gh run list

# View workflow logs
gh run view RUN_ID --log

# Trigger workflow manually
gh workflow run terraform-apply.yml

# Check cluster status
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# View Terraform state
terraform state list
terraform show

# Debug terraform
TF_LOG=DEBUG terraform plan
```

---

## 📝 Best Practices

1. **Always review** Terraform plans before applying
2. **Use branches** for infrastructure changes
3. **Enable drift detection** to catch manual changes
4. **Monitor costs** using Infracost reports
5. **Keep secrets secure** - never commit credentials
6. **Test in non-production** first
7. **Document changes** in commit messages
8. **Use tags** for resource organization
9. **Enable notifications** for pipeline failures
10. **Regular backups** of Terraform state

---

## 🔗 Additional Resources

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [GitHub Actions for Terraform](https://learn.hashicorp.com/tutorials/terraform/github-actions)
- [Jenkins Pipeline Syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)

---

**Generated by EKS Wizard** | Project: public | Region: us-east-1