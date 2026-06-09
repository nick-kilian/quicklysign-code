# Architecture: QuicklySign Coder on GCP

## 1. Research & Planning Answers

### 1.1 Can Coder server run reliably on Cloud Run?
**Technically Viable, but UX Impacted.** Cloud Run supports WebSockets, but imposes a **60-minute hard timeout** on all requests (including WebSockets). This means every hour, your IDE (VS Code, JetBrains) or terminal connection will drop and need to reconnect. Additionally, Cloud Run is ephemeral; while Coder's state is in Postgres, the control plane's local filesystem is lost on restart.
**Recommendation:** We will implement the Cloud Run version as the primary target per your preference, but include the "Small VM" fallback logic in the Terraform. For production-grade stability without 60-minute drops, the VM is superior.

### 1.2 Does it require PostgreSQL?
**Yes.** Coder requires a PostgreSQL database (version 13+). We will use **Cloud SQL for PostgreSQL** (db-f1-micro or similar) to ensure persistence and ease of management.

### 1.3 How should the Coder server be exposed publicly and securely?
For Cloud Run, we use the provided `.a.run.app` URL (or a custom domain). We will secure it by:
- Enabling **Session Affinity** on Cloud Run.
- Requiring authentication for all Coder access.
- Using Secret Manager for the Coder database connection string and session tokens.

### 1.4 How should Coder agents connect back to the Coder server?
Coder agents running on Workspace VMs connect to the **CODER_ACCESS_URL** over HTTPS/WebSockets. This URL must be reachable from the VPC or the public internet (depending on network config). We will use public exposure for simplicity unless IAP/Tailscale is requested.

### 1.5 Best way to configure Coder workspace autostop/autostart?
We will use the `coder_workspace` resource in Terraform to define:
- `default_ttl`: 1 hour.
- `autostop_block`: To handle scheduled stops.
- `startup_script`: To ensure the agent starts correctly.

### 1.6 What API/CLI mechanism exists to extend or update a workspace autostop deadline?
The `coder schedule extend <duration>` CLI command is the most reliable way to bump the deadline from within the workspace. Alternatively, the REST API `PUT /api/v2/workspaces/{id}/autostop` can be used to set a specific timestamp.

### 1.7 How should a workspace template provision GCP Spot VMs?
In the Coder Terraform template, the `google_compute_instance` resource will specify:
```hcl
scheduling {
  provisioning_model = "SPOT"
  preemptible        = true
  automatic_restart  = false
}
```
We will also use `instance_termination_action = "STOP"` to allow Coder to see the VM as stopped rather than deleted.

### 1.8 What Coder license/features are available in Community edition for this setup?
**Community Edition** covers:
- Unlimited users and workspaces.
- Standard autostop/autostart.
- Inactivity detection (SSH/IDE).
- VS Code / JetBrains / SSH support.
- API/CLI access.
**Enterprise** (not needed here) adds enforced "Required Stop", Quotas, and RBAC.

## 2. Component Mapping

- **Control Plane**: Cloud Run (Container: `codercom/coder`).
- **Database**: Cloud SQL (PostgreSQL).
- **Workspaces**: GCP Compute Engine (Spot VMs).
- **Networking**: Cloud Run Load Balancer / DNS.
- **Secrets**: GCP Secret Manager.
- **Agent Watchdog**: Custom shell scripts using `coder schedule extend`.

## 3. Idle Detection Logic

We will implement a heuristic-based watchdog that checks for:
1. Active `claude` or `codex` tmux sessions.
2. Recent stdout/stderr activity in those sessions.
3. Recent file changes in the workspace.
4. Active child processes (test runners, etc.).

If "active work" is detected, the watchdog runs `coder schedule extend 45m` every 30 minutes.
