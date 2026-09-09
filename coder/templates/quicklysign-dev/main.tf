terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# The Coder provisioner runs on the control plane VM and authenticates to GCP
# via that VM's service account (Application Default Credentials).
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  # Fixed Linux user. Keeps every path in the helper scripts predictable
  # (/home/coder) regardless of the Coder username.
  linux_user = "coder"

  workspace_name = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"

  # Filterable in billing reports: label app = coder
  common_labels = {
    app   = "coder"
    owner = lower(data.coder_workspace_owner.me.name)
  }

  # Helper scripts installed into ~/.local/bin on the workspace.
  # Delivered via the agent startup script (not GCE metadata), so they are
  # size-limited only by the Coder API, and updating the template updates them.
  bin_scripts = {
    "agent-run"           = file("${path.module}/scripts/agent-run")
    "agent-watchdog"      = file("${path.module}/scripts/agent-watchdog.sh")
    "agent-status"        = file("${path.module}/scripts/agent-status.sh")
    "agent-activity-hook" = file("${path.module}/scripts/agent-activity-hook.sh")
    "worklane"            = file("${path.module}/scripts/worklane")
    "lane-init"           = file("${path.module}/scripts/lane-init")
    "list-app-ports"      = file("${path.module}/scripts/list-app-ports")
    "setup-repos"         = file("${path.module}/scripts/setup-repos.sh")
    "install-dev-tools"   = file("${path.module}/scripts/install-dev-tools.sh")
    "install-agent-tools" = file("${path.module}/scripts/install-agent-tools.sh")
  }

  # Appended (idempotently, every boot) to the dev user's ~/.bashrc. Per-lane
  # shell history: each tmux work-lane keeps its own up-arrow recall instead of
  # all panes sharing one global ~/.bash_history. ($TMUX/$HOME/$(...) are shell
  # runtime refs — no $${...} braces, so templatefile leaves them alone.)
  bashrc_extra = <<-EOS
    # --- quicklysign: per-tmux-session history ---------------------------------
    shopt -s histappend
    export HISTSIZE=100000 HISTFILESIZE=200000
    if [ -n "$TMUX" ]; then
      __lane="$(tmux display-message -p '#S' 2>/dev/null)"
      [ -n "$__lane" ] && HISTFILE="$HOME/.bash_history.$__lane"
    fi
    export PROMPT_COMMAND='history -a; history -c; history -r'
    # ---------------------------------------------------------------------------
  EOS
}

