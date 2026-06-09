provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "coder_workspace" "me" {}

resource "coder_agent" "main" {
  auth           = "google-instance-identity"
  arch           = "amd64"
  os             = "linux"
  startup_script = file("./scripts/startup.sh")

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\\([0-9.]*\\)%* id.*/\\1/' | awk '{print 100 - $1\"%\"}'"
    interval     = 60
  }

  metadata {
    display_name = "Memory Usage"
    key          = "mem_usage"
    script       = "free -m | awk '/Mem:/ { printf(\"%3.1f%%\", $3/$2*100) }'"
    interval     = 60
  }
}

resource "google_compute_instance" "workspace" {
  count        = data.coder_workspace.me.start_count
  name         = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  machine_type = var.machine_type
  zone         = var.zone

  scheduling {
    preemptible        = true
    automatic_restart  = false
    provisioning_model = "SPOT"
    instance_termination_action = "STOP"
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = "default" # Adjust if using a specific VPC
    access_config {
      // Ephemeral public IP
    }
  }

  service_account {
    email  = "coder-workspace@${var.project_id}.iam.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }

  metadata = {
    coder_agent_token = coder_agent.main.token
    google-logging-enabled = "true"
  }

  labels = {
    "coder_workspace" = "true"
    "owner"           = data.coder_workspace.me.owner
  }
}

resource "coder_metadata" "workspace_info" {
  resource_id = google_compute_instance.workspace[0].id
  item {
    key   = "machine type"
    value = var.machine_type
  }
  item {
    key   = "disk size"
    value = "${var.disk_size} GB"
  }
}
