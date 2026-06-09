resource "google_service_account" "coder_control_plane" {
  account_id   = "coder-control-plane"
  display_name = "Coder Control Plane Service Account"
}

resource "google_service_account" "coder_workspace" {
  account_id   = "coder-workspace"
  display_name = "Coder Workspace Service Account"
}

# Control Plane permissions
resource "google_project_iam_member" "control_plane_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.coder_control_plane.email}"
}

# Workspace permissions (Compute Engine, Secret Manager access, etc.)
resource "google_project_iam_member" "workspace_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.coder_workspace.email}"
}
