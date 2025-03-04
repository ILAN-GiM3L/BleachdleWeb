pipeline {
    agent any

    environment {
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
                            credentialsId: 'Github-cred'  // or your GitHub credentials for private repo
                        ]]
                    ])
                }
            }
        }

        // 3) Create/Update ArgoCD Cluster (Persistent)
        //
        // We run "terraform apply" but only target the argocd cluster resources 
        // so that we won't accidentally destroy them later. 
        // If the cluster already exists, terraform will leave it alone.
        stage('Create or Update ArgoCD Cluster') {
            steps {
                withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                    dir("terraform") {
                        sh '''
                            echo "[ArgoCD Cluster] Ensuring the ArgoCD cluster exists..."
                            export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
                            gcloud auth activate-service-account --key-file="$GCP_CREDENTIALS_FILE"
                            gcloud config set project "bleachdle-web"
                            
                            terraform init
                            # Apply only the resources for argocd cluster by targeting them:
                            terraform apply -auto-approve -target=google_container_cluster.argocd -target=google_container_node_pool.argocd_nodes || true
                        '''
                    }
                }
            }
        }

        // 4) Install Argo CD (only if not previously installed)
        //
        // You can add conditions or checks if you only want to do this once. 
        // For simplicity, let's do a "kubectl apply" each time, 
        // but it won't harm if the objects are unchanged.
        stage('Install Argo CD on ArgoCD Cluster (Once)') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform") {
                            sh '''
                                echo "[Argo CD] Installing Argo CD in the argocd cluster..."
                                export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
                                # Retrieve the cluster name and region from outputs
                                PROJECT_NAME=$(terraform output -raw gcp_project)
                                REGION_NAME=$(terraform output -raw gcp_region)
                                ARGO_CLUSTER=$(terraform output -raw argocd_cluster_name)
                                
                                gcloud auth activate-service-account --key-file=$GCP_CREDENTIALS_FILE
                                gcloud config set project "$PROJECT_NAME"
                                gcloud components install gke-gcloud-auth-plugin --quiet || true
                                gcloud container clusters get-credentials "$ARGO_CLUSTER" --region "$REGION_NAME"
                                
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

        // 5) Destroy Old Bleachdle Ephemeral Cluster
        stage('Destroy Old Bleachdle Cluster') {
            when {
                expression { true } // Always destroy ephemeral cluster
            }
            steps {
                withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                    dir("terraform") {
                        sh '''
                            echo "[Destroy Old] Attempting to destroy old Bleachdle ephemeral cluster..."
                            export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
                            gcloud auth activate-service-account --key-file="$GCP_CREDENTIALS_FILE"
                            gcloud config set project "bleachdle-web"
                            terraform init
                            # Only target the ephemeral cluster resources so we don't wipe out ArgoCD:
                            terraform destroy -auto-approve -target=google_container_node_pool.bleachdle_ephemeral_nodes -target=google_container_cluster.bleachdle_ephemeral || true
                        '''
                    }
                }
            }
        }

        // 6) Terraform Import (KMS, SA, etc.) except ephemeral cluster
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
                            terraform import -input=false google_project_iam_member.vault_sa_kms_bind bleachdle-web/roles/cloudkms.cryptoKeyEncrypterDecrypter/serviceAccount:vault-unseal-sa@bleachdle-web.iam.gserviceaccount.com || true

                            echo "[Import] Skipping SA Key import (resource does not support import)."
                        '''
                    }
                }
            }
        }

        // 7) Terraform Apply to create new Bleachdle ephemeral cluster
        stage('Terraform Apply (Ephemeral)') {
            steps {
                withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                    dir("terraform") {
                        sh '''
                            echo "[Terraform Apply] Creating brand new ephemeral cluster + KMS + SA..."
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

        // 8) Create vault-gcp-creds Secret automatically (no manual kubectl)
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
                                CLUSTER_NAME=$(terraform output -raw bleachdle_cluster_name)
                                
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

        // 9) Argo CD Applications (Vault + Bleachdle) on the ephemeral cluster
        //
        // *IMPORTANT*: Note that your "destination.server" in the YAML 
        // is "https://kubernetes.default.svc". This implies it uses 
        // the in-cluster config. So you actually want ArgoCD to manage 
        // resources on a different cluster. That typically requires 
        // registering the ephemeral cluster as an External Cluster 
        // in ArgoCD. For brevity, we just apply the application definitions 
        // to the ephemeral cluster. But be aware if ArgoCD is physically 
        // running in a separate cluster, you need to set up a "Cluster Secret" 
        // in ArgoCD to point to your ephemeral cluster.
        stage('Argo CD Applications') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform") {
                            sh '''
                                export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
                                PROJECT_NAME=$(terraform output -raw gcp_project)
                                REGION_NAME=$(terraform output -raw gcp_region)
                                CLUSTER_NAME=$(terraform output -raw bleachdle_cluster_name)
                                
                                gcloud auth activate-service-account --key-file=$GCP_CREDENTIALS_FILE
                                gcloud config set project "$PROJECT_NAME"
                                gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION_NAME"
                                
                                kubectl apply -f ../argocd-apps/vault-application.yaml -n argocd
                                kubectl apply -f ../argocd-apps/bleachdle-application.yaml -n argocd
                                echo "[Argo CD] Vault & Bleachdle applications submitted."
                            '''
                        }
                    }
                }
            }
        }

        // 10) Populate Vault Secrets
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
                                CLUSTER_NAME=$(terraform output -raw bleachdle_cluster_name)
                                
                                gcloud auth activate-service-account --key-file=$GCP_CREDENTIALS_FILE
                                gcloud config set project "$PROJECT_NAME"
                                gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION_NAME"
                                
                                echo "[Populate Vault] Waiting for vault pod to be ready..."
                                # Since you are using 'StatefulSet vault-0' in your app,
                                # let's wait for that:
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
                                  db_host="35.246.242.114" \
                                  db_user="root" \
                                  db_password="GeverYozem10072003" \
                                  db_name="Bleach_DB" \
                                  api_url="https://bleachdle-web.oa.r.appspot.com/"
                                
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
