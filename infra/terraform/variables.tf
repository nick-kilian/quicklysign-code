variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "quicklysign-terraform-dev"
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "The GCP zone for the control plane VM"
  type        = string
  default     = "us-west1-a"
}

variable "coder_hostname" {
  description = "Public hostname for the Coder server (becomes CODER_ACCESS_URL). Point an A record at the reserved static IP after the first apply."
  type        = string
  default     = "coder.ragingbucket.com"
}

variable "control_plane_machine_type" {
  description = "Machine type for the always-on Coder control plane VM. Coder's documented minimum is 1 vCPU / 2 GB; e2-small is 2 vCPU (shared) / 2 GB."
  type        = string
  default     = "e2-small"
}

variable "db_version" {
  description = "Cloud SQL Postgres version. Coder requires Postgres 13+."
  type        = string
  default     = "POSTGRES_16"
}

variable "db_tier" {
  description = "Cloud SQL machine tier. Shared-core is sufficient for a single-user Coder deployment."
  type        = string
  default     = "db-f1-micro"
}
