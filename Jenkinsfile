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
                                export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"

                                gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                                gcloud config set project "${GCP_PROJECT}"
                                terraform init

                                set +e
                                gcloud container clusters describe argocd-cluster --region "${GCP_REGION}" > /dev/null 2>&1
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

        
        // 3) Destroy Old Bleachdle Ephemeral cluster if it exists
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
        stage('Import Existing KeyRing & Key') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        dir("terraform/bleachdle") {
                        sh """
                            export GOOGLE_APPLICATION_CREDENTIALS="\${GCP_CREDENTIALS_FILE}"
                            gcloud auth activate-service-account --key-file="\${GCP_CREDENTIALS_FILE}"
                            gcloud config set project "\${GCP_PROJECT}"

                            terraform init

                            terraform import google_kms_key_ring.vault_key_ring \
                            projects/\${GCP_PROJECT}/locations/\${GCP_REGION}/keyRings/vault-key-ring || true

                            terraform import google_kms_crypto_key.vault_key \
                            projects/\${GCP_PROJECT}/locations/\${GCP_REGION}/keyRings/vault-key-ring/cryptoKeys/vault-key || true
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

        stage('Prepare ephemeral cluster for Vault') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh """
                            cd terraform/bleachdle
                            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                            gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                            gcloud container clusters get-credentials bleachdle-cluster --region "${GCP_REGION}"

                            # create 'vault' namespace if missing
                            kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

                            # create the secret from GCP creds
                            kubectl create secret generic vault-gcp-creds \
                                --from-file=gcp-creds.json="${GCP_CREDENTIALS_FILE}" \
                                --namespace vault
                        """
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
                            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"

                            # 1) Get credentials for Argocd cluster
                            cd terraform/argo
                            ARGO_CLUSTER=\$(terraform output -raw argocd_cluster_name)

                            gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                            gcloud config set project "${GCP_PROJECT}"
                            gcloud container clusters get-credentials "\$ARGO_CLUSTER" --region "${GCP_REGION}"

                            # 2) Extract ArgoCD service IP and admin password
                            EXTERNAL_IP=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                            ARGOCD_PASSWORD=\$(kubectl get secret argocd-initial-admin-secret -n argocd -o go-template='{{.data.password | base64decode}}')

                            # 3) Login to ArgoCD CLI
                            argocd login "\$EXTERNAL_IP" \\
                                --username admin \\
                                --password "\$ARGOCD_PASSWORD" \\
                                --insecure

                            # 4) Get credentials for the ephemeral cluster
                            cd ../bleachdle
                            BLEACH_CLUSTER=\$(terraform output -raw bleachdle_cluster_name)
                            gcloud container clusters get-credentials "\$BLEACH_CLUSTER" --region "${GCP_REGION}"

                            # 5) Add ephemeral cluster to ArgoCD
                            CURRENT_CONTEXT=\$(kubectl config current-context)
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
                            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"

                            # 1) Retrieve credentials for ArgoCD cluster again
                            cd terraform/argo
                            ARGO_CLUSTER=\$(terraform output -raw argocd_cluster_name)

                            gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                            gcloud config set project "${GCP_PROJECT}"
                            gcloud container clusters get-credentials "\$ARGO_CLUSTER" --region "${GCP_REGION}"

                            EXTERNAL_IP=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                            ARGOCD_PASSWORD=\$(kubectl get secret argocd-initial-admin-secret -n argocd -o go-template='{{.data.password | base64decode}}')

                            # 2) Login to ArgoCD
                            argocd login "\$EXTERNAL_IP" \\
                                --username admin \\
                                --password "\$ARGOCD_PASSWORD" \\
                                --insecure

                            # 3) Apply or create the parent application
                            kubectl apply -n argocd -f ../../argocd-apps/parent-application.yaml

                            echo "[Argo] Parent Application created/updated. Child apps will be managed automatically."
                        """
                    }
                }
            }
        }

        stage('Wait for Bleachdle to be Deployed') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh """
                            cd terraform/bleachdle
                            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                            gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                            gcloud container clusters get-credentials bleachdle-cluster --region "${GCP_REGION}"
                            
                            echo "Waiting up to 2 minutes for bleachdle-sa to appear..."
                            COUNT=0
                            while [ \$COUNT -lt 12 ]; do
                                SA_SECRET=\$(kubectl get secret -n default | grep 'bleachdle-sa-token' || true)
                                if [ -n "\$SA_SECRET" ]; then
                                    echo "bleachdle-sa secret found!"
                                    break
                                else
                                    echo "bleachdle-sa secret not found yet..."
                                    sleep 10
                                    COUNT=\$((COUNT+1))
                                fi
                            done
                        """
                    }
                }
            }
        }

        stage('Initialize & Configure Vault') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                        sh """
                            cd terraform/bleachdle
                            export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDENTIALS_FILE}"
                            gcloud auth activate-service-account --key-file="${GCP_CREDENTIALS_FILE}"
                            gcloud container clusters get-credentials bleachdle-cluster --region "${GCP_REGION}"

                            COUNT=0
                            while [ \$COUNT -lt 12 ]; do
                                POD_READY=\$(kubectl get pods -n vault -l app.kubernetes.io/name=vault --field-selector=status.phase=Running | grep 'vault-' | wc -l)
                                if [ "\$POD_READY" -gt 0 ]; then
                                    echo "Vault pod is Running"
                                    break
                                else
                                    echo "Waiting for Vault pod..."
                                    sleep 10
                                    COUNT=\$((COUNT+1))
                                fi
                            done

                            # Port-forward in background
                            kubectl port-forward svc/vault -n vault 8200:8200 > /tmp/vault-pf.log 2>&1 &
                            sleep 5
                        """

                        // 4) Initialize Vault if not already done
                        sh """
                            export VAULT_ADDR="http://127.0.0.1:8200"
                            set +e
                            vault status 2>&1 | grep 'Initialized.*true'
                            IS_INIT=\$?
                            set -e

                            if [ "\$IS_INIT" -eq 0 ]; then
                                echo "[Vault] Already initialized."
                            else
                                echo "[Vault] Not initialized; initializing now..."
                                INIT_OUTPUT=\$(vault operator init -key-shares=1 -key-threshold=1 -format=json)
                                echo "\$INIT_OUTPUT" > /tmp/init.json
                                ROOT_TOKEN=\$(echo "\$INIT_OUTPUT" | jq -r '.root_token')
                                UNSEAL_KEY=\$(echo "\$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')

                                vault operator unseal "\$UNSEAL_KEY"
                                vault login "\$ROOT_TOKEN"
                            fi
                        """

                        // 5) Now set up bleachdle-policy, add secrets, etc.
                        sh """
                            export VAULT_ADDR="http://127.0.0.1:8200"

                            echo "[Vault] Writing bleachdle-policy..."
                            vault policy write bleachdle-policy - <<EOF
path "bleach/data/app" {
  capabilities = ["create", "update", "read", "list", "delete"]
}
EOF

                            echo "[Vault] Creating secrets at bleach/data/app..."
                            vault kv put bleach/data/app \\
                                db_host="mydbhost.example" \\
                                db_user="mydbuser" \\
                                db_password="mydbpass" \\
                                db_name="mydbname" \\
                                api_url="https://my-api-url"
                        """

                        // 6) **Enable & Configure Kubernetes Auth**
                        sh """
                            echo "[Vault] Enabling Kubernetes auth method..."
                            export VAULT_ADDR="http://127.0.0.1:8200"
                            vault auth enable kubernetes || true

                            echo "[Vault] Retrieving bleachdle-sa token..."
                            SA_SECRET_NAME=\$(kubectl get secret -n default | grep 'bleachdle-sa-token' | awk '{print \$1}')
                            SA_JWT_TOKEN=\$(kubectl get secret "\$SA_SECRET_NAME" -n default -o jsonpath='{.data.token}' | base64 --decode)
                            KUBE_CA_CERT=\$(kubectl get secret "\$SA_SECRET_NAME" -n default -o jsonpath='{.data.ca\\.crt}' | base64 --decode)

                            echo "[Vault] Configuring auth/kubernetes config..."
                            vault write auth/kubernetes/config \\
                                token_reviewer_jwt="\$SA_JWT_TOKEN" \\
                                kubernetes_host="https://kubernetes.default.svc" \\
                                kubernetes_ca_cert="\$KUBE_CA_CERT" \\
                                issuer="https://kubernetes.default.svc.cluster.local"

                            echo "[Vault] Creating bleachdle-role to map bleachdle-sa -> bleachdle-policy..."
                            vault write auth/kubernetes/role/bleachdle-role \\
                                bound_service_account_names=bleachdle-sa \\
                                bound_service_account_namespaces=default \\
                                policies=bleachdle-policy \\
                                ttl=1h
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
