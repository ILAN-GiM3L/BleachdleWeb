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

###############################################################################
# Enable Required GCP Services
###############################################################################
resource "google_project_service" "enable_container" {
  project = var.GCP_PROJECT
  service = "container.googleapis.com"
}

resource "google_project_service" "enable_iam" {
  project = var.GCP_PROJECT
  service = "iam.googleapis.com"
}

resource "google_project_service" "enable_iam_credentials" {
  project = var.GCP_PROJECT
  service = "iamcredentials.googleapis.com"
}

resource "google_project_service" "enable_kms" {
  project = var.GCP_PROJECT
  service = "cloudkms.googleapis.com"
}

###############################################################################
# Google Provider
###############################################################################
provider "google" {
  project = var.GCP_PROJECT
  region  = var.GCP_REGION
}

###############################################################################
# KMS: Key Ring & Crypto Key
###############################################################################
resource "google_kms_key_ring" "vault_key_ring" {
  name     = "vault-key-ring"
  location = var.GCP_REGION

  # Make sure KMS API is enabled before creating the Key Ring
  depends_on = [
    google_project_service.enable_kms
  ]
}

resource "google_kms_crypto_key" "vault_key" {
  name            = "vault-key"
  key_ring        = google_kms_key_ring.vault_key_ring.id
  rotation_period = "100000s"
  purpose         = "ENCRYPT_DECRYPT"

  depends_on = [
    google_kms_key_ring.vault_key_ring
  ]
}

###############################################################################
# GKE: ephemeral cluster w/ Workload Identity
###############################################################################
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

  # Ensure container/IAM APIs are enabled before cluster creation
  depends_on = [
    google_project_service.enable_container,
    google_project_service.enable_iam,
    google_project_service.enable_iam_credentials
  ]
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

  depends_on = [
    google_container_cluster.bleachdle_ephemeral
  ]
}

###############################################################################
# Workload Identity Binding
###############################################################################
# Binds bleachdle-sa (K8s) -> terraform-admin GCP SA for impersonation
###############################################################################
resource "google_service_account_iam_binding" "allow_bleachdle_sa_impersonation" {
  service_account_id = "projects/${var.GCP_PROJECT}/serviceAccounts/terraform-admin@${var.GCP_PROJECT}.iam.gserviceaccount.com"
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.GCP_PROJECT}.svc.id.goog[default/bleachdle-sa]",
  ]

  # Wait until the cluster identity pool is fully created
  depends_on = [
    google_container_cluster.bleachdle_ephemeral
  ]
}

resource "google_service_account_iam_binding" "allow_vault_sa_impersonation" {
  service_account_id = "projects/${var.GCP_PROJECT}/serviceAccounts/terraform-admin@${var.GCP_PROJECT}.iam.gserviceaccount.com"
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.GCP_PROJECT}.svc.id.goog[vault/vault-sa]",
  ]
  depends_on = [
    google_container_cluster.bleachdle_ephemeral
  ]
}


###############################################################################
# KMS IAM: let terraform-admin@... do KMS
###############################################################################
resource "google_kms_crypto_key_iam_member" "bleachdle_sa_kms_permissions" {
  crypto_key_id = google_kms_crypto_key.vault_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:terraform-admin@${var.GCP_PROJECT}.iam.gserviceaccount.com"

  depends_on = [
    google_kms_crypto_key.vault_key
  ]
}

# If you need broader KMS privileges, uncomment & update:
resource "google_kms_crypto_key_iam_member" "bleachdle_sa_kms_admin_permissions" {
  crypto_key_id = google_kms_crypto_key.vault_key.id
  role          = "roles/cloudkms.admin"
  member        = "serviceAccount:terraform-admin@${var.GCP_PROJECT}.iam.gserviceaccount.com"

  depends_on = [
    google_kms_crypto_key.vault_key
  ]
}


###############################################################################
# K8S & HELM providers
###############################################################################
provider "kubernetes" {
  host                   = "https://${google_container_cluster.bleachdle_ephemeral.endpoint}"
  cluster_ca_certificate = base64decode(
    google_container_cluster.bleachdle_ephemeral.master_auth[0].cluster_ca_certificate
  )
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.bleachdle_ephemeral.endpoint}"
    cluster_ca_certificate = base64decode(
      google_container_cluster.bleachdle_ephemeral.master_auth[0].cluster_ca_certificate
    )
    token                  = data.google_client_config.default.access_token
  }
}

###############################################################################
# Data Source: google_client_config
###############################################################################
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
