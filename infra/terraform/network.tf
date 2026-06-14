resource "google_compute_network" "vpc" {
  name                    = "coder-vpc"
  auto_create_subnetworks = true

  depends_on = [google_project_service.services]
}

# Reserved static IP so the Coder access URL (DNS A record) never changes.
resource "google_compute_address" "coder" {
  name   = "coder-control-plane-ip"
  region = var.region
  labels = local.common_labels
}

# Private services access for Cloud SQL private IP.
resource "google_compute_global_address" "private_ip_address" {
  name          = "coder-private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
  labels        = local.common_labels
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# Custom VPCs deny all ingress by default. Only open what we need:
# HTTP/HTTPS to the control plane (80 is required for Let's Encrypt HTTP-01).
resource "google_compute_firewall" "coder_https" {
  name    = "coder-allow-https"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["coder-server"]
}

# Break-glass SSH via IAP only (no public port 22 anywhere).
# Usage: gcloud compute ssh <vm> --tunnel-through-iap
resource "google_compute_firewall" "iap_ssh" {
  name    = "coder-allow-iap-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # Google's IAP TCP forwarding range
  target_tags   = ["coder-server", "coder-workspace"]
}
