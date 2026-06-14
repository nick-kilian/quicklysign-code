# Coder control plane: a small always-on GCE VM.
#
# Cloud Run was evaluated and rejected — Coder requires a static,
# non-autoscaled control plane holding long-lived WebSocket/DERP relay
# connections, which Cloud Run severs at its request timeout (max 60 min)
# and on instance churn. See docs/architecture.md §1 for the full analysis
# and sources.
resource "google_compute_instance" "coder" {
  name         = "coder-control-plane"
  machine_type = var.control_plane_machine_type
  zone         = var.zone
  tags         = ["coder-server"]

  allow_stopping_for_update = true

  labels = local.common_labels

  boot_disk {
    initialize_params {
      image  = "debian-cloud/debian-12"
      size   = 20
      type   = "pd-balanced"
      labels = local.common_labels
    }
  }

  network_interface {
    network = google_compute_network.vpc.id
    access_config {
      nat_ip = google_compute_address.coder.address
    }
  }

  service_account {
    email  = google_service_account.coder_control_plane.email
    scopes = ["cloud-platform"] # access is constrained by IAM roles, not scopes
  }

  metadata = {
    google-logging-enabled = "true"
  }

  # Idempotent: installs Coder + Caddy on first boot, refreshes config
  # (including the DB URL from Secret Manager) on every boot.
  metadata_startup_script = templatefile("${path.module}/templates/control-plane-startup.sh.tftpl", {
    project_id     = var.project_id
    coder_hostname = var.coder_hostname
  })

  depends_on = [
    google_secret_manager_secret_version.db_url,
    google_secret_manager_secret_iam_member.control_plane_db_url,
  ]
}
