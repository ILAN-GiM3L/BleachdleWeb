pipeline {
    agent any

    environment {
        // Ensure the proper PATH is set so that gcloud, docker, etc. are available
        PATH = "/usr/local/bin:/opt/homebrew/bin:/Users/ilangimelfarb/Downloads/google-cloud-sdk/bin:$PATH"
        
        GCP_PROJECT = 'bleachdle-web'
        GCP_REGION  = 'us-central1'

        DOCKERHUB_REPO     = 'ilangimel/bleachdle-web-app'
        DOCKERHUB_USERNAME = credentials('DOCKERHUB_USERNAME')
        DOCKERHUB_PASSWORD = credentials('DOCKERHUB_PASSWORD')
        IMAGE_NAME         = 'ilangimel/bleachdle-web-app'
        VERSION            = "${BUILD_NUMBER}"
        
        // For tests, if your app expects these env variables, you can set dummy values.
        DB_HOST     = "35.246.242.114"
        DB_USER     = "cm9vdA=="       // base64 for "test-user" if needed (or set plain text in tests)
        DB_PASSWORD = "R2V2ZXJZb3plbTEwMDcyMDAz"       // base64 for "test-pass"
        DB_NAME     =  "Bleach_DB"
        API_URL     = "https://bleachdle-web.oa.r.appspot.com"
    }

    stages {
        // Clean the workspace to start fresh
        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }

        // Checkout the repository (this must be a multibranch pipeline or similar for changeset to work)
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

        // Only run tests if files that affect the Docker image have changed:
        stage('Conditional: Run Tests') {
            when {
                changeset pattern: 'app\\.py|templates/.*|static/.*|requirements\\.txt|Dockerfile', comparator: 'REGEXP'
            }
            steps {
                script {
                    echo "Changes detected in application code. Running tests..."
                    // Install dependencies and run tests
                    // (If your tests require DB_HOST etc., the dummy values from the environment will be used)
                    sh 'pip install -r requirements.txt'
                    sh 'pytest --maxfail=1 --disable-warnings -q'
                }
            }
        }

        // Only login to Docker Hub if changes were made in the image-related files.
        stage('Conditional: Login to Docker Hub') {
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
                            echo "Logging into Docker Hub"
                            echo $DOCKER_PASSWORD | docker login --username $DOCKER_USERNAME --password-stdin
                        '''
                    }
                }
            }
        }

        // Only build and push the Docker image if changes were made in image-related files.
        stage('Conditional: Build and Push Docker Image') {
            when {
                changeset pattern: 'app\\.py|templates/.*|static/.*|requirements\\.txt|Dockerfile', comparator: 'REGEXP'
            }
            steps {
                script {
                    // Change directory if your Docker context is not the repository root.
                    // Here, assuming the Dockerfile is in the repository root.
                    dir("${WORKSPACE}") {
                        // Set up Docker Buildx builder for multi-platform builds
                        sh '''
                            echo "Setting up Docker Buildx builder named Bleachbuild"
                            docker buildx create --use --name Bleachbuild || echo "Buildx builder already exists"
                        '''
                        // Build and push the Docker image
                        sh '''
                            echo "Building the Docker image using Buildx with docker-compose.yml"
                            docker buildx build --platform linux/amd64,linux/arm64 -t $IMAGE_NAME:latest -t $IMAGE_NAME:1.0.${VERSION} . --push
                        '''
                    }
                }
            }
        }

        // Continue with your other stages for cluster setup and ArgoCD deployments.
        stage('Check/Create ArgoCD Cluster') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/argo") {
                            sh """
                                echo "[Argo] Checking if 'argocd-cluster' exists..."
                                export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"

                                gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                                gcloud config set project "${GCP_PROJECT}"
                                terraform init

                                set +e
                                gcloud container clusters describe argocd-cluster --region "${GCP_REGION}" > /dev/null 2>&1
                                CLUSTER_EXISTS=\$?
                                set -e

                                if [ \$CLUSTER_EXISTS -eq 0 ]; then
                                  echo "[Argo] 'argocd-cluster' ALREADY exists. Skipping creation."
                                else
                                  echo "[Argo] 'argocd-cluster' does NOT exist. Creating..."
                                  terraform plan -out=tfplan -target=google_container_cluster.argocd -target=google_container_node_pool.argocd_nodes
                                  terraform apply -auto-approve tfplan
                                fi
                            """
                        }
                    }
                }
            }
        }

        stage('Install & Expose ArgoCD') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/argo") {
                            sh """
                                echo "[Argo] Installing Argo CD on 'argocd-cluster'..."
                                export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                                
                                gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                                gcloud config set project "${GCP_PROJECT}"
                                gcloud components install gke-gcloud-auth-plugin --quiet || true
                                
                                ARGO_CLUSTER=\$(terraform output -raw argocd_cluster_name)
                                gcloud container clusters get-credentials "\$ARGO_CLUSTER" --region "${GCP_REGION}"
                                
                                # Create argocd namespace if it doesn't exist
                                kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
                                
                                # Apply official Argo CD manifests
                                kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
                                
                                echo "[Argo] Patching 'argocd-server' to LoadBalancer..."
                                kubectl rollout status deploy/argocd-server -n argocd --timeout=180s || true
                                kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
                                
                                echo "[Argo] Waiting for external IP..."
                                COUNT=0
                                EXTERNAL_IP=""
                                while [ \$COUNT -lt 30 ]; do
                                  EXTERNAL_IP=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                                  ARGOCD_PASSWORD=\$(kubectl get secret argocd-initial-admin-secret -n argocd -o go-template='{{.data.password | base64decode}}')
                                  if [ -n "\$EXTERNAL_IP" ]; then
                                    echo "[Argo] Found IP: \$EXTERNAL_IP"
                                    echo "[Argo] Access Argo CD at: http://\$EXTERNAL_IP"
                                    echo "[Argo] Initial admin password: \$ARGOCD_PASSWORD"
                                    break
                                  else
                                    echo "Waiting for IP..."
                                    sleep 10
                                    COUNT=\$((COUNT+1))
                                  fi
                                done
                            """
                        }
                    }
                }
            }
        }

        stage('Destroy Old Bleachdle Cluster') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/bleachdle") {
                            sh """
                                echo "[Bleachdle] Checking if 'bleachdle-cluster' exists..."
                                export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                                
                                gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                                gcloud config set project "${GCP_PROJECT}"
                                terraform init
                                
                                set +e
                                gcloud container clusters describe bleachdle-cluster --region "${GCP_REGION}" > /dev/null 2>&1
                                EPH_EXISTS=\$?
                                set -e
                                
                                if [ \$EPH_EXISTS -eq 0 ]; then
                                  echo "[Bleachdle] Found 'bleachdle-cluster'. Destroying..."
                                  terraform destroy -auto-approve || true
                                else
                                  echo "[Bleachdle] 'bleachdle-cluster' NOT found. Skipping."
                                fi
                            """
                        }
                    }
                }
            }
        }

        stage('Create Bleachdle Ephemeral Cluster') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/bleachdle") {
                            sh """
                                echo "[Bleachdle] Creating ephemeral cluster..."
                                export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                                
                                gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                                gcloud config set project "${GCP_PROJECT}"
                                
                                terraform init
                                terraform plan -out=tfplan
                                terraform apply -auto-approve tfplan
                            """
                        }
                    }
                }
            }
        }

        stage('Register Bleachdle Ephemeral Cluster in ArgoCD') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh """
                            echo "[Argo] Registering ephemeral cluster with ArgoCD..."
                            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                            
                            cd terraform/argo
                            ARGO_CLUSTER=\$(terraform output -raw argocd_cluster_name)
                            
                            gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                            gcloud config set project "${GCP_PROJECT}"
                            gcloud container clusters get-credentials "\$ARGO_CLUSTER" --region "${GCP_REGION}"
                            
                            EXTERNAL_IP=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                            ARGOCD_PASSWORD=\$(kubectl get secret argocd-initial-admin-secret -n argocd -o go-template='{{.data.password | base64decode}}')
                            
                            argocd login "\$EXTERNAL_IP" \\
                                --username admin \\
                                --password "\$ARGOCD_PASSWORD" \\
                                --insecure
                            
                            cd ../bleachdle
                            BLEACH_CLUSTER=\$(terraform output -raw bleachdle_cluster_name)
                            gcloud container clusters get-credentials "\$BLEACH_CLUSTER" --region "${GCP_REGION}"
                            
                            CURRENT_CONTEXT=\$(kubectl config current-context)
                            yes | argocd cluster add "\$CURRENT_CONTEXT" --name bleachdle-ephemeral
                            echo "[Argo] Ephemeral cluster registered under name 'bleachdle-ephemeral'"
                        """
                    }
                }
            }
        }

        stage('Deploy Applications with ArgoCD') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh """
                            echo "[Argo] Deploying Parent Application and Child Applications..."
                            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                            
                            cd terraform/argo
                            ARGO_CLUSTER=\$(terraform output -raw argocd_cluster_name)
                            
                            gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                            gcloud config set project "${GCP_PROJECT}"
                            gcloud container clusters get-credentials "\$ARGO_CLUSTER" --region "${GCP_REGION}"
                            
                            EXTERNAL_IP=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                            ARGOCD_PASSWORD=\$(kubectl get secret argocd-initial-admin-secret -n argocd -o go-template='{{.data.password | base64decode}}')
                            
                            argocd login "\$EXTERNAL_IP" \\
                                --username admin \\
                                --password "\$ARGOCD_PASSWORD" \\
                                --insecure
                            
                            kubectl apply -n argocd -f ../argocd-apps/parent-application.yaml
                            
                            echo "[Argo] Applications deployed. Child apps will be synced automatically."
                        """
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
