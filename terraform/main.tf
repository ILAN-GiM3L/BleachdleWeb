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
  }

  required_version = ">= 1.0.0"
}

provider "google" {
  project = var.GCP_PROJECT
  region  = var.GCP_REGION
}

# Needed by the kubernetes provider to fetch a token for authentication
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = google_container_cluster.primary.endpoint
  cluster_ca_certificate = google_container_cluster.primary.cluster_ca_certificate
  token                  = data.google_client_config.default.access_token
}

resource "random_id" "key_id" {
  byte_length = 8
}

# Outputs for debugging and verification
output "gke_cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}

output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}