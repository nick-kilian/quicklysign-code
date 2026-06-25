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

# Custom VPCs deny all ingress by default. Only open what we need: HTTPS to the
# control plane. Port 80 is intentionally NOT opened — Caddy uses the ACME
# TLS-ALPN-01 challenge (over 443) rather than HTTP-01, so port 80 is unneeded.
# This closes the SCC OPEN_HTTP_PORT finding and narrows the public surface to
# 443 only. (Caddy still binds :80 locally for an http->https redirect, but it's
# not reachable externally — users reach Coder via the https URL.)
resource "google_compute_firewall" "coder_https" {
  name    = "coder-allow-https"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443"]
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
