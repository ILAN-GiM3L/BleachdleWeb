#########################################
# vault.tf
#########################################

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
    # If you want an external LB on GCP, optionally add an annotation:
    # annotations:
    #   networking.gke.io/load-balancer-type: "External"
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

# Wait a bit for the pod/service to come up
resource "null_resource" "vault_init_wait" {
  depends_on = [helm_release.vault]
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

#########################################
# Data resource: discover LB IP of "vault"
#########################################
data "kubernetes_service" "vault_lb" {
  metadata {
    name      = "vault"
    namespace = "vault"
  }
  depends_on = [helm_release.vault]
}

#########################################
# Vault provider referencing LB IP
#########################################
provider "vault" {
  address         = format("http://%s:8200", data.kubernetes_service.vault_lb.status[0].load_balancer[0].ingress[0].ip)
  token           = var.vault_token
  skip_tls_verify = true
}

#########################################
# Vault resources
#########################################
resource "vault_mount" "kv" {
  path = "secret"
  type = "kv-v2"
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
  depends_on = [vault_mount.kv]
}

resource "vault_policy" "bleachdle_policy" {
  name = "bleachdle-policy"

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

  # Use token_policies and numeric token_ttl
  token_policies = [
    vault_policy.bleachdle_policy.name
  ]
  token_ttl = 3600
}

resource "vault_generic_endpoint" "app_secrets" {
  depends_on = [
    vault_mount.kv,
    vault_auth_backend.kubernetes,
    vault_policy.bleachdle_policy,
    vault_kubernetes_auth_backend_role.bleachdle_role
  ]

  path = "secret/data/app"

  data_json = jsonencode({
    db_host     = var.db_host
    db_user     = var.db_user
    db_password = var.db_password
    db_name     = var.db_name
    api_url     = var.api_url
  })
}
