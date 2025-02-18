###############################################################################
# 1) Install Vault with a LoadBalancer
###############################################################################
resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
  }
}

resource "helm_release" "vault" {
  name       = "vault"
  namespace  = kubernetes_namespace.vault.metadata[0].name
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.24.0"

  values = [
    <<EOF
server:
  ha:
    enabled: true
    replicas: 3
  dataStorage:
    enabled: true
    size: 5Gi
  ui:
    enabled: true
  service:
    type: LoadBalancer
    annotations:
      # Make sure it's an external LB in GCP
      networking.gke.io/load-balancer-type: "External"
  readinessProbe:
    enabled: true
    path: /v1/sys/health
    initialDelaySeconds: 10
    periodSeconds: 5
  livenessProbe:
    enabled: true
    path: /v1/sys/health
  autoUnseal:
    enabled: true
    cloudProvider: gcp
    gcpKms:
      project: "${var.GCP_PROJECT}"
      region: "${var.GCP_REGION}"
      keyRing: "vault-key-ring"
      cryptoKey: "vault-key"
EOF
  ]
}

# Wait a moment for LB provisioning
resource "null_resource" "vault_init_wait" {
  depends_on = [helm_release.vault]

  provisioner "local-exec" {
    command = "sleep 60"
  }
}

###############################################################################
# 2) Discover the external IP of Vault LB
###############################################################################
data "kubernetes_service" "vault_lb" {
  metadata {
    name      = "vault"
    namespace = "vault"
  }
  depends_on = [helm_release.vault]
}

###############################################################################
# 3) Poll the Vault LB until it responds
#    This ensures the service is listening on port 8200.
###############################################################################
resource "null_resource" "vault_healthcheck" {
  depends_on = [
    null_resource.vault_init_wait,
    data.kubernetes_service.vault_lb
  ]

  provisioner "local-exec" {
    # This script attempts a GET on /v1/sys/health up to 10 times
    command = <<EOT
set -e
echo "Polling Vault LB for readiness..."

VAULT_IP="$(terraform output -raw vault_lb_ip || true)"
if [ -z "$VAULT_IP" ]; then
  # fallback if we haven't created an output yet
  # we'll parse from the data source directly
  VAULT_IP="$(echo '${data.kubernetes_service.vault_lb.status[0].load_balancer[0].ingress[0].ip}')"
fi

for i in $(seq 1 10); do
  echo "Attempt $i checking: http://$VAULT_IP:8200/v1/sys/health"
  if curl -s -o /dev/null --connect-timeout 4 "http://$VAULT_IP:8200/v1/sys/health"; then
    echo "Vault is responding. Good to go!"
    exit 0
  fi
  echo "Still not ready. Sleeping 10s..."
  sleep 10
done

echo "Vault did not become ready after 10 tries. Exiting..."
exit 1
EOT
  }
}

###############################################################################
# 4) Output the LB IP from the data source (optional)
###############################################################################
output "vault_lb_ip" {
  # Sometimes GCP LB only sets 'hostname' instead of 'ip'.
  # If you see empty IP, try using 'hostname' below.
  value = data.kubernetes_service.vault_lb.status[0].load_balancer[0].ingress[0].ip
  depends_on = [data.kubernetes_service.vault_lb]
}

###############################################################################
# 5) Now define the Vault provider, referencing that LB IP
###############################################################################
provider "vault" {
  address = format(
    "http://%s:8200",
    data.kubernetes_service.vault_lb.status[0].load_balancer[0].ingress[0].ip
  )
  token           = var.vault_token
  skip_tls_verify = true
}

###############################################################################
# 6) Vault resources, depends_on = vault_healthcheck
###############################################################################
resource "vault_mount" "kv" {
  path = "secret"
  type = "kv-v2"
  depends_on = [null_resource.vault_healthcheck]
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
  depends_on = [
    vault_mount.kv,
    null_resource.vault_healthcheck
  ]
}

resource "vault_policy" "bleachdle_policy" {
  name = "bleachdle-policy"
  depends_on = [null_resource.vault_healthcheck]

  policy = <<EOT
path "secret/data/app" {
  capabilities = ["read"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "bleachdle_role" {
  role_name                        = "bleachdle-role"
  backend                          = vault_auth_backend.kubernetes.path
  bound_service_account_names      = ["bleachdle-sa"]
  bound_service_account_namespaces = ["default"]

  token_policies = [
    vault_policy.bleachdle_policy.name
  ]
  token_ttl = 3600

  depends_on = [
    vault_auth_backend.kubernetes,
    vault_policy.bleachdle_policy,
    null_resource.vault_healthcheck
  ]
}

resource "vault_generic_endpoint" "app_secrets" {
  path = "secret/data/app"

  data_json = jsonencode({
    db_host     = var.db_host
    db_user     = var.db_user
    db_password = var.db_password
    db_name     = var.db_name
    api_url     = var.api_url
  })

  depends_on = [
    vault_mount.kv,
    vault_auth_backend.kubernetes,
    vault_policy.bleachdle_policy,
    vault_kubernetes_auth_backend_role.bleachdle_role,
    null_resource.vault_healthcheck
  ]
}
