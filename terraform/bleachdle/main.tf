###############################################################################
# terraform/bleachdle/main.tf
###############################################################################
terraform {
  backend "gcs" {
    # Notice a different prefix for the ephemeral state
    bucket = "bleachdle-terraform-state-bucket"
    prefix = "terraform/bleachdle/state"
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

resource "google_kms_key_ring" "vault_key_ring" {
  name     = "vault-key-ring"
  location = var.GCP_REGION
}

resource "google_kms_crypto_key" "vault_key" {
  name            = "vault-key"
  key_ring        = google_kms_key_ring.vault_key_ring.id
  rotation_period = "100000s"
  purpose         = "ENCRYPT_DECRYPT"
}

# 1. Allow the Kubernetes service account (bleachdle-sa) to impersonate terraform-admin service account
resource "google_iam_policy_binding" "bleachdle_sa_impersonation" {
  role    = "roles/iam.serviceAccountTokenCreator"
  members = [
    "serviceAccount:bleachdle-sa@${var.GCP_PROJECT}.iam.gserviceaccount.com"
  ]
  resource = "projects/${var.GCP_PROJECT}/serviceAccounts/terraform-admin@${var.GCP_PROJECT}.iam.gserviceaccount.com"
}

# 2. Grant KMS Crypto Key Encrypter/Decrypter permissions to the Kubernetes service account (bleachdle-sa)
resource "google_kms_crypto_key_iam_member" "bleachdle_sa_kms_permissions" {
  crypto_key_id = google_kms_crypto_key.vault_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:bleachdle-sa@${var.GCP_PROJECT}.iam.gserviceaccount.com"
}




data "google_client_config" "default" {}


