pipeline {
    agent any
    
    parameters {
        choice(
            name: 'ACTION',
            choices: ['plan', 'apply', 'destroy'],
            description: 'Select Terraform action to perform'
        )
        booleanParam(
            name: 'AUTO_APPROVE',
            defaultValue: false,
            description: 'Auto-approve Terraform apply/destroy'
        )
    }
    
    environment {
        TF_VERSION = '1.6.0'
        AWS_REGION = 'us-east-1'
        PROJECT_NAME = 'public'
        TF_IN_AUTOMATION = 'true'
        TF_INPUT = 'false'
        
        // AWS credentials from Jenkins credentials store
        AWS_CREDENTIALS = credentials('aws-credentials')
        
        // Terraform backend configuration
        TF_STATE_BUCKET = credentials('tf-state-bucket')
        TF_STATE_LOCK_TABLE = credentials('tf-state-lock-table')
        
        // Slack webhook for notifications
        SLACK_WEBHOOK = credentials('slack-webhook-url')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        disableConcurrentBuilds()
        timestamps()
        timeout(time: 2, unit: 'HOURS')
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    echo "🔄 Checking out code..."
                    checkout scm
                    
                    // Get commit information
                    env.GIT_COMMIT_MSG = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()
                    env.GIT_AUTHOR = sh(
                        script: 'git log -1 --pretty=%an',
                        returnStdout: true
                    ).trim()
                }
            }
        }
        
        stage('Pre-deployment Validation') {
            steps {
                script {
                    echo "✅ Running pre-deployment checks..."
                    sh '''
                        chmod +x scripts/pre-deploy.sh
                        bash scripts/pre-deploy.sh
                    '''
                }
            }
        }
        
        stage('Terraform Format Check') {
            steps {
                script {
                    echo "🎨 Checking Terraform formatting..."
                    def formatResult = sh(
                        script: 'terraform fmt -check -recursive',
                        returnStatus: true
                    )
                    if (formatResult != 0) {
                        error("❌ Terraform files are not properly formatted. Run 'terraform fmt -recursive'")
                    }
                }
            }
        }
        
        stage('Security Scanning') {
            parallel {
                stage('tfsec') {
                    steps {
                        script {
                            echo "🔒 Running tfsec security scan..."
                            sh '''
                                docker run --rm \
                                    -v $(pwd):/src \
                                    aquasec/tfsec:latest \
                                    /src \
                                    --format=junit \
                                    --out=/src/tfsec-results.xml \
                                    --minimum-severity MEDIUM || true
                            '''
                            junit 'tfsec-results.xml'
                        }
                    }
                }
                
                stage('Checkov') {
                    steps {
                        script {
                            echo "🔍 Running Checkov policy scan..."
                            sh '''
                                docker run --rm \
                                    -v $(pwd):/tf \
                                    bridgecrew/checkov:latest \
                                    -d /tf \
                                    --framework terraform \
                                    --output junitxml \
                                    --output-file-path /tf/checkov-results.xml || true
                            '''
                            junit 'checkov-results.xml'
                        }
                    }
                }
            }
        }
        
        stage('Terraform Init') {
            steps {
                script {
                    echo "🚀 Initializing Terraform..."
                    sh """
                        terraform init \
                            -backend-config="bucket=\${TF_STATE_BUCKET}" \
                            -backend-config="key=public/terraform.tfstate" \
                            -backend-config="region=us-east-1" \
                            -backend-config="dynamodb_table=\${TF_STATE_LOCK_TABLE}"
                    """
                }
            }
        }
        
        stage('Terraform Validate') {
            steps {
                script {
                    echo "✔️ Validating Terraform configuration..."
                    sh 'terraform validate'
                }
            }
        }
        
        stage('Terraform Plan') {
            steps {
                script {
                    echo "📋 Creating Terraform plan..."
                    def planResult = sh(
                        script: '''
                            set -o pipefail
                            terraform plan \
                                -var-file="terraform.tfvars" \
                                -out=tfplan \
                                -no-color | tee plan.txt
                        ''',
                        returnStatus: true
                    )
                    
                    if (planResult != 0) {
                        error("Terraform plan failed with exit code ${planResult}")
                    }
                    
                    // Archive the plan
                    archiveArtifacts artifacts: 'tfplan,plan.txt', fingerprint: true
                    
                    // Check for changes
                    def planOutput = readFile('plan.txt')
                    if (planOutput.contains('No changes')) {
                        env.HAS_CHANGES = 'false'
                        echo "ℹ️ No infrastructure changes detected"
                    } else {
                        env.HAS_CHANGES = 'true'
                        echo "📝 Infrastructure changes detected"
                    }
                }
            }
        }
        
        stage('Cost Estimation') {
            when {
                expression { env.HAS_CHANGES == 'true' }
            }
            steps {
                script {
                    echo "💰 Estimating infrastructure costs..."
                    sh '''
                        docker run --rm \
                            -v $(pwd):/code \
                            -e INFRACOST_API_KEY=\${INFRACOST_API_KEY} \
                            infracost/infracost:latest \
                            breakdown --path /code --format table | tee cost-estimate.txt || true
                    '''
                    archiveArtifacts artifacts: 'cost-estimate.txt', allowEmptyArchive: true
                }
            }
        }
        
        stage('Manual Approval') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' || params.ACTION == 'destroy' }
                    expression { params.AUTO_APPROVE == false }
                    expression { env.HAS_CHANGES == 'true' }
                }
            }
            steps {
                script {
                    def planSummary = readFile('plan.txt')
                    def userInput = input(
                        id: 'Proceed',
                        message: "Review the plan and approve to ${params.ACTION}",
                        parameters: [
                            text(
                                defaultValue: planSummary,
                                description: 'Terraform Plan Output',
                                name: 'PLAN_OUTPUT'
                            )
                        ],
                        ok: "Approve ${params.ACTION}"
                    )
                    echo "✅ Deployment approved by user"
                }
            }
        }
        
        stage('Terraform Apply') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { env.HAS_CHANGES == 'true' }
                }
            }
            steps {
                script {
                    echo "🚀 Applying Terraform changes..."
                    def applyResult = sh(
                        script: '''
                            set -o pipefail
                            terraform apply \
                                -auto-approve \
                                tfplan | tee apply.txt
                        ''',
                        returnStatus: true
                    )
                    
                    if (applyResult != 0) {
                        error("Terraform apply failed with exit code ${applyResult}")
                    }
                    
                    archiveArtifacts artifacts: 'apply.txt', fingerprint: true
                    
                    // Save outputs
                    sh 'terraform output -json > outputs.json'
                    archiveArtifacts artifacts: 'outputs.json', fingerprint: true
                }
            }
        }
        
        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                script {
                    echo "🗑️ Destroying Terraform infrastructure..."
                    def destroyResult = sh(
                        script: '''
                            set -o pipefail
                            terraform destroy \
                                -var-file="terraform.tfvars" \
                                -auto-approve | tee destroy.txt
                        ''',
                        returnStatus: true
                    )
                    
                    if (destroyResult != 0) {
                        error("Terraform destroy failed with exit code ${destroyResult}")
                    }
                    
                    archiveArtifacts artifacts: 'destroy.txt', fingerprint: true
                }
            }
        }
        
        stage('Post-deployment Verification') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { env.HAS_CHANGES == 'true' }
                }
            }
            steps {
                script {
                    echo "🔍 Running post-deployment verification..."
                    sh '''
                        chmod +x scripts/post-deploy.sh
                        bash scripts/post-deploy.sh
                    '''
                }
            }
        }
        
        stage('Install Add-ons') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { env.HAS_CHANGES == 'true' }
                }
            }
            steps {
                script {
                    echo "📦 Installing Kubernetes add-ons..."
                    sh '''
                        chmod +x scripts/install-addons.sh
                        bash scripts/install-addons.sh
                    '''
                }
            }
        }
    }
    
    post {
        success {
            script {
                def message = """
                ✅ *Terraform ${params.ACTION} Successful*
                
                *Project:* public
                *Region:* us-east-1
                *Action:* ${params.ACTION}
                *Branch:* ${env.BRANCH_NAME}
                *Commit:* ${env.GIT_COMMIT_MSG}
                *Author:* ${env.GIT_AUTHOR}
                *Build:* #${env.BUILD_NUMBER}
                *Duration:* ${currentBuild.durationString}
                
                <${env.BUILD_URL}|View Build>
                """
                
                slackSend(
                    color: 'good',
                    message: message,
                    channel: '#infrastructure'
                )
                
                emailext(
                    subject: "✅ Terraform ${params.ACTION} Successful - public",
                    body: """
                        <h2>Terraform Deployment Successful</h2>
                        <p><strong>Project:</strong> public</p>
                        <p><strong>Action:</strong> ${params.ACTION}</p>
                        <p><strong>Commit:</strong> ${env.GIT_COMMIT_MSG}</p>
                        <p><strong>Author:</strong> ${env.GIT_AUTHOR}</p>
                        <p><a href="${env.BUILD_URL}">View Build Details</a></p>
                    """,
                    to: '${DEFAULT_RECIPIENTS}',
                    mimeType: 'text/html'
                )
            }
        }
        
        failure {
            script {
                def message = """
                ❌ *Terraform ${params.ACTION} Failed*
                
                *Project:* public
                *Region:* us-east-1
                *Action:* ${params.ACTION}
                *Branch:* ${env.BRANCH_NAME}
                *Commit:* ${env.GIT_COMMIT_MSG}
                *Author:* ${env.GIT_AUTHOR}
                *Build:* #${env.BUILD_NUMBER}
                
                <${env.BUILD_URL}console|View Console Output>
                """
                
                slackSend(
                    color: 'danger',
                    message: message,
                    channel: '#infrastructure-alerts'
                )
                
                emailext(
                    subject: "❌ Terraform ${params.ACTION} Failed - public",
                    body: """
                        <h2>Terraform Deployment Failed</h2>
                        <p><strong>Project:</strong> public</p>
                        <p><strong>Action:</strong> ${params.ACTION}</p>
                        <p><strong>Commit:</strong> ${env.GIT_COMMIT_MSG}</p>
                        <p><strong>Author:</strong> ${env.GIT_AUTHOR}</p>
                        <p><a href="${env.BUILD_URL}console">View Console Output</a></p>
                    """,
                    to: '${DEFAULT_RECIPIENTS}',
                    mimeType: 'text/html'
                )
            }
        }
        
        always {
            cleanWs()
        }
    }
}