data "coder_parameter" "machine_type" {
  name         = "machine_type"
  display_name = "Machine Type"
  description  = "Compute instance type (provisioned as a Spot VM)"
  default      = "t2d-standard-4"
  mutable      = true
  icon         = "/icon/memory.svg"

  option {
    name  = "t2d-standard-4 (4 vCPU, 16 GB)"
    value = "t2d-standard-4"
  }
  option {
    name  = "t2d-standard-8 (8 vCPU, 32 GB)"
    value = "t2d-standard-8"
  }
}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  # Instance-identity auth: the agent proves who it is with a Google-signed
  # JWT from the metadata server. No agent token ever touches VM metadata.
  auth = "google-instance-identity"

  # Non-blocking so you can SSH in while the first-boot tool install runs.
  startup_script_behavior = "non-blocking"

  startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="$HOME/.local/bin:$PATH"
    export CODER_URL='${data.coder_workspace.me.access_url}' # used by install-agent-tools

    mkdir -p "$HOME/.local/bin" "$HOME/.local/state" \
             "$HOME/.local/share/agent-sessions/signals" \
             "$HOME/.config/quicklysign" "$HOME/.config/agent-watchdog"

    # --- install bundled helper scripts ---
    # (single-line base64 pipes: immune to heredoc/indentation pitfalls)
    %{~for name, content in local.bin_scripts}
    echo '${base64encode(content)}' | base64 -d > "$HOME/.local/bin/${name}"
    chmod +x "$HOME/.local/bin/${name}"
    %{~endfor}

    # --- shell config: per-lane history (every boot; idempotent) ---
    if ! grep -q 'quicklysign: per-tmux-session history' "$HOME/.bashrc" 2>/dev/null; then
      echo '${base64encode(local.bashrc_extra)}' | base64 -d >> "$HOME/.bashrc"
    fi

    # --- repo configuration (source of truth lives in the template) ---
    echo '${base64encode(file("${path.module}/repos.json"))}' | base64 -d > "$HOME/.config/quicklysign/repos.json"

    # --- watchdog credentials: initial fallback ---
    # Short-lived owner session token, written early so the watchdog always has
    # *something*. Upgraded to a long-lived API token after install-agent-tools
    # below (once the coder CLI exists).
    umask 077
    printf '%s\n' \
      'CODER_URL=${data.coder_workspace.me.access_url}' \
      'CODER_SESSION_TOKEN=${data.coder_workspace_owner.me.session_token}' \
      'CODER_WORKSPACE_NAME=${data.coder_workspace.me.name}' \
      > "$HOME/.config/agent-watchdog/env"
    umask 022

    install-dev-tools   2>&1 | tee -a "$HOME/.local/state/install-dev-tools.log"
    install-agent-tools 2>&1 | tee -a "$HOME/.local/state/install-agent-tools.log"
    setup-repos         2>&1 | tee -a "$HOME/.local/state/setup-repos.log" || true

    # --- upgrade the watchdog credential to a long-lived, SELF-RENEWING token ---
    # The injected owner session token is short-lived, and Coder caps ANY token
    # at 168h/7d — so a token minted once silently expires a week later and the
    # workspace then autostops even while agents are actively working. The old
    # logic only re-minted on validation FAILURE, and re-minted from the owner
    # session token, which isn't fresh on automated/spot restarts — so the mint
    # failed and the dead token persisted for months.
    #
    # Fix: roll the token BEFORE it expires, using the token ITSELF as the mint
    # credential (no dependence on the owner session token in steady state). Each
    # boot: keep the stored token if it's valid AND younger than 4 days;
    # otherwise mint a fresh 168h token (from the stored token if still valid,
    # else the owner session token for cold start) under a unique name and swap
    # it in only after it validates. Boots are frequent, so this stays ahead of
    # the 7-day cap; a full cold start is only needed if the workspace sits
    # stopped >7 days.
    umask 077
    LL_FILE="$HOME/.config/agent-watchdog/api-token"
    OWNER_TOK='${data.coder_workspace_owner.me.session_token}'

    stored_valid=false
    if [ -s "$LL_FILE" ] && CODER_SESSION_TOKEN="$(cat "$LL_FILE")" coder whoami >/dev/null 2>&1; then
      stored_valid=true
    fi
    # Renew if the token is invalid/missing, or older than 4 days (3-day margin
    # under the 7-day cap). find -mtime +4 prints the file only when older.
    need_new=true
    if $stored_valid && [ -z "$(find "$LL_FILE" -mtime +4 2>/dev/null)" ]; then
      need_new=false
    fi
    if $need_new; then
      if $stored_valid; then MINT_TOK="$(cat "$LL_FILE")"; else MINT_TOK="$OWNER_TOK"; fi
      _name="watchdog-${data.coder_workspace.me.name}-$(date +%s)"
      _tok=$(CODER_SESSION_TOKEN="$MINT_TOK" coder tokens create --lifetime 168h --name "$_name" 2>/dev/null | tail -1 || true)
      # Only overwrite once the new token actually validates (a token contains a
      # hyphen, so don't pattern-match it — verify with whoami).
      if [ -n "$_tok" ] && CODER_SESSION_TOKEN="$_tok" coder whoami >/dev/null 2>&1; then
        printf '%s' "$_tok" > "$LL_FILE"
        # prune superseded watchdog-* tokens (best-effort; they'd auto-expire).
        CODER_SESSION_TOKEN="$_tok" coder tokens list -o json 2>/dev/null \
          | jq -r --arg keep "$_name" '.[]? | select((.token_name // .name // "") | startswith("watchdog-")) | select((.token_name // .name) != $keep) | .id' 2>/dev/null \
          | while read -r _id; do [ -n "$_id" ] && CODER_SESSION_TOKEN="$_tok" coder tokens remove "$_id" >/dev/null 2>&1 || true; done
      fi
    fi
    if [ -s "$LL_FILE" ]; then
      printf '%s\n' \
        'CODER_URL=${data.coder_workspace.me.access_url}' \
        "CODER_SESSION_TOKEN=$(cat "$LL_FILE")" \
        'CODER_WORKSPACE_NAME=${data.coder_workspace.me.name}' \
        > "$HOME/.config/agent-watchdog/env"
    fi
    umask 022

    # Pick up the refreshed credential after every (re)start.
    XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user restart agent-watchdog.service || true
  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 60
    timeout      = 5
  }
  metadata {
    display_name = "Memory Usage"
    key          = "mem_usage"
    script       = "coder stat mem"
    interval     = 60
    timeout      = 5
  }
  metadata {
    display_name = "Disk Usage"
    key          = "disk_usage"
    script       = "coder stat disk --path /home/coder"
    interval     = 600
    timeout      = 10
  }
  metadata {
    display_name = "Agent Lanes"
    key          = "agent_lanes"
    script       = "ls ~/.local/share/agent-sessions/*.json 2>/dev/null | wc -l | tr -d ' '"
    interval     = 60
    timeout      = 5
  }
}

