# Architecture

All claims below were verified against official Coder docs/source in June 2026
(Coder ~v2.34.x). Sources are linked inline.

## 1. Can the Coder server run reliably on Cloud Run?

**No — and we deploy it on a small GCE VM instead.**

- Cloud Run appears in no official Coder install path. The official GCP
  options are Compute Engine and GKE
  ([install docs](https://coder.com/docs/install/cloud)).
- Coder requires a **static, non-autoscaled control plane**: "We don't
  recommend that you autoscale the Coder Servers… Stopping a Coder Server
  instance will (momentarily) disconnect any users currently connecting
  through that instance"
  ([scale best practices](https://coder.com/docs/tutorials/best-practices/scale-coder)).
  Cloud Run's instance churn / scale-to-zero violates this directly.
- All IDE/SSH/terminal traffic that can't go peer-to-peer is relayed through
  **DERP inside coderd over long-lived WebSockets**
  ([networking docs](https://coder.com/docs/admin/networking)). Cloud Run
  treats WebSockets as ordinary requests subject to its **60-minute maximum
  timeout** ([GCP docs](https://cloud.google.com/run/docs/triggering/websockets)),
  so every relayed session would be severed at least hourly.
- The previous iteration of this repo also had a Terraform cycle (the Cloud
  Run service referenced its own `.uri` as `CODER_ACCESS_URL`), so the Cloud
  Run path never actually deployed.

**Decision:** `e2-small` Debian 12 VM (Coder's documented minimum is 1 vCPU /
2 GB per [scale-testing](https://coder.com/docs/admin/infrastructure/scale-testing)),
running the official `coder` deb package under systemd, behind Caddy for TLS.

## 2. Does Coder require PostgreSQL?

**Yes — Postgres 13+.** coderd has a bundled Postgres for evaluation, but the
docs recommend external Postgres for production
([architecture](https://coder.com/docs/admin/infrastructure/architecture),
[setup](https://coder.com/docs/admin/setup)). We use **Cloud SQL Postgres 16,
`db-f1-micro`, private IP only** (VPC peering); the connection URL lives in
Secret Manager and is fetched by the control plane VM at boot.

## 3. How is the server exposed publicly and securely?

- Reserved **static IP** + DNS A record: `coder.ragingbucket.com`.
- **Caddy** terminates TLS (automatic Let's Encrypt) and proxies to coderd on
  `127.0.0.1:3000`. Caddy fully supports WebSockets.
- `CODER_ACCESS_URL=https://coder.ragingbucket.com`. The built-in
  `*.try.coder.app` tunnel is testing-only (URL changes every restart —
  [coder#1176](https://github.com/coder/coder/issues/1176)), so it is not used.
- `CODER_WILDCARD_ACCESS_URL` (subdomain apps / dashboard port forwarding) is
  **deliberately omitted**: it would require a DNS-01 wildcard certificate.
  Path-based apps and `coder port-forward` over SSH still work.
- Firewall: only 80/443 to the control plane; SSH only via IAP tunnel.

## 4. How do workspace agents connect back?

**Outbound-only from the agent** over HTTPS/WebSocket to the access URL; no
inbound connectivity to workspaces is needed
([networking](https://coder.com/docs/admin/networking)). Direct client↔agent
connections upgrade to WireGuard via STUN when possible; otherwise traffic
relays through coderd's DERP. Workspace VMs have an ephemeral public IP for
egress but **zero inbound firewall rules**.

Agent **authentication** uses `auth = "google-instance-identity"`: the agent
exchanges a Google-signed identity JWT (from the metadata server) for its
session, and coderd matches the instance ID recorded by the Terraform
provisioner. No agent token is ever placed in VM metadata (Coder's own
tooling warns tokens in metadata are insecure on VMs).

## 5. How is autostop/autostart configured?

- Template-level **default autostop (TTL)**: 1 hour (set by
  `scripts/create-template.sh`; adjustable per workspace).
- Coder's built-in **activity bump** extends the deadline on *connection*
  activity: SSH, VS Code/JetBrains, web terminal
  ([workspace scheduling](https://coder.com/docs/user-guides/workspace-scheduling)).
- **In-workspace background processes do NOT count as activity** — confirmed
  by maintainers ([discussion #18897](https://github.com/coder/coder/discussions/18897)).
  This is exactly the gap the agent watchdog fills (see
  `docs/idle-detection.md`).
- Autostop *requirement*, dormancy, etc. are Premium and not needed here.

## 6. How do you extend an autostop deadline programmatically?

Two supported mechanisms, both verified:

- CLI: **`coder schedule extend <workspace> <duration>`** (alias of the older
  `override-stop`; new deadline is computed from now)
  ([CLI reference](https://coder.com/docs/reference/cli/schedule_extend)).
- API: **`PUT /api/v2/workspaces/{workspace}/extend`** with
  `{"deadline": "<RFC3339>"}` and a *user* session token
  ([API reference](https://coder.com/docs/reference/api/workspaces)).

Inside the workspace, the CLI is authenticated via
`data.coder_workspace_owner.me.session_token` (regenerated each workspace
start), written to a 0600 env file consumed by the watchdog's systemd unit.
`CODER_AGENT_TOKEN` cannot call user endpoints. The `coder` binary is
downloaded from our own deployment (`$CODER_URL/bin/coder-linux-amd64`) so
versions always match.

Note: Coder now also has first-class "Tasks"/AgentAPI integration where agent
status counts as activity — a possible future simplification, but the
watchdog approach works with plain tmux + CLI sessions, which is the workflow
here.

## 7. How does the template provision Spot VMs?

Per the `hashicorp/google` provider docs, all three scheduling fields must be
set together:

```hcl
scheduling {
  preemptible                 = true
  provisioning_model          = "SPOT"
  automatic_restart           = false
  instance_termination_action = "DELETE"
}
```

`DELETE` (not `STOP`) on preemption: following the official `gcp-linux`
template pattern, `coder stop` sets `count = 0` and deletes the VM anyway,
while the root disk (`auto_delete = false`, `lifecycle ignore_changes`)
persists. A preemption therefore leaves the identical end state as a normal
stop — restart from Coder and resume. A `STOP`ped instance would instead
linger as Terraform drift.

## 8. What does Community edition cover?

Everything this setup needs, free: unlimited users/workspaces/templates,
autostart/autostop TTL, activity bump, SSH/IDE/web terminal, full API/CLI.
Premium adds enforced autostop requirement, dormancy cleanup, quotas, RBAC,
HA — none required for a single-user deployment
([template schedule docs](https://coder.com/docs/admin/templates/managing-templates/schedule),
[pricing](https://coder.com/pricing)).

## Component diagram

```
            ┌──────────────────── GCP project: quicklysign-terraform-dev ──────────┐
            │                                                                      │
 Warp/IDE ──┼──► https://coder.ragingbucket.com (static IP)                        │
            │      Caddy (TLS) ──► coderd :3000  ── e2-small VM, coder-vpc         │
            │                        │  ▲                                          │
            │      Cloud SQL ◄───────┘  │ outbound WebSocket (agent)               │
            │      Postgres 16          │                                          │
            │      (private IP)       Spot VM t2d-standard-4 (per workspace)       │
            │                         200GB persistent root disk (survives stop)   │
            │                         Docker · tmux · claude · codex · watchdog    │
            └──────────────────────────────────────────────────────────────────────┘
```
