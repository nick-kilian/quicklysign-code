# API enablement. Cloud Run and VPC-access APIs are intentionally absent:
# the control plane runs on a small GCE VM (see docs/architecture.md for why
# Cloud Run was rejected). Artifact Registry is not needed for this setup.
locals {
  # Applied to every label-capable resource so costs are filterable in
  # billing reports (filter: label app = coder).
  common_labels = {
    app = "coder"
  }

  services = [
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
}

resource "google_project_service" "services" {
  for_each = toset(local.services)
  project  = var.project_id
  service  = each.key

  disable_on_destroy = false
}
