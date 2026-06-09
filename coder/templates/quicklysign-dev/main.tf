provider "google" {
  project = var.project_id
  region  = var.region
  zone    = data.coder_parameter.zone.value
}

data "coder_workspace" "me" {}

# Parameters for the Coder UI
data "coder_parameter" "zone" {
  name         = "zone"
  display_name = "GCP Zone"
  description  = "The zone to provision the workspace in."
  default      = "us-west1-a"
  icon         = "/icon/gcp.svg"
  mutable      = true
  option {
    name  = "us-west1-a"
    value = "us-west1-a"
  }
  option {
    name  = "us-west1-b"
    value = "us-west1-b"
  }
  option {
    name  = "us-west1-c"
    value = "us-west1-c"
  }
}

data "coder_parameter" "machine_type" {
  name         = "machine_type"
  display_name = "Machine Type"
  description  = "Compute instance type (Spot VM)"
  default      = "t2d-standard-4"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "t2d-standard-4 (4 vCPU, 16GB RAM)"
    value = "t2d-standard-4"
  }
  option {
    name  = "t2d-standard-8 (8 vCPU, 32GB RAM)"
    value = "t2d-standard-8"
  }
}

resource "coder_agent" "main" {
  auth           = "google-instance-identity"
  arch           = "amd64"
  os             = "linux"
  
  # The startup script runs as the 'coder' user
  startup_script = <<-EOT
    #!/bin/bash
    set -e
    
    # Save Coder env vars for systemd watchdog
    echo "CODER_URL=$CODER_URL" > ~/.coder_env
    echo "CODER_SESSION_TOKEN=$CODER_SESSION_TOKEN" >> ~/.coder_env
    
    # Extract scripts from GCP metadata
    mkdir -p ~/scripts ~/.local/bin ~/.local/share/agent-sessions
    
    curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/install_dev_tools" > ~/scripts/install-dev-tools.sh
    curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/install_agent_tools" > ~/scripts/install-agent-tools.sh
    curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/agent_run" > ~/.local/bin/agent-run
    curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/agent_watchdog" > ~/.local/bin/agent-watchdog
    curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/agent_status" > ~/.local/bin/agent-status
    curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/worklane" > ~/.local/bin/worklane
    
    chmod +x ~/scripts/*.sh ~/.local/bin/*
    
    # Execute bootstraps
    ~/scripts/install-dev-tools.sh 2>&1 | tee -a /tmp/install-dev-tools.log
    ~/scripts/install-agent-tools.sh 2>&1 | tee -a /tmp/install-agent-tools.log
  EOT

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

# Standalone Persistent Disk (Survives Spot VM Preemption)
resource "google_compute_disk" "workspace_disk" {
  name  = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}-home"
  type  = "pd-ssd"
  zone  = data.coder_parameter.zone.value
  size  = var.disk_size
  
  # Ensure the disk is not destroyed if the workspace is just stopped
  lifecycle {
    ignore_changes = [name, image]
  }
}

resource "google_compute_instance" "workspace" {
  count        = data.coder_workspace.me.start_count
  name         = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  machine_type = data.coder_parameter.machine_type.value
  zone         = data.coder_parameter.zone.value

  scheduling {
    preemptible                 = true
    automatic_restart           = false
    provisioning_model          = "SPOT"
    instance_termination_action = "STOP"
  }

  # Ephemeral boot disk for the OS
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30
      type  = "pd-balanced"
    }
  }

  # Attach the persistent home disk
  attached_disk {
    source      = google_compute_disk.workspace_disk.self_link
    device_name = "home-disk"
  }

  network_interface {
    network = "coder-vpc"
    access_config {}
  }

  service_account {
    email  = "coder-workspace@${var.project_id}.iam.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }

  # Pass scripts securely via metadata to avoid git clone dependencies inside the VM
  metadata = {
    coder_agent_token      = coder_agent.main.token
    google-logging-enabled = "true"
    
    # Mount script for the attached disk
    startup-script = <<-EOT
      #!/bin/bash
      set -e
      # Mount the persistent disk to /home/coder if not mounted
      if ! mount | grep -q '/home/coder'; then
        mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/disk/by-id/google-home-disk || true
        mkdir -p /home/coder
        mount -o discard,defaults /dev/disk/by-id/google-home-disk /home/coder
        chown -R 1000:1000 /home/coder
      fi
    EOT

    install_dev_tools   = file("${path.module}/scripts/install-dev-tools.sh")
    install_agent_tools = file("${path.module}/scripts/install-agent-tools.sh")
    agent_run           = file("${path.module}/scripts/agent-run")
    agent_watchdog      = file("${path.module}/scripts/agent-watchdog.sh")
    agent_status        = file("${path.module}/scripts/agent-status.sh")
    worklane            = file("${path.module}/scripts/worklane")
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
    value = data.coder_parameter.machine_type.value
  }
  item {
    key   = "disk size"
    value = "${var.disk_size} GB"
  }
  item {
    key   = "zone"
    value = data.coder_parameter.zone.value
  }
}
