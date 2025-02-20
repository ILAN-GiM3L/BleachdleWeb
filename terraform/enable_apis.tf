resource "google_project_service" "enable_resource_manager" {
  project            = var.GCP_PROJECT
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "enable_container" {
  project            = var.GCP_PROJECT
  service            = "container.googleapis.com"
  disable_on_destroy = false
}
