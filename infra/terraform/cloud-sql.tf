resource "random_password" "db_password" {
  length  = 24
  special = false # keeps the connection URL safe without escaping
}

resource "google_sql_database_instance" "coder" {
  name             = "coder-db"
  database_version = var.db_version
  region           = var.region

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    # ENTERPRISE (standard) edition: required for shared-core tiers like
    # db-f1-micro; the API otherwise defaults Postgres 16 to ENTERPRISE_PLUS.
    edition           = "ENTERPRISE"
    tier              = var.db_tier
    availability_type = "ZONAL"
    user_labels       = local.common_labels
    disk_size         = 10
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }

    backup_configuration {
      enabled    = true
      start_time = "03:00"
    }
  }

  # Requires an intentional two-step change to destroy the database.
  deletion_protection = true
}

resource "google_sql_database" "coder" {
  name     = "coder"
  instance = google_sql_database_instance.coder.name
}

resource "google_sql_user" "coder" {
  name     = "coder"
  instance = google_sql_database_instance.coder.name
  password = random_password.db_password.result
}
