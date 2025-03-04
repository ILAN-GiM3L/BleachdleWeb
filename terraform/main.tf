###############################################################################
# main.tf
###############################################################################
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

###############################################################################
# Google Provider
###############################################################################
provider "google" {
  project = var.GCP_PROJECT
  region  = var.GCP_REGION
}

resource "google_project_service" "cloud_resource_manager" {
  project            = var.GCP_PROJECT
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

data "google_client_config" "default" {}

# We still keep a random_id for the  naming
resource "random_id" "key_id" {
  byte_length = 8
}

##################################################
# Declarative creation of KMS Key Ring if missing
##################################################
resource "google_kms_key_ring" "vault_key_ring" {
  name     = "vault-key-ring"
  location = var.GCP_REGION
  project  = var.GCP_PROJECT
}
# [CHANGE] Replaced the null_resource block that used local-exec for the KMS key ring.

##################################################
# Declarative creation of KMS Crypto Key if missing
##################################################
resource "google_kms_crypto_key" "vault_crypto_key" {
  name     = "vault-key"
  key_ring = google_kms_key_ring.vault_key_ring.id
  purpose  = "ENCRYPT_DECRYPT"
  # If you want a rotation period (e.g. 90 days), uncomment the following line:
  # rotation_period = "7776000s"
}
# [CHANGE] Replaced the null_resource block that created the crypto key.

##################################################
# Declarative creation of Vault SA if missing
##################################################
resource "google_service_account" "vault_sa" {
  account_id   = "vault-unseal-sa"
  display_name = "Vault Auto Unseal Service Account"
  project      = var.GCP_PROJECT
}
# [CHANGE] Replaced the null_resource block that checked and created the SA.

##################################################
# Declarative binding of SA -> KMS Encrypter/Decrypter role
##################################################
resource "google_project_iam_member" "vault_sa_kms_bind" {
  project = var.GCP_PROJECT
  member  = "serviceAccount:${google_service_account.vault_sa.email}"
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
}
# [CHANGE] Replaced the null_resource block that conditionally added the IAM binding.
# NOTE: The import ID for this resource now must use the format:
# projects/bleachdle-web/roles/cloudkms.cryptoKeyEncrypterDecrypter/members/serviceAccount:vault-unseal-sa@bleachdle-web.iam.gserviceaccount.com

##################################################
# Declarative creation of SA key
##################################################
resource "google_service_account_key" "vault_sa_key" {
  service_account_id = google_service_account.vault_sa.name

  lifecycle {
    create_before_destroy = true
    # [CHANGE] Removed ignore_changes for private_key/public_key because these are computed.
  }
}
# [CHANGE] Replaced the null_resource that created a local file and the data "local_file" block.
# The output below now directly references this native resource.


###############################################################################
# Outputs
###############################################################################
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
  value     = google_service_account_key.vault_sa_key.private_key
  sensitive = true
}
# [CHANGE] Now directly outputs the private key from the native SA key resource.
