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

# ----------------------------------------------------------------------
# PROVIDERS
# ----------------------------------------------------------------------
provider "google" {
  project = var.GCP_PROJECT
  region  = var.GCP_REGION
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = google_container_cluster.primary.endpoint
  cluster_ca_certificate = google_container_cluster.primary.cluster_ca_certificate
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = google_container_cluster.primary.endpoint
    cluster_ca_certificate = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
    token                  = data.google_client_config.default.access_token
  }
}

# ----------------------------------------------------------------------
# SHARED RESOURCES
# ----------------------------------------------------------------------
resource "random_id" "key_id" {
  byte_length = 8
}

output "gke_cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}

output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}
