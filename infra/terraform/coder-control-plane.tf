resource "google_cloud_run_v2_service" "coder" {
  count    = var.use_cloud_run ? 1 : 0
  name     = "coder"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.coder_control_plane.email
    timeout         = "3600s" # Max timeout for WebSockets

    containers {
      image = var.coder_image
      
      env {
        name  = "CODER_PG_CONNECTION_URL"
        value = "postgres://coder:${random_password.db_password.result}@${google_sql_database_instance.coder.private_ip_address}/coder?sslmode=disable"
      }
      env {
        name  = "CODER_HTTP_ADDRESS"
        value = "0.0.0.0:8080"
      }
      env {
        name  = "CODER_ACCESS_URL"
        value = "https://coder-${data.google_project.project.number}.${var.region}.a.run.app"
      }

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "4Gi"
        }
      }
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "ALL_TRAFFIC"
    }

    scaling {
      min_instance_count = 1 # Keep at least one to avoid cold starts and for WebSockets
    }
    
    session_affinity = true
  }
}

data "google_project" "project" {}

resource "google_cloud_run_service_iam_member" "public_access" {
  count    = var.use_cloud_run ? 1 : 0
  location = google_cloud_run_v2_service.coder[0].location
  service  = google_cloud_run_v2_service.coder[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Fallback VM logic
resource "google_compute_instance" "coder_fallback" {
  count        = var.use_cloud_run ? 0 : 1
  name         = "coder-control-plane"
  machine_type = "e2-small"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = google_compute_network.vpc.id
    access_config {
      # Static IP or Ephemeral for now
    }
  }

  service_account {
    email  = google_service_account.coder_control_plane.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    curl -L https://coder.com/install.sh | sh
    export CODER_PG_CONNECTION_URL="postgres://coder:${random_password.db_password.result}@${google_sql_database_instance.coder.private_ip_address}/coder?sslmode=disable"
    export CODER_HTTP_ADDRESS="0.0.0.0:80"
    coder server
  EOT
}