# Persistent root disk: survives workspace stop (VM deletion) and Spot
# preemption. Everything — OS, installed tools, home dir, repos, Claude/Codex
# sessions and credentials — persists here.
resource "google_compute_disk" "root" {
  name   = "${local.workspace_name}-root"
  type   = "pd-balanced"
  zone   = var.zone
  image  = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
  size   = var.disk_size_gb
  labels = local.common_labels

  lifecycle {
    ignore_changes = [name, image]
  }
}

resource "google_compute_instance" "workspace" {
  count        = data.coder_workspace.me.start_count
  name         = local.workspace_name
  machine_type = data.coder_parameter.machine_type.value
  zone         = var.zone
  tags         = ["coder-workspace"]

  # Spot VM. The hashicorp/google provider requires all three of
  # preemptible/provisioning_model/automatic_restart to be set together.
  # DELETE on preemption matches Coder's stop semantics (count = 0 deletes
  # the VM, the root disk persists either way), so a preemption leaves the
  # same end state as a normal stop.
  scheduling {
    preemptible                 = true
    provisioning_model          = "SPOT"
    automatic_restart           = false
    instance_termination_action = "DELETE"
  }

  boot_disk {
    auto_delete = false # the disk is the workspace; never delete it with the VM
    source      = google_compute_disk.root.name
  }

  network_interface {
    network = var.network_name
    access_config {} # ephemeral public IP for egress; no inbound rules exist
  }

  service_account {
    email  = "coder-workspace@${var.project_id}.iam.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }

  labels = merge(local.common_labels, {
    coder_workspace = lower(data.coder_workspace.me.name)
  })

  metadata = {
    google-logging-enabled = "true"
  }

  # Runs as root on every boot. The first-boot bootstrap (scripts/startup.sh:
  # system packages, Docker, gh, gcloud) is persisted on the root disk and
  # skipped on later boots. Bootstrap failure is logged but never blocks the
  # agent — a reachable workspace with broken tooling beats an unreachable one.
  metadata_startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    if ! id -u ${local.linux_user} >/dev/null 2>&1; then
      useradd -m -s /bin/bash ${local.linux_user}
      echo "${local.linux_user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder-user
    fi

    echo '${base64encode(templatefile("${path.module}/scripts/startup.sh", { linux_user = local.linux_user }))}' | base64 -d > /opt/coder-bootstrap.sh

    if [ ! -f /var/lib/coder-base-setup-done ]; then
      if bash /opt/coder-bootstrap.sh >> /var/log/coder-bootstrap.log 2>&1; then
        touch /var/lib/coder-base-setup-done
        echo "first-boot bootstrap succeeded"
      else
        echo "WARNING: first-boot bootstrap FAILED (see /var/log/coder-bootstrap.log) — starting agent anyway"
      fi
    fi

    usermod -aG docker ${local.linux_user} 2>/dev/null || true

    exec sudo -u ${local.linux_user} sh -c '${coder_agent.main.init_script}'
  EOT
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = google_compute_instance.workspace[0].id

  item {
    key   = "machine type"
    value = data.coder_parameter.machine_type.value
  }
  item {
    key   = "spot"
    value = "yes (may be preempted; disk persists)"
  }
  item {
    key   = "zone"
    value = var.zone
  }
}

resource "coder_metadata" "disk_info" {
  resource_id = google_compute_disk.root.id

  item {
    key   = "persistent disk"
    value = "${var.disk_size_gb} GB pd-balanced"
  }
}
