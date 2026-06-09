resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "google_sql_database_instance" "coder" {
  name             = "coder-db"
  database_version = "POSTGRES_15"
  region           = var.region

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }
  }

  deletion_protection = false # Set to true for production
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
