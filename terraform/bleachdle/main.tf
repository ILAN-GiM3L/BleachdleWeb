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

data "google_client_config" "default" {}


