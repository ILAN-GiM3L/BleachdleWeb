###############################################################################
# terraform/bleachdle/main.tf
###############################################################################
terraform {
  backend "gcs" {
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

##############################
# KMS
##############################
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

##############################
# GKE: ephemeral cluster
##############################
resource "google_container_cluster" "bleachdle_ephemeral" {
  name                     = "bleachdle-cluster"
  location                 = var.GCP_REGION
  node_locations           = ["us-central1-a"]
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = "default"
  subnetwork = "default"

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  addons_config {
    http_load_balancing {
      disabled = false
    }
  }

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.GCP_PROJECT}.svc.id.goog"
  }
}

resource "google_container_node_pool" "bleachdle_ephemeral_nodes" {
  name     = "bleachdle-ephemeral-nodes"
  cluster  = google_container_cluster.bleachdle_ephemeral.name
  location = var.GCP_REGION

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    machine_type = "e2-medium"
    image_type   = "COS_CONTAINERD"
    disk_size_gb = 15
    disk_type    = "pd-standard"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  management {
    auto_upgrade = true
    auto_repair  = true
  }
}

##############################
# Workload Identity Binding
##############################
# This allows your K8s SA (in the default namespace) to act as
# terraform-admin@bleachdle-web.iam.gserviceaccount.com
# by granting roles/iam.workloadIdentityUser on that GCP SA.
#
# NOTE: The "member" is set to:
#   "serviceAccount:<PROJECT>.svc.id.goog[<NAMESPACE>/<K8S_SA>]"
# ...matching the annotation we added to the SA in the Helm chart.
##############################

resource "google_service_account_iam_binding" "allow_bleachdle_sa_impersonation" {
  service_account_id = "terraform-admin@${var.GCP_PROJECT}.iam.gserviceaccount.com"
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.GCP_PROJECT}.svc.id.goog[default/bleachdle-sa]",
  ]
}

##############################
# KMS IAM: let terraform-admin@... do KMS
##############################
# If you also want the same GCP SA to have wide KMS perms:
# you already have it as an Owner, but here’s an example if you want a more minimal approach:
resource "google_kms_crypto_key_iam_member" "bleachdle_sa_kms_permissions" {
  crypto_key_id = google_kms_crypto_key.vault_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:terraform-admin@${var.GCP_PROJECT}.iam.gserviceaccount.com"
}

# Optional: If you want even broader KMS admin capabilities:
# resource "google_kms_crypto_key_iam_member" "bleachdle_sa_kms_admin_permissions" {
#   crypto_key_id = google_kms_crypto_key.vault_key.id
#   role          = "roles/cloudkms.admin"
#   member        = "serviceAccount:terraform-admin@${var.GCP_PROJECT}.iam.gserviceaccount.com"
# }

##############################
# K8S & HELM providers
##############################
provider "kubernetes" {
  host                   = "https://${google_container_cluster.bleachdle_ephemeral.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.bleachdle_ephemeral.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.bleachdle_ephemeral.endpoint}"
    cluster_ca_certificate = base64decode(google_container_cluster.bleachdle_ephemeral.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

data "google_client_config" "default" {}

###############################################################################
# Outputs
###############################################################################
output "bleachdle_cluster_endpoint" {
  value = google_container_cluster.bleachdle_ephemeral.endpoint
}

output "bleachdle_cluster_name" {
  value = google_container_cluster.bleachdle_ephemeral.name
}
