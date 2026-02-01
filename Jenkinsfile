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
        AWS_REGION       = 'us-east-1'
        TF_IN_AUTOMATION = 'true'
        TF_INPUT         = 'false'
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
            }
        }

        stage('Terraform Format Check') {
            steps {
                sh 'terraform fmt -check -recursive'
            }
        }

        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }

        stage('Terraform Validate') {
            steps {
                sh 'terraform validate'
            }
        }

        stage('Terraform Plan') {
            steps {
                echo "📋 Running Terraform plan..."

                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'aws-jenkins-creds']
                ]) {
                    sh '''
                        export AWS_DEFAULT_REGION=${AWS_REGION}
                        aws sts get-caller-identity

                        terraform plan -out=tfplan -no-color | tee plan.txt
                    '''
                }

                archiveArtifacts artifacts: 'tfplan,plan.txt', fingerprint: true

                script {
                    def planOutput = readFile('plan.txt')
                    env.HAS_CHANGES = planOutput.contains('No changes') ? 'false' : 'true'
                }
            }
        }

        stage('Manual Approval') {
            when {
                allOf {
                    expression { params.ACTION != 'plan' }
                    expression { params.AUTO_APPROVE == false }
                    expression { env.HAS_CHANGES == 'true' }
                }
            }
            steps {
                input message: "Approve Terraform ${params.ACTION}?"
            }
        }

        stage('Terraform Apply') {
            when {
                expression { params.ACTION == 'apply' && env.HAS_CHANGES == 'true' }
            }
            steps {
                echo "🚀 Applying Terraform changes..."

                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'aws-jenkins-creds']
                ]) {
                    sh '''
                        export AWS_DEFAULT_REGION=${AWS_REGION}
                        terraform apply -auto-approve tfplan
                        terraform output -json > outputs.json
                    '''
                }

                archiveArtifacts artifacts: 'outputs.json', fingerprint: true
            }
        }

        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                echo "🗑️ Destroying Terraform resources..."

                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'aws-jenkins-creds']
                ]) {
                    sh '''
                        export AWS_DEFAULT_REGION=${AWS_REGION}
                        terraform destroy -auto-approve
                    '''
                }
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
