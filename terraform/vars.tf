variable "GCP_PROJECT" {
  description = "Google Cloud Project ID"
  default     = "bleachdle-project"
}

variable "GCP_REGION" {
  description = "Google Cloud Region"
  default     = "us-central1"
}

variable "db_host" {
  description = "Host address for the MySQL database"
  type        = string
  default     = "34.165.72.240"
}

variable "db_user" {
  description = "Username for the MySQL database"
  type        = string
  default     = "root"
}

variable "db_password" {
  description = "Password for the MySQL database"
  type        = string
  default     = "GeverYozem10072003"
}

variable "db_name" {
  description = "MySQL database name"
  type        = string
  default     = "Bleach_DB"
}

variable "api_url" {
  description = "API endpoint that your Flask app calls"
  type        = string
  default     = "http://bleachdle-project.ey.r.appspot.com/"
}

variable "vault_token" {
  description = "Vault dev root token"
  type        = string
  sensitive   = true
  default     = "root"
}
