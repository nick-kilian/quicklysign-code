# The Postgres connection URL lives only in Secret Manager. The control plane
# VM fetches it at boot with its service account — it is never written to
# instance metadata or Terraform-rendered startup scripts.
#
# sslmode=disable is acceptable here because the connection rides the private
# VPC peering to Cloud SQL's private IP and never crosses the public internet.
resource "google_secret_manager_secret" "db_url" {
  secret_id = "coder-db-url"
  labels    = local.common_labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.services]
}

resource "google_secret_manager_secret_version" "db_url" {
  secret      = google_secret_manager_secret.db_url.id
  secret_data = "postgres://coder:${random_password.db_password.result}@${google_sql_database_instance.coder.private_ip_address}/coder?sslmode=disable"
}

resource "google_secret_manager_secret_iam_member" "control_plane_db_url" {
  secret_id = google_secret_manager_secret.db_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.coder_control_plane.email}"
}

# Google OIDC client secret. The container is managed here; the VALUE (version)
# is added out-of-band (gcloud) so the secret never lands in Terraform state or
# git — same hygiene as not putting it in a tfvar. The control plane fetches the
# latest version at boot (only when var.oidc_client_id is set).
resource "google_secret_manager_secret" "oidc_client_secret" {
  secret_id = "coder-oidc-client-secret"
  labels    = local.common_labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.services]
}

resource "google_secret_manager_secret_iam_member" "control_plane_oidc_client_secret" {
  secret_id = google_secret_manager_secret.oidc_client_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.coder_control_plane.email}"
}
