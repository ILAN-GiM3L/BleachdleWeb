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
# GKE: ephemeral cluster
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
# K8S & HELM Providers
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
