variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "nick-coder"
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "The GCP zone"
  type        = string
  default     = "us-west1-a"
}

variable "coder_image" {
  description = "The Coder Docker image"
  type        = string
  default     = "ghcr.io/coder/coder:latest"
}

variable "use_cloud_run" {
  description = "Whether to use Cloud Run for the Coder control plane"
  type        = bool
  default     = true
}
