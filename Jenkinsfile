pipeline {
    agent any

    environment {
        // Let Jenkins see Docker and gcloud
        PATH = "/usr/local/bin:/opt/homebrew/bin:/Users/ilangimelfarb/Downloads/google-cloud-sdk/bin:$PATH"

        DOCKERHUB_REPO = 'ilangimel/bleachdle-web-app'
        DOCKERHUB_USERNAME = credentials('DOCKERHUB_USERNAME')
        DOCKERHUB_PASSWORD = credentials('DOCKERHUB_PASSWORD')
        IMAGE_NAME = 'ilangimel/bleachdle-web-app'
        VERSION = "${BUILD_NUMBER}"
    }

    stages {
        // 1) Clean
        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }

        // 2) Clone
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

        // 3) [Optional] Destroy old cluster if it exists
        stage('Destroy Old Cluster') {
            when {
                expression { true } // Always destroy (change if you want a condition)
            }
            steps {
                withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                    dir("terraform") {
                        sh '''
                            echo "[Destroy Old] Attempting to destroy old cluster..."
                            export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
                            terraform init
                            terraform destroy -auto-approve || true
                        '''
                    }
                }
            }
        }

        // 4) Terraform apply to create GKE + KMS + Vault SA
        stage('Terraform Apply') {
            steps {
                withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                    dir("terraform") {
                        sh '''
                            echo "[Terraform Apply] Creating brand new cluster + KMS + SA..."
                            export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE

                            terraform init
                            terraform plan -out=tfplan
                            terraform apply -auto-approve tfplan
                        '''
                    }
                }
            }
        }

        // 5) Install Argo CD
        stage('Install Argo CD') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform") {
                            sh '''
                                export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE

                                PROJECT_NAME=$(terraform output -raw gcp_project)
                                REGION_NAME=$(terraform output -raw gcp_region)
                                CLUSTER_NAME=$(terraform output -raw gke_cluster_name)

                                echo "[Argo CD] Authenticating gcloud..."
                                gcloud auth activate-service-account --key-file=$GCP_CREDENTIALS_FILE
                                gcloud config set project "$PROJECT_NAME"
                                gcloud components install gke-gcloud-auth-plugin --quiet || true
                                gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION_NAME"

                                # Create the argocd namespace
                                kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

                                # Install Argo CD
                                kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

                                echo "[Argo CD] Waiting for argocd-server to be ready..."
                                kubectl rollout status deploy/argocd-server -n argocd --timeout=180s || true
                            '''
                        }
                    }
                }
            }
        }

        // 6) Create vault-gcp-creds Secret automatically (no manual kubectl)
        stage('Create Vault GCP Secret') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform") {
                            sh '''
                                echo "[Create Vault Secret] Creating K8s secret vault-gcp-creds in 'vault' namespace..."

                                export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE

                                PROJECT_NAME=$(terraform output -raw gcp_project)
                                REGION_NAME=$(terraform output -raw gcp_region)
                                CLUSTER_NAME=$(terraform output -raw gke_cluster_name)

                                # Grab the Vault SA key from Terraform output
                                VAULT_SA_KEY=$(terraform output -raw vault_unseal_sa_key)

                                echo "[Kube Config] Authenticating..."
                                gcloud auth activate-service-account --key-file=$GCP_CREDENTIALS_FILE
                                gcloud config set project "$PROJECT_NAME"
                                gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION_NAME"

                                # Create the 'vault' namespace if not exists
                                kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

                                # Create the secret from the service account key
                                kubectl -n vault delete secret vault-gcp-creds --ignore-not-found=true
                                kubectl -n vault create secret generic vault-gcp-creds \
                                  --from-literal=gcp-creds.json="$VAULT_SA_KEY"

                                echo "[Vault Secret] Created 'vault-gcp-creds' in vault namespace."
                            '''
                        }
                    }
                }
            }
        }

        // 7) Argo CD Applications (Vault + Bleachdle)
        stage('Argo CD Applications') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform") {
                            sh '''
                                export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE

                                PROJECT_NAME=$(terraform output -raw gcp_project)
                                REGION_NAME=$(terraform output -raw gcp_region)
                                CLUSTER_NAME=$(terraform output -raw gke_cluster_name)

                                gcloud auth activate-service-account --key-file=$GCP_CREDENTIALS_FILE
                                gcloud config set project "$PROJECT_NAME"
                                gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION_NAME"

                                # Apply Argo CD Applications
                                kubectl apply -f ../argocd-apps/vault-application.yaml -n argocd
                                kubectl apply -f ../argocd-apps/bleachdle-application.yaml -n argocd

                                echo "[Argo CD] Vault & Bleachdle applications submitted. Waiting a bit..."
                            '''
                        }
                    }
                }
            }
        }

        // 8) Populate Vault secrets
        stage('Populate Vault Secrets') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform") {
                            sh '''
                                echo "[Populate Vault] Logging into Vault and setting secrets..."

                                export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE

                                PROJECT_NAME=$(terraform output -raw gcp_project)
                                REGION_NAME=$(terraform output -raw gcp_region)
                                CLUSTER_NAME=$(terraform output -raw gke_cluster_name)

                                gcloud auth activate-service-account --key-file=$GCP_CREDENTIALS_FILE
                                gcloud config set project "$PROJECT_NAME"
                                gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION_NAME"

                                # Wait for vault pods to be ready
                                echo "[Populate Vault] Waiting for vault pod to be ready..."
                                kubectl rollout status statefulset/vault-0 -n vault --timeout=180s || true

                                # We'll just do a loop check on the health endpoint
                                COUNT=0
                                until kubectl -n vault exec vault-0 -- \
                                  sh -c 'curl -s http://127.0.0.1:8200/v1/sys/health | grep "initialized"'; do
                                  echo "Waiting for Vault to come up..."
                                  sleep 5
                                  COUNT=$((COUNT+1))
                                  if [ $COUNT -gt 30 ]; then
                                    echo "Vault did not become healthy in time."
                                    exit 1
                                  fi
                                done

                                # Now login using the root token from Helm chart's initialRootToken
                                kubectl -n vault exec vault-0 -- vault login token=root

                                # Insert your secrets
                                kubectl -n vault exec vault-0 -- \
                                  vault kv put bleach/data/app \
                                    db_host="34.165.72.240" \
                                    db_user="root" \
                                    db_password="GeverYozem10072003" \
                                    db_name="Bleach_DB" \
                                    api_url="http://bleachdle-project.ey.r.appspot.com/"

                                echo "[Populate Vault] Secrets set. Bleachdle pods can now pull them."
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
                echo "Pipeline finished. Workspace cleaned."
            }
        }
    }
}
