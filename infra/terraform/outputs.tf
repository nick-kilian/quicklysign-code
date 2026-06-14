output "coder_url" {
  description = "The Coder access URL"
  value       = "https://${var.coder_hostname}"
}

output "control_plane_ip" {
  description = "Reserved static IP of the control plane VM"
  value       = google_compute_address.coder.address
}

output "dns_record" {
  description = "DNS record you must create"
  value       = "${var.coder_hostname}. A ${google_compute_address.coder.address}"
}

output "database_private_ip" {
  value = google_sql_database_instance.coder.private_ip_address
}

output "workspace_service_account" {
  description = "Attach this SA to workspace VMs (the template's default matches)"
  value       = google_service_account.coder_workspace.email
}

output "vpc_name" {
  value = google_compute_network.vpc.name
}
