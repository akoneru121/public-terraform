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
        AWS_REGION = 'us-east-1'
        PROJECT_NAME = 'public'
        TF_IN_AUTOMATION = 'true'
        TF_INPUT = 'false'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        disableConcurrentBuilds()
        timestamps()
        timeout(time: 1, unit: 'HOURS')
    }

    stages {

        stage('Checkout') {
            steps {
                echo "🔄 Checking out code..."
                checkout scm

                script {
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

        stage('Terraform Format Check') {
            steps {
                echo "🎨 Checking Terraform formatting..."
                sh 'terraform fmt -check -recursive'
            }
        }

        stage('Terraform Init') {
            steps {
                echo "🚀 Initializing Terraform..."
                sh 'terraform init'
            }
        }

        stage('Terraform Validate') {
            steps {
                echo "✔️ Validating Terraform configuration..."
                sh 'terraform validate'
            }
        }

        stage('Terraform Plan') {
            steps {
                echo "📋 Running Terraform plan..."
                sh '''
                    terraform plan \
                      -out=tfplan \
                      -no-color | tee plan.txt
                '''

                archiveArtifacts artifacts: 'tfplan,plan.txt', fingerprint: true

                script {
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

        stage('Manual Approval') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' || params.ACTION == 'destroy' }
                    expression { params.AUTO_APPROVE == false }
                    expression { env.HAS_CHANGES == 'true' }
                }
            }
            steps {
                input message: "Approve Terraform ${params.ACTION}?",
                      ok: "Approve ${params.ACTION}"
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
                echo "🚀 Applying Terraform changes..."
                sh 'terraform apply -auto-approve tfplan'

                sh 'terraform output -json > outputs.json'
                archiveArtifacts artifacts: 'outputs.json', fingerprint: true
            }
        }

        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                echo "🗑️ Destroying Terraform resources..."
                sh 'terraform destroy -auto-approve'
            }
        }
    }

    post {
        success {
            echo "✅ Terraform ${params.ACTION} completed successfully"
        }

        failure {
            echo "❌ Terraform ${params.ACTION} failed"
        }
    }
}
