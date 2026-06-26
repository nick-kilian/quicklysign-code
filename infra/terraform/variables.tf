variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "quicklysign-terraform-dev"
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "The GCP zone for the control plane VM"
  type        = string
  default     = "us-west1-a"
}

variable "prod_read_projects" {
  description = <<-EOT
    Prod GCP projects the workspace SA is granted READ-ONLY logs + monitoring on
    (cross-project). Your terraform credentials (ADC) need projectIamAdmin on
    each of these. SECURITY: anyone who can use a workspace inherits this prod
    read access, so keep the list and roles minimal.
  EOT
  type        = list(string)
  default     = ["quicklysign-eu", "themassive-live", "quicklysign-financial"]
}

variable "extra_dev_projects" {
  description = <<-EOT
    Additional PURE-APP dev projects (no Coder infra co-located) the workspace SA
    gets the dev_workspace_roles read+write set on. Unlike quicklysign-terraform-dev
    these need no self-destruct exclusions. SECURITY: every workspace user inherits
    write on these projects' data/app services.
  EOT
  type        = list(string)
  default     = ["quicklysign-python3-dev"]
}

variable "bots_deployer_sa_email" {
  description = <<-EOT
    Deploy SA in quicklysign-bots that workspaces impersonate to terraform-apply
    the bot's infra. The SA and its quicklysign-bots roles are created by the
    ESTATE IaC; this repo only grants the workspace SA tokenCreator on it.
  EOT
  type        = string
  default     = "task-failure-bot-deployer@quicklysign-bots.iam.gserviceaccount.com"
}

variable "coder_hostname" {
  description = "Primary public hostname for the Coder server (becomes CODER_ACCESS_URL). Point an A record at the reserved static IP after the first apply."
  type        = string
  default     = "coder.ragingbucket.com"
}

variable "oidc_client_id" {
  description = <<-EOT
    Google OAuth 2.0 Web client ID for Coder OIDC login. Empty disables OIDC
    (the startup script then writes no OIDC config). The matching client secret
    is NOT a variable — it lives in the coder-oidc-client-secret Secret Manager
    secret and is fetched at boot, like the DB URL.
  EOT
  type        = string
  default     = "182084267345-gcv0jiipo2pcpgfa58cta929rlu1n1os.apps.googleusercontent.com"
}

variable "oidc_email_domain" {
  description = "Comma-separated email domain(s) allowed to log in via OIDC."
  type        = string
  default     = "quicklysign.com"
}

variable "oidc_allow_signups" {
  description = <<-EOT
    If false, OIDC will NOT auto-provision new users — only users pre-created in
    Coder can log in (a manual allow-list, the OSS substitute for group gating).
    Recommended false; pre-create the first owner.
  EOT
  type        = bool
  default     = false
}

variable "coder_extra_hostnames" {
  description = <<-EOT
    Additional hostnames Caddy serves (and obtains certs for) alongside
    coder_hostname — useful for an alias domain. CODER_ACCESS_URL stays the
    primary coder_hostname; these are reverse-proxy aliases. Each needs an
    A record pointing at the static IP, and (TLS-ALPN-01) it must resolve to
    the origin IP directly (no Cloudflare proxy) so ACME can validate on 443.
  EOT
  type        = list(string)
  default     = ["coder.quicklysign.com"]
}

variable "control_plane_machine_type" {
  description = "Machine type for the always-on Coder control plane VM. Coder's documented minimum is 1 vCPU / 2 GB; e2-small is 2 vCPU (shared) / 2 GB."
  type        = string
  default     = "e2-small"
}

variable "db_version" {
  description = "Cloud SQL Postgres version. Coder requires Postgres 13+."
  type        = string
  default     = "POSTGRES_16"
}

variable "db_tier" {
  description = "Cloud SQL machine tier. Shared-core is sufficient for a single-user Coder deployment."
  type        = string
  default     = "db-f1-micro"
}
