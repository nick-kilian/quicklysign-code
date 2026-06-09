output "coder_url" {
  value = var.use_cloud_run ? google_cloud_run_v2_service.coder[0].uri : "http://${google_compute_instance.coder_fallback[0].network_interface[0].access_config[0].nat_ip}"
}

output "vpc_id" {
  value = google_compute_network.vpc.id
}

output "database_ip" {
  value = google_sql_database_instance.coder.private_ip_address
}

output "workspace_service_account" {
  value = google_service_account.coder_workspace.email
}
