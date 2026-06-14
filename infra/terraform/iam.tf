resource "google_service_account" "coder_control_plane" {
  account_id   = "coder-control-plane"
  display_name = "Coder Control Plane (runs coderd + Terraform provisioner)"
}

resource "google_service_account" "coder_workspace" {
  account_id   = "coder-workspace"
  display_name = "Coder Workspace VMs"
}

# --- Control plane ---
# The control plane runs Coder's Terraform provisioner, which creates and
# destroys workspace VMs/disks. instanceAdmin.v1 is the narrowest predefined
# role that covers that; it does NOT grant project-wide admin like compute.admin.
resource "google_project_iam_member" "control_plane_compute" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.coder_control_plane.email}"
}

# Needed to attach the workspace service account to the VMs it provisions —
# scoped to that one SA, not project-wide.
resource "google_service_account_iam_member" "control_plane_uses_workspace_sa" {
  service_account_id = google_service_account.coder_workspace.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.coder_control_plane.email}"
}

resource "google_project_iam_member" "control_plane_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.coder_control_plane.email}"
}

resource "google_project_iam_member" "control_plane_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.coder_control_plane.email}"
}

# --- Workspaces ---
# Workspace VMs only need to write logs/metrics. The Coder agent authenticates
# via Google instance identity (a signed JWT from the metadata server), which
# requires an attached SA but no extra IAM roles.
resource "google_project_iam_member" "workspace_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.coder_workspace.email}"
}

resource "google_project_iam_member" "workspace_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.coder_workspace.email}"
}
