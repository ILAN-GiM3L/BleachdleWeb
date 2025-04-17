pipeline {
    agent any

    environment {
        // Common environment variables
        PATH = "/usr/local/bin:/opt/homebrew/bin:/Users/ilangimelfarb/Downloads/google-cloud-sdk/bin:${env.PATH}"

        GCP_PROJECT = credentials('GCP_PROJECT')
        GCP_REGION  = credentials('GCP_REGION')

        DOCKERHUB_REPO     = 'ilangimel/bleachdle-web-app'
        DOCKERHUB_USERNAME = credentials('DOCKERHUB_USERNAME')
        DOCKERHUB_PASSWORD = credentials('DOCKERHUB_PASSWORD')
        IMAGE_NAME         = 'ilangimel/bleachdle-web-app'
        VERSION            = "${BUILD_NUMBER}"

        // For tests (optional)
        DB_HOST     = credentials('DB_HOST')
        DB_USER     = credentials('DB_USER')
        DB_PASSWORD = credentials('DB_PASSWORD')
        DB_NAME     = credentials('DB_NAME')
        API_URL     = credentials('API_URL')
    }

    stages {

        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }

        stage('Clone Repository') {
            steps {
                script {
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/main']],
                        userRemoteConfigs: [[
                            url: 'https://github.com/ILAN-GiM3L/BleachdleWeb.git',
                            credentialsId: 'Github-cred'
                        ]]
                    ])
                }
            }
        }


        // Only log in to Docker Hub if image-related files changed
        stage('Login to Docker Hub (if needed)') {
            when {
                changeset pattern: 'app\\.py|templates/.*|static/.*|requirements\\.txt|Dockerfile', comparator: 'REGEXP'
            }
            steps {
                script {
                    withCredentials([
                        string(credentialsId: 'DOCKERHUB_USERNAME', variable: 'DOCKER_USERNAME'),
                        string(credentialsId: 'DOCKERHUB_PASSWORD', variable: 'DOCKER_PASSWORD')
                    ]) {
                        sh '''
                            echo "Logging into Docker Hub..."
                            echo $DOCKER_PASSWORD | docker login --username $DOCKER_USERNAME --password-stdin
                        '''
                    }
                }
            }
        }

        // Build/push Docker image if app-related files changed
        stage('Build & Push Docker Image (if needed)') {
            when {
                changeset pattern: 'app\\.py|templates/.*|static/.*|requirements\\.txt|Dockerfile', comparator: 'REGEXP'
            }
            steps {
                script {
                    dir("${WORKSPACE}") {
                        sh '''
                            echo "Setting up Docker Buildx builder named Bleachbuild"
                            docker buildx create --use --name Bleachbuild || echo "Buildx builder already exists"

                            echo "Building the Docker image using multi-arch builds"
                            docker buildx build --platform linux/amd64,linux/arm64 \
                                -t $IMAGE_NAME:latest \
                                -t $IMAGE_NAME:1.0.$VERSION \
                                . --push
                        '''
                    }
                }
            }
        }

        // Only create/update cluster if .tf changed or cluster doesn't exist
        stage('Create/Update Bleachdle GKE Cluster') {
            when {
                anyOf {
                    changeset pattern: 'terraform/bleachdle/.*\\.tf', comparator: 'REGEXP'
                    expression {
                        // Wrap the "gcloud auth" check in withCredentials so GCP_CREDENTIALS_FILE is not empty
                        withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                            def status = sh(
                                script: """
                                    set +e
                                    gcloud auth activate-service-account --key-file=\$GCP_CREDENTIALS_FILE
                                    gcloud config set project \$GCP_PROJECT
                                    gcloud container clusters describe bleachdle-cluster --region \$GCP_REGION >/dev/null 2>&1
                                    exit \$?
                                """, returnStatus: true
                            )
                            return (status != 0)  // if status != 0 => cluster not found => run stage
                        }
                    }
                }
            }
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/bleachdle") {
                            sh '''
                                echo "[Bleachdle] Creating or updating single cluster..."
                                export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                                gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                                gcloud config set project "${GCP_PROJECT}"

                                terraform init
                                terraform plan -out=tfplan
                                terraform apply -auto-approve tfplan
                            '''
                        }
                    }
                }
            }
        }

        // Install ArgoCD only if it's missing (we don't tie it to changes in the app config)
        stage('Install ArgoCD (only if missing)') {
            when {
                expression {
                    // Wrap the "gcloud auth" check in withCredentials so GCP_CREDENTIALS_FILE is not empty
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        def status = sh(
                            script: """
                                set +e
                                gcloud auth activate-service-account --key-file=\$GCP_CREDENTIALS_FILE
                                gcloud config set project \$GCP_PROJECT
                                gcloud container clusters get-credentials bleachdle-cluster --region \$GCP_REGION
                                kubectl get deployment argocd-server -n argocd >/dev/null 2>&1
                                exit \$?
                            """, returnStatus: true
                        )
                        return (status != 0) // if non-zero => argocd-server deployment not found => install ArgoCD
                    }
                }
            }
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/bleachdle") {
                            sh '''
                                echo "[Argo] Installing Argo CD on single cluster..."
                                export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                                
                                gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                                gcloud config set project "${GCP_PROJECT}"
                                gcloud container clusters get-credentials bleachdle-cluster --region "${GCP_REGION}"

                                kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

                                kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

                                echo "[Argo] Patching 'argocd-server' to LoadBalancer..."
                                kubectl rollout status deploy/argocd-server -n argocd --timeout=180s || true
                                kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

                                echo "[Argo] Creating 'monitoring' namespace if missing..."
                                kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

                                # Wait for external IP
                                echo "[Argo] Waiting for external IP..."
                                COUNT=0
                                EXTERNAL_IP=""
                                while [ $COUNT -lt 30 ]; do
                                  EXTERNAL_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                                  ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o go-template='{{.data.password | base64decode}}')
                                  if [ -n "$EXTERNAL_IP" ]; then
                                    echo "[Argo] Found IP: $EXTERNAL_IP"
                                    echo "[Argo] Access ArgoCD at: http://$EXTERNAL_IP"
                                    echo "[Argo] Initial admin password: $ARGOCD_PASSWORD"
                                    break
                                  else
                                    echo "Waiting for IP..."
                                    sleep 10
                                    COUNT=$((COUNT+1))
                                  fi
                                done
                            '''
                        }
                    }
                }
            }
        }

        // Deploy the parent app if:
        // - The bleachdle-parent application isn't in the cluster, OR
        // - The parent-application.yaml itself changed
        stage('Deploy/Update Parent Application') {
            when {
                anyOf {
                    changeset pattern: 'argocd-apps/parent-application\\.yaml', comparator: 'REGEXP'
                    expression {
                        // Wrap the "gcloud auth" check in withCredentials so GCP_CREDENTIALS_FILE is not empty
                        withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                            def status = sh(
                                script: """
                                    set +e
                                    gcloud auth activate-service-account --key-file=\$GCP_CREDENTIALS_FILE
                                    gcloud config set project \$GCP_PROJECT
                                    gcloud container clusters get-credentials bleachdle-cluster --region \$GCP_REGION
                                    kubectl get app bleachdle-parent -n argocd >/dev/null 2>&1
                                    exit \$?
                                """, returnStatus: true
                            )
                            return (status != 0) // if non-zero => 'bleachdle-parent' doesn't exist
                        }
                    }
                }
            }
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/bleachdle") {
                            sh '''
                                echo "[Argo] Deploying or updating Parent Application..."
                                export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                                
                                gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                                gcloud config set project "${GCP_PROJECT}"
                                gcloud container clusters get-credentials bleachdle-cluster --region "${GCP_REGION}"

                                EXTERNAL_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                                ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o go-template='{{.data.password | base64decode}}')

                                argocd login "$EXTERNAL_IP" \
                                    --username admin \
                                    --password "$ARGOCD_PASSWORD" \
                                    --insecure

                                kubectl apply -n argocd -f ../../argocd-apps/parent-application.yaml
                            '''
                        }
                    }
                }
            }
        }
    }
    post {
        always {
            script {
                echo "Pipeline finished. Cleaning workspace."
            }
            cleanup {
                cleanWs()
            }
        }
    }
}
