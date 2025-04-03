variable "GCP_PROJECT" {
  description = "Google Cloud Project ID"
  type        = string
  default     = "bleachdle-web"
}

variable "GCP_REGION" {
  description = "Google Cloud Region"
  type        = string
  default     = "us-central1"
}

variable "GCP_ZONE" {
  description = "Google Cloud Zone (e.g. us-central1-a)"
  type        = string
  default     = "us-central1-a"
}
