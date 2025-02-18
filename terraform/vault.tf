# Providers
provider "google" {
  project     = var.GCP_PROJECT           # Google Cloud Project ID
  region      = var.GCP_REGION            # Google Cloud region
}

provider "kubernetes" {
  host                   = google_container_cluster.primary.endpoint
  cluster_ca_certificate = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = google_container_cluster.primary.endpoint
    cluster_ca_certificate = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
    token                  = data.google_client_config.default.access_token
  }
}

# Data for GKE Cluster
data "google_client_config" "default" {}

# Fetch the GKE cluster details
data "google_container_cluster" "primary" {
  name     = google_container_cluster.primary.name
  location = var.GCP_REGION
}

# Create a namespace for Vault
resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
  }
}

# Vault Installation using Helm
resource "helm_release" "vault" {
  name       = "vault"
  namespace  = kubernetes_namespace.vault.metadata[0].name
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.24.0"  # Updated Helm chart version for latest Vault release

  values = [
    <<EOF
    server:
      ha:
        enabled: true
        replicas: 3
      dataStorage:
        enabled: true
        size: 5Gi # Adjusted storage size based on project requirements
      ui:
        enabled: true # Enable UI for easier management
      service:
        type: ClusterIP # Keep Vault internal within the cluster
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

# Vault Initialization
resource "null_resource" "vault_init_wait" {
  depends_on = [helm_release.vault]

  provisioner "local-exec" {
    command = "sleep 60"  # Adjusted wait time based on deployment behavior
  }
}

# Enable Key-Value (KV) Secret Engine
resource "vault_mount" "kv" {
  path = "secret"
  type = "kv-v2"  # KV v2 for versioned secrets
}

# Enable Kubernetes Authentication for Vault
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

# Kubernetes Authentication Role for Vault
resource "vault_kubernetes_auth_backend_role" "example_role" {
  role_name                     = "example-role"
  backend                       = vault_auth_backend.kubernetes.path
  bound_service_account_names    = ["vault-auth"]  # Service account name in Kubernetes
  bound_service_account_namespaces = ["vault"]
  policies                      = ["default"]
  ttl                           = "1h"
}

# Write Secrets into Vault's KV Store
resource "vault_generic_endpoint" "app_secrets" {
  path = "secret/data/app"
  data_json = jsonencode({
    db_host     = var.db_host,
    db_user     = var.db_user,
    db_password = var.db_password,
    db_name     = var.db_name,
    api_url     = var.api_url
  })
}
