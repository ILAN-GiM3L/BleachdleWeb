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

  timeout = 600
  wait    = true

  values = [
    <<EOF
server:
  dev:
    enabled: true
    devToken: "root"

  ui:
    enabled: true

  service:
    type: LoadBalancer
    annotations:
      networking.gke.io/load-balancer-type: "External"

  readinessProbe:
    enabled: true
    path: /v1/sys/health
    initialDelaySeconds: 5
    periodSeconds: 5

  livenessProbe:
    enabled: true
    path: /v1/sys/health

injector:
  enabled: true
EOF
  ]
}

resource "null_resource" "vault_helm_wait" {
  depends_on = [helm_release.vault]

  provisioner "local-exec" {
    command = "sleep 120"
  }
}

data "kubernetes_service" "vault_lb" {
  metadata {
    name      = "vault"
    namespace = "vault"
  }
  depends_on = [helm_release.vault]
}

resource "null_resource" "vault_healthcheck" {
  depends_on = [
    null_resource.vault_helm_wait,
    data.kubernetes_service.vault_lb
  ]

  provisioner "local-exec" {
    command = <<EOT
set -e
VAULT_IP="${data.kubernetes_service.vault_lb.status[0].load_balancer[0].ingress[0].ip}"
echo "Polling Vault LB for readiness in dev mode..."

for i in $(seq 1 15); do
  echo "Attempt $i checking: http://$VAULT_IP:8200/v1/sys/health"
  if curl -s -o /dev/null --connect-timeout 4 "http://$VAULT_IP:8200/v1/sys/health"; then
    echo "Vault dev server is responding. Good to go!"
    exit 0
  fi
  echo "Still not ready. Sleeping 10s..."
  sleep 10
done

echo "Vault did not become ready after 15 tries. Exiting..."
exit 1
EOT
  }
}

output "vault_lb_ip" {
  value = data.kubernetes_service.vault_lb.status[0].load_balancer[0].ingress[0].ip
}

provider "vault" {
  address         = format("http://%s:8200", data.kubernetes_service.vault_lb.status[0].load_balancer[0].ingress[0].ip)
  token           = var.vault_token
  skip_tls_verify = true
}

resource "vault_mount" "kv" {
  path = "bleach"
  type = "kv-v2"

  depends_on = [null_resource.vault_healthcheck]
}

resource "vault_policy" "bleachdle_policy" {
  name       = "bleachdle-policy"
  depends_on = [vault_mount.kv]

  policy = <<EOT
path "bleach/data/app" {
  capabilities = ["read","create","update"]
}
EOT
}

# ✅ **ADDING SECRET STORAGE AFTER POLICY IS READY**
resource "vault_kv_secret_v2" "bleach_app_secrets" {
  mount = vault_mount.kv.path
  name  = "app"

  data_json = jsonencode({
    db_host     = var.db_host
    db_user     = var.db_user
    db_password = var.db_password
    db_name     = var.db_name
    api_url     = var.api_url
  })

  depends_on = [
    vault_mount.kv,
    vault_policy.bleachdle_policy
  ]
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"

  depends_on = [
    vault_mount.kv,
    null_resource.vault_healthcheck
  ]
}

# ----------------------------------------------------------------------
# ADDED: Missing Kubernetes Service Account Resource
# ----------------------------------------------------------------------
resource "kubernetes_service_account" "bleachdle_sa" {
  metadata {
    name      = "bleachdle-sa"
    namespace = "default"
  }
  automount_service_account_token = true
}

# ----------------------------------------------------------------------
# ADDED: Missing Kubernetes Secret Resource
# ----------------------------------------------------------------------
resource "kubernetes_secret" "bleachdle_sa_secret" {
  metadata {
    name      = "bleachdle-sa-token"
    namespace = "default"
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.bleachdle_sa.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"

  depends_on = [kubernetes_service_account.bleachdle_sa]
}

data "kubernetes_secret" "bleachdle_sa_secret" {
  metadata {
    name      = kubernetes_secret.bleachdle_sa_secret.metadata[0].name
    namespace = "default"
  }
  depends_on = [kubernetes_secret.bleachdle_sa_secret]
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  backend            = vault_auth_backend.kubernetes.path
  token_reviewer_jwt = data.kubernetes_secret.bleachdle_sa_secret.data["token"]
  kubernetes_host    = "https://kubernetes.default.svc.cluster.local"
  kubernetes_ca_cert = data.kubernetes_secret.bleachdle_sa_secret.data["ca.crt"]
  issuer             = "https://kubernetes.default.svc.cluster.local"
  disable_iss_validation = true  # ✅ Added this to avoid token validation issues

  depends_on = [
    vault_auth_backend.kubernetes,
    data.kubernetes_secret.bleachdle_sa_secret
  ]
}

resource "vault_kubernetes_auth_backend_role" "bleachdle_role" {
  role_name = "bleachdle-role"
  backend   = vault_auth_backend.kubernetes.path

  bound_service_account_names      = ["bleachdle-sa"]
  bound_service_account_namespaces = ["default"]

  token_policies = [
    vault_policy.bleachdle_policy.name
  ]

  token_ttl              = 3600
  token_max_ttl          = 7200
  token_explicit_max_ttl = 0
  token_period           = 0

  depends_on = [
    vault_kubernetes_auth_backend_config.kubernetes
  ]
}
