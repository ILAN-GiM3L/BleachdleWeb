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

# We still keep a random_id for the cluster naming
resource "random_id" "key_id" {
  byte_length = 8
}

##################################################
# Imperative creation of KMS Key Ring if missing
##################################################
resource "null_resource" "vault_key_ring" {
  provisioner "local-exec" {
    command = <<EOT
      set -e
      echo "[Check KMS Key Ring] Checking if vault-key-ring already exists..."
      if gcloud kms keyrings describe vault-key-ring \
         --location="${var.GCP_REGION}" \
         --project="${var.GCP_PROJECT}" >/dev/null 2>&1; then
        echo "Key ring 'vault-key-ring' already exists, skipping creation."
      else
        echo "Creating Key Ring 'vault-key-ring'..."
        gcloud kms keyrings create vault-key-ring \
          --location="${var.GCP_REGION}" \
          --project="${var.GCP_PROJECT}"
      fi
    EOT
  }
}

##################################################
# Imperative creation of KMS Crypto Key if missing
##################################################
resource "null_resource" "vault_crypto_key" {
  depends_on = [null_resource.vault_key_ring]

  provisioner "local-exec" {
    command = <<EOT
      set -e
      echo "[Check Crypto Key] Checking if 'vault-key' already exists..."
      if gcloud kms keys describe vault-key \
         --keyring="vault-key-ring" \
         --location="${var.GCP_REGION}" \
         --project="${var.GCP_PROJECT}" >/dev/null 2>&1; then
        echo "Crypto Key 'vault-key' already exists, skipping creation."
      else
        echo "Creating Crypto Key 'vault-key'..."
        gcloud kms keys create vault-key \
          --keyring="vault-key-ring" \
          --location="${var.GCP_REGION}" \
          --purpose="encryption" \
          --project="${var.GCP_PROJECT}"

        # If you want a rotation period (e.g. 90 days):
        # gcloud kms keys update vault-key \
        #   --keyring="vault-key-ring" \
        #   --location="${var.GCP_REGION}" \
        #   --rotation-period="7776000s" \
        #   --project="${var.GCP_PROJECT}"
      fi
    EOT
  }
}

##################################################
# Imperative creation of Vault SA if missing
##################################################
resource "null_resource" "vault_sa" {
  depends_on = [null_resource.vault_crypto_key]

  provisioner "local-exec" {
    command = <<EOT
      set -e
      SA_EMAIL="vault-unseal-sa@${var.GCP_PROJECT}.iam.gserviceaccount.com"
      echo "[Check Service Account] Checking if vault-unseal-sa exists..."
      if gcloud iam service-accounts list \
           --project="${var.GCP_PROJECT}" \
           --format="value(email)" | grep -q "$SA_EMAIL"; then
        echo "Service account '$SA_EMAIL' already exists, skipping creation."
      else
        echo "Creating service account 'vault-unseal-sa'..."
        gcloud iam service-accounts create vault-unseal-sa \
          --display-name="Vault Auto Unseal Service Account" \
          --project="${var.GCP_PROJECT}"
      fi
    EOT
  }
}

##################################################
# Imperative creation of SA -> KMS Encrypter/Decrypter role
##################################################
resource "null_resource" "vault_sa_kms_bind" {
  depends_on = [null_resource.vault_sa]

  provisioner "local-exec" {
    command = <<EOT
      set -e
      SA_EMAIL="vault-unseal-sa@${var.GCP_PROJECT}.iam.gserviceaccount.com"
      echo "[Check IAM Binding] Checking if SA already has roles/cloudkms.cryptoKeyEncrypterDecrypter..."

      HAS_ROLE=$( gcloud projects get-iam-policy ${var.GCP_PROJECT} \
        --flatten="bindings[].members" \
        --format="value(bindings.role)" \
        --filter="bindings.members:serviceAccount:$SA_EMAIL AND bindings.role=roles/cloudkms.cryptoKeyEncrypterDecrypter" || true )

      if [ "$HAS_ROLE" = "roles/cloudkms.cryptoKeyEncrypterDecrypter" ]; then
        echo "Service account already has KMS Encrypter/Decrypter role."
      else
        echo "Granting KMS Encrypter/Decrypter role to $SA_EMAIL..."
        gcloud projects add-iam-policy-binding ${var.GCP_PROJECT} \
          --member="serviceAccount:$SA_EMAIL" \
          --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
      fi
    EOT
  }
}

##################################################
# Imperative creation of SA key file (once)
##################################################
resource "null_resource" "vault_sa_key" {
  depends_on = [null_resource.vault_sa_kms_bind]

  provisioner "local-exec" {
    command = <<EOT
      set -e
      SA_EMAIL="vault-unseal-sa@${var.GCP_PROJECT}.iam.gserviceaccount.com"

      echo "[Check SA Key] Checking if local file vault_sa_key.json already exists..."
      if [ -f "vault_sa_key.json" ]; then
        echo "Local file 'vault_sa_key.json' already exists, skipping creation."
      else
        echo "Creating a new key for $SA_EMAIL -> vault_sa_key.json"
        gcloud iam service-accounts keys create vault_sa_key.json \
          --iam-account="$SA_EMAIL" \
          --project="${var.GCP_PROJECT}"
      fi
    EOT
  }
}

# Now read that local file so we can output it as a sensitive Terraform output
data "local_file" "vault_sa_key_json" {
  depends_on = [null_resource.vault_sa_key]
  filename   = "${path.module}/vault_sa_key.json"
}

###############################################################################
# KUBERNETES & HELM providers
###############################################################################
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
# The content is read from vault_sa_key.json after local-exec is done.
output "vault_unseal_sa_key" {
  value     = data.local_file.vault_sa_key_json.content
  sensitive = true
}
