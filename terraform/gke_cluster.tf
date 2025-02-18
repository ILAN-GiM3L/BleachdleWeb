resource "google_container_cluster" "primary" {
  name               = "bleachdle-cluster-${random_id.key_id.hex}"
  location           = var.GCP_REGION
  remove_default_node_pool = true  # Remove the default node pool created by GKE
    initial_node_count = 1

  # Use the existing default VPC network and subnetwork
  network    = "default"
  subnetwork = "default"

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  addons_config {
    http_load_balancing {
      disabled = false
    }
  }

  # Define node pool resource separately for better management
}

resource "google_container_node_pool" "primary_nodes" {
  cluster  = google_container_cluster.primary.name
  location = var.GCP_REGION

  # Autoscaling configuration for flexibility
  autoscaling {
    min_node_count = 1  # Start with 1 nodes for higher availability
    max_node_count = 3  # Allow up to 3 nodes for scaling
  }

  node_config {
    machine_type = "e2-medium"  # Use e2-medium for better performance
    disk_size_gb = 15           # Disk size for the nodes (15 GB)
    disk_type    = "pd-standard"  # Standard persistent disk type
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",  # Least privilege scope
    ]
  }

  management {
    auto_upgrade = true  # Automatically upgrade nodes
    auto_repair  = true  # Automatically repair unhealthy nodes
  }
}


