variable "project_id" {
  description = "GCP project to provision workspace VMs in"
  type        = string
  default     = "quicklysign-terraform-dev"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-west1"
}

# The zone is a template variable (not a user parameter) on purpose: the
# persistent root disk is zonal, so changing zones after creation would
# orphan the disk. Pick the zone once per template.
variable "zone" {
  description = "GCP zone for workspace VMs and their persistent disks"
  type        = string
  default     = "us-west1-a"
}

variable "network_name" {
  description = "VPC network for workspace VMs (created by infra/terraform)"
  type        = string
  default     = "coder-vpc"
}

variable "disk_size_gb" {
  description = "Size of the persistent root disk"
  type        = number
  default     = 200
}
