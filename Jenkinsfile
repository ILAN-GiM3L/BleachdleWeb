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
        // 1) Clean Workspace
        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }

        // 2) Clone Repository
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
                expression { true } // Always destroy (change condition as needed)
            }
            steps {
                withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                    dir("terraform") {
                        sh '''
                            echo "[Destroy Old] Attempting to destroy old cluster..."
                            export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
                            gcloud auth activate-service-account --key-file="$GCP_CREDENTIALS_FILE"
                            gcloud config set project "bleachdle-web"
                            terraform init
                            terraform destroy -auto-approve || true
                        '''
                    }
                }
            }
        }

        // 4) Terraform Import - automatically import existing resources
        stage('Terraform Import') {
            steps {
                withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                    dir("terraform") {
                        sh '''
                            export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
                            gcloud auth activate-service-account --key-file="$GCP_CREDENTIALS_FILE"
                            gcloud config set project "bleachdle-web"
                            terraform init
                            
                            echo "[Import] Importing KMS Key Ring..."
                            terraform import -input=false google_kms_key_ring.vault_key_ring projects/bleachdle-web/locations/us-central1/keyRings/vault-key-ring || true
                            
                            echo "[Import] Importing KMS Crypto Key..."
                            terraform import -input=false google_kms_crypto_key.vault_crypto_key projects/bleachdle-web/locations/us-central1/keyRings/vault-key-ring/cryptoKeys/vault-key || true
                            
                            echo "[Import] Importing Vault Service Account..."
                            terraform import -input=false google_service_account.vault_sa projects/bleachdle-web/serviceAccounts/vault-unseal-sa@bleachdle-web.iam.gserviceaccount.com || true
                            
                            echo "[Import] Importing IAM Binding..."
                            terraform import -input=false google_project_iam_member.vault_sa_kms_bind projects/bleachdle-web/roles/cloudkms.cryptoKeyEncrypterDecrypter/serviceAccount:vault-unseal-sa@bleachdle-web.iam.gserviceaccount.com || true
                            
                            echo "[Import] Importing Vault SA Key (if exists)..."
                            KEY_ID=$(gcloud iam service-accounts keys list --iam-account="vault-unseal-sa@bleachdle-web.iam.gserviceaccount.com" --project="bleachdle-web" --format="value(name)" | head -n 1 | awk -F'/' '{print $NF}')
                            if [ -n "$KEY_ID" ]; then
                                terraform import -input=false google_service_account_key.vault_sa_key projects/bleachdle-web/serviceAccounts/vault-unseal-sa@bleachdle-web.iam.gserviceaccount.com/keys/$KEY_ID || true
                            else
                                echo "No existing SA key found, will be created by Terraform."
                            fi
                        '''
                    }
                }
            }
        }

        // 5) Terraform Apply to create GKE + KMS + Vault SA
        stage('Terraform Apply') {
            steps {
                withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                    dir("terraform") {
                        sh '''
                            echo "[Terraform Apply] Creating brand new cluster + KMS + SA..."
                            export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
                            gcloud auth activate-service-account --key-file="$GCP_CREDENTIALS_FILE"
                            gcloud config set project "bleachdle-web"
                            
                            terraform init
                            terraform plan -out=tfplan
                            terraform apply -auto-approve tfplan
                        '''
                    }
                }
            }
        }

        // 6) Install Argo CD
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
                                
                                kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
                                kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
                                echo "[Argo CD] Waiting for argocd-server to be ready..."
                                kubectl rollout status deploy/argocd-server -n argocd --timeout=180s || true
                            '''
                        }
                    }
                }
            }
        }

        // 7) Create vault-gcp-creds Secret automatically (no manual kubectl)
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
                                
                                VAULT_SA_KEY=$(terraform output -raw vault_unseal_sa_key)
                                
                                gcloud auth activate-service-account --key-file=$GCP_CREDENTIALS_FILE
                                gcloud config set project "$PROJECT_NAME"
                                gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION_NAME"
                                
                                kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
                                kubectl -n vault delete secret vault-gcp-creds --ignore-not-found=true
                                kubectl -n vault create secret generic vault-gcp-creds --from-literal=gcp-creds.json="$VAULT_SA_KEY"
                                
                                echo "[Vault Secret] Created 'vault-gcp-creds' in vault namespace."
                            '''
                        }
                    }
                }
            }
        }

        // 8) Argo CD Applications (Vault + Bleachdle)
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
                                
                                kubectl apply -f ../argocd-apps/vault-application.yaml -n argocd
                                kubectl apply -f ../argocd-apps/bleachdle-application.yaml -n argocd
                                echo "[Argo CD] Vault & Bleachdle applications submitted. Waiting a bit..."
                            '''
                        }
                    }
                }
            }
        }

        // 9) Populate Vault Secrets
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
                                
                                echo "[Populate Vault] Waiting for vault pod to be ready..."
                                kubectl rollout status statefulset/vault-0 -n vault --timeout=180s || true
                                
                                COUNT=0
                                until kubectl -n vault exec vault-0 -- sh -c 'curl -s http://127.0.0.1:8200/v1/sys/health | grep "initialized"'; do
                                  echo "Waiting for Vault to come up..."
                                  sleep 5
                                  COUNT=$((COUNT+1))
                                  if [ $COUNT -gt 30 ]; then
                                    echo "Vault did not become healthy in time."
                                    exit 1
                                  fi
                                done
                                
                                kubectl -n vault exec vault-0 -- vault login token=root
                                
                                kubectl -n vault exec vault-0 -- vault kv put bleach/data/app \
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
