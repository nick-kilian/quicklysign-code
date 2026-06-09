resource "google_secret_manager_secret" "db_url" {
  secret_id = "coder-db-url"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_url" {
  secret = google_secret_manager_secret.db_url.id
  secret_data = "postgres://coder:${random_password.db_password.result}@${google_sql_database_instance.coder.private_ip_address}/coder?sslmode=disable"
}

resource "google_secret_manager_secret_iam_member" "control_plane_db_url" {
  secret_id = google_secret_manager_secret.db_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.coder_control_plane.email}"
}
