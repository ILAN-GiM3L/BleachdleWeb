###############################################################################
# VAULT DEPLOYMENT AND CONFIGURATION
###############################################################################
# We REMOVE the duplicate provider "google", provider "kubernetes", and
# data "google_client_config" lines. We also don't re-declare the helm provider.
# All of those are now in main.tf.

# We can still reference google_container_cluster.primary because
# it is defined in gke_cluster.tf and is in the same Terraform state.

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

  # The helm provider was declared in main.tf, so we don't need provider blocks here.
  # If you want to specify an alias or anything else, you can do:
  # provider = helm.<alias>  (if you had an aliased provider)

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
# VAULT SETUP: KUBERNETES AUTH & KV SECRETS
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

resource "vault_kubernetes_auth_backend_role" "bleachdle_role" {
  role_name                        = "bleachdle-role"
  backend                          = vault_auth_backend.kubernetes.path
  bound_service_account_names      = ["bleachdle-sa"]
  bound_service_account_namespaces = ["default"]
  policies                         = [vault_policy.bleachdle_policy.name]
  ttl                              = "1h"
}

resource "vault_generic_endpoint" "app_secrets" {
  depends_on = [vault_mount.kv]
  path       = "secret/data/app"

  data_json = jsonencode({
    db_host     = var.db_host
    db_user     = var.db_user
    db_password = var.db_password
    db_name     = var.db_name
    api_url     = var.api_url
  })
}
