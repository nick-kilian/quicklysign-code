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

# --- Workspace read+write on the dev project's data/app services ---
# quicklysign-terraform-dev doubles as the shared dev sandbox. Grant write on
# the services actually in use so workspaces can exercise dev fully.
# DELIBERATELY EXCLUDED — this project ALSO hosts the Coder control plane, the
# Coder DB, and the workspace VMs: compute.* / cloudsql.admin / project IAM
# admin / project-wide serviceAccountUser, so a workspace can't delete its own
# control plane or DB, or escalate.
# NOTE: secretmanager.admin spans ALL secrets here (incl coder-db-url + infra
# creds) — downgrade to secretAccessor or add an IAM condition if too broad.
locals {
  dev_workspace_roles = [
    "roles/datastore.user",
    "roles/secretmanager.admin",
    "roles/cloudsql.client",
    "roles/storage.objectAdmin",
    "roles/pubsub.editor",
    "roles/run.developer",
    "roles/cloudtasks.admin",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/artifactregistry.writer",
  ]
}

resource "google_project_iam_member" "workspace_dev" {
  for_each = toset(local.dev_workspace_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.coder_workspace.email}"
}

# Same dev_workspace_roles write set on additional pure-app dev projects (no
# Coder infra co-located -> none of the terraform-dev exclusions apply, and
# their secrets are app-only). Extend via var.extra_dev_projects.
resource "google_project_iam_member" "workspace_extra_dev" {
  for_each = {
    for pair in setproduct(var.extra_dev_projects, local.dev_workspace_roles) :
    "${pair[0]}|${pair[1]}" => { project = pair[0], role = pair[1] }
  }
  project = each.value.project
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.coder_workspace.email}"
}

# --- Workspace read-only access to prod (cross-project) ---
# Grants the workspace SA logs + monitoring *viewer* on each var.prod_read_projects
# project so you can read prod logs/metrics from a workspace. Non-authoritative
# (iam_member adds the binding, never touching other members). logging.viewer
# excludes data-access / private logs by design.
# SECURITY: anyone who can use a workspace inherits this prod read access — keep
# the role set and project list minimal. Requires terraform ADC to have
# projectIamAdmin on each target project.
locals {
  workspace_prod_read_roles = ["roles/logging.viewer", "roles/monitoring.viewer"]
  workspace_prod_read = {
    for pair in setproduct(var.prod_read_projects, local.workspace_prod_read_roles) :
    "${pair[0]}|${pair[1]}" => { project = pair[0], role = pair[1] }
  }
}

resource "google_project_iam_member" "workspace_prod_read" {
  for_each = local.workspace_prod_read
  project  = each.value.project
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.coder_workspace.email}"
}

# --- Workspace impersonation of the quicklysign-bots deploy SA ---
# Lets a workspace terraform-apply task-failure-bot infra into quicklysign-bots
# by impersonating that project's deploy SA — without the workspace SA holding
# any standing admin on quicklysign-bots. The deploy SA itself + its roles + the
# provider's impersonate_service_account live in the ESTATE IaC; this binding is
# the only piece that touches the workspace SA, so it lives here. Revoke to cut
# off access. Apply order: the estate IaC must create the deploy SA first (this
# references it by email).
resource "google_service_account_iam_member" "workspace_impersonate_bots_deployer" {
  service_account_id = "projects/quicklysign-bots/serviceAccounts/${var.bots_deployer_sa_email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.coder_workspace.email}"
}

# Workspace read-only access to the task-failure-bot's logs in quicklysign-bots,
# so a lane can debug the bot's Cloud Run service (enrichment fallbacks, GitHub
# token errors, claude-runner failures) directly from the workspace. Read-only:
# logging.viewer, no write/admin. Like the prod-read grants, this is a
# workspace-SA grant so it lives here rather than the estate IaC.
resource "google_project_iam_member" "workspace_bots_logging" {
  project = "quicklysign-bots"
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.coder_workspace.email}"
}
