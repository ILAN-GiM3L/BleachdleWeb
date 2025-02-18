###############################################################################
# VAULT DEPLOYMENT AND CONFIGURATION
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
    type: ClusterIP
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

resource "null_resource" "vault_init_wait" {
  depends_on = [helm_release.vault]

  provisioner "local-exec" {
    command = "sleep 60"
  }
}

###############################################################################
# VAULT: KV ENGINE + K8S AUTH + POLICY
###############################################################################
resource "vault_mount" "kv" {
  path = "secret"
  type = "kv-v2"
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
  depends_on = [helm_release.vault]
}

resource "vault_policy" "bleachdle_policy" {
  name = "bleachdle-policy"

  policy = <<EOT
path "secret/data/app" {
  capabilities = ["read"]
}
EOT
}

###############################################################################
# FIXED: token_ttl must be a number in seconds. 
###############################################################################
resource "vault_kubernetes_auth_backend_role" "bleachdle_role" {
  role_name                        = "bleachdle-role"
  backend                          = vault_auth_backend.kubernetes.path
  bound_service_account_names      = ["bleachdle-sa"]
  bound_service_account_namespaces = ["default"]

  # 'token_policies' replaced 'policies'
  token_policies = [
    vault_policy.bleachdle_policy.name
  ]

  # 'token_ttl' is numeric (seconds), e.g. 1 hour = 3600
  token_ttl = 3600
}

resource "vault_generic_endpoint" "app_secrets" {
  depends_on = [vault_mount.kv]
  path       = "secret/data/app"

  data_json = jsonencode({
    db_host     = var.db_host,
    db_user     = var.db_user,
    db_password = var.db_password,
    db_name     = var.db_name,
    api_url     = var.api_url
  })
}
