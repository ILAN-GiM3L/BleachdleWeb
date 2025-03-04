###############################################################################
# terraform/argo/gke_argocd_cluster.tf
###############################################################################
resource "google_container_cluster" "argocd" {
  name                     = "argocd-cluster"
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

resource "google_container_node_pool" "argocd_nodes" {
  name     = "argocd-nodes"
  cluster  = google_container_cluster.argocd.name
  location = var.GCP_REGION

  autoscaling {
    min_node_count = 1
    max_node_count = 2
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

output "argocd_cluster_name" {
  value = google_container_cluster.argocd.name
}
