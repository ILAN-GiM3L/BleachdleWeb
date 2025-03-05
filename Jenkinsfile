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

        // 1) Check/Create ArgoCD cluster (persistent)
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

        // 2) Import KMS/SA in the "argo" project if needed
        stage('Import KMS & SA') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/argo") {
                            sh """
                                echo "[Argo] Importing KMS & SA if they exist..."
                                export GOOGLE_APPLICATION_CREDENTIALS=\$GCP_CREDENTIALS_FILE

                                gcloud auth activate-service-account --key-file="\$GCP_CREDENTIALS_FILE"
                                gcloud config set project "\$GCP_PROJECT"
                                terraform init

                                terraform import google_kms_key_ring.vault_key_ring     projects/\$GCP_PROJECT/locations/\$GCP_REGION/keyRings/vault-key-ring || true
                                terraform import google_kms_crypto_key.vault_crypto_key projects/\$GCP_PROJECT/locations/\$GCP_REGION/keyRings/vault-key-ring/cryptoKeys/vault-key || true
                                terraform import google_service_account.vault_sa        projects/\$GCP_PROJECT/serviceAccounts/vault-unseal-sa@\$GCP_PROJECT.iam.gserviceaccount.com || true
                                terraform import google_project_iam_member.vault_sa_kms_bind \$GCP_PROJECT/roles/cloudkms.cryptoKeyEncrypterDecrypter/serviceAccount:vault-unseal-sa@\$GCP_PROJECT.iam.gserviceaccount.com || true
                            """
                        }
                    }
                }
            }
        }

        // 3) Install & Expose ArgoCD on persistent cluster
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

                                kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
                                kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

                                echo "[Argo] Patching 'argocd-server' to LoadBalancer..."
                                kubectl rollout status deploy/argocd-server -n argocd --timeout=180s || true
                                kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

                                echo "[Argo] Waiting for external IP..."
                                COUNT=0
                                EXTERNAL_IP=""
                                while [ \$COUNT -lt 30 ]; do
                                  EXTERNAL_IP=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                                  if [ -n "\$EXTERNAL_IP" ]; then
                                    echo "[Argo] Found IP: \$EXTERNAL_IP"
                                    echo "[Argo] Access Argo CD at: http://\$EXTERNAL_IP"
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

        // 4) Destroy Old Bleachdle Ephemeral cluster if it exists
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

        // 5) Create Bleachdle Ephemeral Cluster
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

        // 6) Create Vault GCP Secret in ephemeral cluster (for auto-unseal)
        stage('Create Vault GCP Secret') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh """
                            cd terraform/argo
                            terraform init
                            SA_KEY=\$(terraform output -raw vault_unseal_sa_key)

                            # Switch to ephemeral cluster
                            cd ../bleachdle
                            terraform init
                            CLUSTER_NAME=\$(terraform output -raw bleachdle_cluster_name)

                            export GOOGLE_APPLICATION_CREDENTIALS=\$GCP_CREDENTIALS_FILE
                            gcloud auth activate-service-account --key-file=\$GCP_CREDENTIALS_FILE
                            gcloud config set project "\$GCP_PROJECT"
                            gcloud container clusters get-credentials "\$CLUSTER_NAME" --region "\$GCP_REGION"

                            echo "[Vault GCP Secret] Creating 'vault-gcp-creds' in ephemeral cluster..."
                            kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
                            kubectl -n vault delete secret vault-gcp-creds --ignore-not-found=true
                            kubectl -n vault create secret generic vault-gcp-creds --from-literal=gcp-creds.json="\$SA_KEY"
                        """
                    }
                }
            }
        }

        // NEW 7) Register ephemeral cluster in persistent Argo CD
        stage('Register Ephemeral Cluster in ArgoCD') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh '''
                            echo "[ArgoCD] Register ephemeral cluster in persistent cluster's ArgoCD..."
                            cd terraform/bleachdle
                            terraform init

                            # Grab ephemeral cluster data
                            EPH_NAME=$(terraform output -raw bleachdle_cluster_name)
                            EPH_ENDPOINT=$(terraform output -raw bleachdle_cluster_endpoint)

                            # We'll get ephemeral cluster credentials (token + CA) by using gcloud/kubectl
                            export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
                            gcloud auth activate-service-account --key-file=$GCP_CREDENTIALS_FILE
                            gcloud config set project "$GCP_PROJECT"
                            gcloud container clusters get-credentials "$EPH_NAME" --region "$GCP_REGION"

                            # We'll extract the default service account token + ca cert from ephemeral cluster
                            SA_NAME=$(kubectl get sa default -o jsonpath="{.secrets[0].name}")
                            CA_CRT=$(kubectl get secret "$SA_NAME" -o jsonpath="{.data['ca\\.crt']}")
                            TOKEN=$(kubectl get secret "$SA_NAME" -o jsonpath="{.data['token']}" | base64 --decode)

                            # Now switch context to the persistent cluster (argocd-cluster)
                            cd ../argo
                            terraform init
                            PERSISTENT_CLUSTER=$(terraform output -raw argocd_cluster_name)
                            gcloud container clusters get-credentials "$PERSISTENT_CLUSTER" --region "$GCP_REGION"

                            # Create the Secret in the 'argocd' namespace
                            cat <<EOF > cluster-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: bleachdle-ephemeral
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
data:
  name: $(echo -n "bleachdle-ephemeral" | base64 -w0)
  server: $(echo -n "https://$EPH_ENDPOINT" | base64 -w0)
  config: $(echo -n "bearerToken: $TOKEN\ntlsClientConfig:\n  caData: $CA_CRT\n" | base64 -w0)
EOF

                            echo "Applying ephemeral cluster secret to persistent cluster..."
                            kubectl apply -f cluster-secret.yaml
                        '''
                    }
                }
            }
        }

        // 8) Create the Argo CD Applications in the persistent cluster
        stage('Apply ArgoCD Applications (Vault + Bleachdle)') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh """
                            echo "[ArgoCD] Applying Vault + Bleachdle Applications to persistent cluster..."

                            # Switch context to persistent cluster
                            cd terraform/argo
                            terraform init
                            PERSISTENT_CLUSTER=\$(terraform output -raw argocd_cluster_name)
                            gcloud container clusters get-credentials "\$PERSISTENT_CLUSTER" --region "\$GCP_REGION"

                            # Now apply the Apps in the persistent cluster's argocd namespace
                            kubectl apply -n argocd -f ../../argocd-apps/vault-application.yaml
                            kubectl apply -n argocd -f ../../argocd-apps/bleachdle-application.yaml
                        """
                    }
                }
            }
        }

        // 9) Populate Vault secrets in ephemeral cluster
        stage('Populate Vault Secrets') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh """
                            # Switch context to ephemeral cluster for direct 'vault kv put'
                            cd terraform/bleachdle
                            terraform init
                            CLUSTER_NAME=\$(terraform output -raw bleachdle_cluster_name)

                            export GOOGLE_APPLICATION_CREDENTIALS=\$GCP_CREDENTIALS_FILE
                            gcloud auth activate-service-account --key-file=\$GCP_CREDENTIALS_FILE
                            gcloud config set project "\$GCP_PROJECT"
                            gcloud container clusters get-credentials "\$CLUSTER_NAME" --region "\$GCP_REGION"

                            echo "[Populate Vault] Waiting for vault-0..."
                            kubectl rollout status statefulset/vault-0 -n vault --timeout=180s || true

                            COUNT=0
                            until kubectl -n vault exec vault-0 -- sh -c 'curl -s http://127.0.0.1:8200/v1/sys/health | grep "initialized"'; do
                              echo "Waiting for Vault..."
                              sleep 5
                              COUNT=\$((COUNT+1))
                              if [ \$COUNT -gt 30 ]; then
                                echo "Vault not healthy in time."
                                exit 1
                              fi
                            done

                            kubectl -n vault exec vault-0 -- vault login token=root

                            kubectl -n vault exec vault-0 -- vault kv put bleach/data/app \\
                              db_host="35.246.242.114" \\
                              db_user="root" \\
                              db_password="GeverYozem10072003" \\
                              db_name="Bleach_DB" \\
                              api_url="https://bleachdle-web.oa.r.appspot.com/"
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
        }
    }
}
