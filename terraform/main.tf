terraform {
  backend "gcs" {
    bucket = "bleachdle-terraform-state-bucket"
    prefix = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }

  required_version = ">= 1.0.0"
}

provider "google" {
  project = var.GCP_PROJECT
  region  = var.GCP_REGION
}

data "google_client_config" "default" {}

resource "random_id" "key_id" {
  byte_length = 8
}

# -------------------------------------------------
# GOOGLE KMS for Vault auto-unseal
# -------------------------------------------------
resource "google_kms_key_ring" "vault" {
  name     = "vault-key-ring"
  project  = var.GCP_PROJECT
  location = var.GCP_REGION
}

resource "google_kms_crypto_key" "vault" {
  name            = "vault-key"
  key_ring        = google_kms_key_ring.vault.id
  rotation_period = "7776000s"  # ~ 90 days
}

# Create a Service Account for Vault auto-unseal
resource "google_service_account" "vault_unseal" {
  account_id   = "vault-unseal-sa"
  display_name = "Vault Auto Unseal Service Account"
}

# Provide this SA with Cloud KMS encrypt/decrypt
resource "google_project_iam_member" "vault_unseal_kms" {
  project = var.GCP_PROJECT
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.vault_unseal.email}"
}

# This key will be used inside the Vault container to talk to GCP KMS
resource "google_service_account_key" "vault_unseal_key" {
  service_account_id = google_service_account.vault_unseal.name
}

# ----------------------------------------------------------------------
# KUBERNETES & HELM providers
# ----------------------------------------------------------------------
provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

output "gke_cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}

output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}

output "gcp_project" {
  value = var.GCP_PROJECT
}

output "gcp_region" {
  value = var.GCP_REGION
}

# Provide the unseal key JSON as a Terraform output so Jenkins can grab it
output "vault_unseal_sa_key" {
  value     = google_service_account_key.vault_unseal_key.private_key
  sensitive = true
}
