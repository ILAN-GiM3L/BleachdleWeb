pipeline {
    agent any

    environment {
        PATH = "/usr/local/bin:/opt/homebrew/bin:/Users/ilangimelfarb/Downloads/google-cloud-sdk/bin:$PATH"
        
        GCP_PROJECT = 'bleachdle-web'
        GCP_REGION  = 'us-central1'

        DOCKERHUB_REPO     = 'ilangimel/bleachdle-web-app'
        DOCKERHUB_USERNAME = credentials('DOCKERHUB_USERNAME')
        DOCKERHUB_PASSWORD = credentials('DOCKERHUB_PASSWORD')
        IMAGE_NAME         = 'ilangimel/bleachdle-web-app'
        VERSION            = "${BUILD_NUMBER}"
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

        // 1) Check/Create ArgoCD (Persistent) Cluster
        stage('Check/Create ArgoCD Cluster') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/argo") {
                            sh """
                                echo "[Argo] Checking if 'argocd-cluster' exists..."
                                export GOOGLE_APPLICATION_CREDENTIALS=\$GCP_CREDENTIALS_FILE

                                gcloud auth activate-service-account --key-file="\$GCP_CREDENTIALS_FILE"
                                gcloud config set project "\$GCP_PROJECT"
                                terraform init

                                set +e
                                gcloud container clusters describe argocd-cluster --region "\$GCP_REGION" > /dev/null 2>&1
                                CLUSTER_EXISTS=\$?
                                set -e

                                if [ \$CLUSTER_EXISTS -eq 0 ]; then
                                  echo "[Argo] 'argocd-cluster' ALREADY exists. Skip creating."
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

        // 2) Install & Expose ArgoCD on that cluster
        stage('Install & Expose ArgoCD') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/argo") {
                            sh """
                                echo "[Argo] Installing Argo CD on 'argocd-cluster'..."
                                export GOOGLE_APPLICATION_CREDENTIALS=\$GCP_CREDENTIALS_FILE

                                gcloud auth activate-service-account --key-file="\$GCP_CREDENTIALS_FILE"
                                gcloud config set project "\$GCP_PROJECT"
                                gcloud components install gke-gcloud-auth-plugin --quiet || true

                                ARGO_CLUSTER=\$(terraform output -raw argocd_cluster_name)
                                gcloud container clusters get-credentials "\$ARGO_CLUSTER" --region "\$GCP_REGION"

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

        // 3) Destroy Old Bleachdle Ephemeral cluster if it exists
        stage('Destroy Old Bleachdle Cluster') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/bleachdle") {
                            sh """
                                echo "[Bleachdle] Checking if 'bleachdle-cluster' exists..."
                                export GOOGLE_APPLICATION_CREDENTIALS=\$GCP_CREDENTIALS_FILE

                                gcloud auth activate-service-account --key-file="\$GCP_CREDENTIALS_FILE"
                                gcloud config set project "\$GCP_PROJECT"
                                terraform init

                                set +e
                                gcloud container clusters describe bleachdle-cluster --region "\$GCP_REGION" > /dev/null 2>&1
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

        // 4) Create Bleachdle Ephemeral Cluster
        stage('Create Bleachdle Ephemeral Cluster') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/bleachdle") {
                            sh """
                                echo "[Bleachdle] Creating ephemeral cluster..."
                                export GOOGLE_APPLICATION_CREDENTIALS=\$GCP_CREDENTIALS_FILE

                                gcloud auth activate-service-account --key-file="\$GCP_CREDENTIALS_FILE"
                                gcloud config set project "\$GCP_PROJECT"

                                terraform init
                                terraform plan -out=tfplan
                                terraform apply -auto-approve tfplan
                            """
                        }
                    }
                }
            }
        }

        // 5) Register Bleachdle Ephemeral Cluster in ArgoCD
        stage('Register Bleachdle Ephemeral Cluster in ArgoCD') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh """
                            echo "[Argo] Registering ephemeral cluster with ArgoCD..."
                            export GOOGLE_APPLICATION_CREDENTIALS=\$GCP_CREDENTIALS_FILE

                            # 1) Get credentials for Argocd cluster
                            cd terraform/argo
                            ARGO_CLUSTER=\$(terraform output -raw argocd_cluster_name)

                            gcloud auth activate-service-account --key-file="\$GCP_CREDENTIALS_FILE"
                            gcloud config set project "\$GCP_PROJECT"
                            gcloud container clusters get-credentials "\$ARGO_CLUSTER" --region "\$GCP_REGION"

                            # 2) Extract ArgoCD service IP and admin password
                            EXTERNAL_IP=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                            ARGOCD_PASSWORD=\$(kubectl get secret argocd-initial-admin-secret -n argocd -o go-template='{{.data.password | base64decode}}')

                            # 3) Login to ArgoCD CLI (assumes ArgoCD CLI is installed)
                            argocd login "\$EXTERNAL_IP" \\
                                --username admin \\
                                --password "\$ARGOCD_PASSWORD" \\
                                --insecure

                            # 4) Get credentials for the ephemeral cluster
                            cd ../bleachdle
                            BLEACH_CLUSTER=\$(terraform output -raw bleachdle_cluster_name)
                            gcloud container clusters get-credentials "\$BLEACH_CLUSTER" --region "\$GCP_REGION"

                            # 5) Add ephemeral cluster to ArgoCD
                            CURRENT_CONTEXT=\$(kubectl config current-context)

                            # For non-interactive mode, you can do:
                            yes | argocd cluster add "\$CURRENT_CONTEXT" --name bleachdle-ephemeral
                            echo "[Argo] Ephemeral cluster registered under name 'bleachdle-ephemeral'"
                        """
                    }
                }
            }
        }

        // 6) Create Parent Application in ArgoCD
        stage('Create Parent Application in ArgoCD') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh """
                            echo "[Argo] Creating/Syncing Parent Application..."
                            export GOOGLE_APPLICATION_CREDENTIALS=\$GCP_CREDENTIALS_FILE

                            # 1) Retrieve credentials for ArgoCD cluster again
                            cd terraform/argo
                            ARGO_CLUSTER=\$(terraform output -raw argocd_cluster_name)

                            gcloud auth activate-service-account --key-file="\$GCP_CREDENTIALS_FILE"
                            gcloud config set project "\$GCP_PROJECT"
                            gcloud container clusters get-credentials "\$ARGO_CLUSTER" --region "\$GCP_REGION"

                            EXTERNAL_IP=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                            ARGOCD_PASSWORD=\$(kubectl get secret argocd-initial-admin-secret -n argocd -o go-template='{{.data.password | base64decode}}')

                            # 2) Login to ArgoCD
                            argocd login "\$EXTERNAL_IP" \\
                                --username admin \\
                                --password "\$ARGOCD_PASSWORD" \\
                                --insecure

                            # 3) Apply or create the parent application
                            # Use kubectl apply:
                            kubectl apply -n argocd -f ../../argocd-apps/parent-application.yaml

                            echo "[Argo] Parent Application created/updated. Child apps will be managed automatically."
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                echo "Pipeline finished. Workspace cleaned."
            }
            cleanup {
                cleanWs()
            }
        }
    }
}
