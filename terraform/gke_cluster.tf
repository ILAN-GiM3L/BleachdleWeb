resource "google_container_cluster" "bleachdle_ephemeral" {
  name                     = "bleachdle-cluster"
  location                 = var.GCP_REGION
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
}

resource "google_container_node_pool" "bleachdle_ephemeral_nodes" {
  name      = "bleachdle-ephemeral-nodes"
  cluster   = google_container_cluster.bleachdle_ephemeral.name
  location  = var.GCP_REGION

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

###############################################################################
# KUBERNETES & HELM providers for Bleachdle cluster
###############################################################################
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

###############################################################################
# Outputs
###############################################################################
output "bleachdle_cluster_endpoint" {
  value = google_container_cluster.bleachdle_ephemeral.endpoint
}

output "bleachdle_cluster_name" {
  value = google_container_cluster.bleachdle_ephemeral.name
}
