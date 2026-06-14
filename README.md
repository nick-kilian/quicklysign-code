# quicklysign-coder

Self-hosted [Coder](https://coder.com) on GCP for QuicklySign development:
a small always-on control plane VM, and on-demand **Spot VM workspaces** with
agent-aware idle detection so Claude Code / Codex sessions keep the workspace
alive only while they're actually working.

| Component | What | Where |
|---|---|---|
| Control plane | `coderd` + Caddy (TLS) on an `e2-small` VM, static IP | `infra/terraform/` |
| Database | Cloud SQL Postgres 16 (`db-f1-micro`, private IP) | `infra/terraform/cloud-sql.tf` |
| Workspaces | `t2d-standard-4` Spot VMs, 200 GB persistent disk, Ubuntu 24.04 | `coder/templates/quicklysign-dev/` |
| Idle logic | hook-driven watchdog bumping `coder schedule extend` | `coder/templates/quicklysign-dev/scripts/` |

Access URL: **https://coder.ragingbucket.com** (Cloud Run was evaluated and
rejected for the control plane — see `docs/architecture.md` §1).

## Setup

Prereqs: `gcloud` (authenticated, with Application Default Credentials),
`terraform` >= 1.5, `coder` CLI, `jq`.

```bash
make bootstrap              # enable GCP APIs, check auth
make deploy-control-plane   # terraform apply; prints the DNS record to create
# create the printed A record: coder.ragingbucket.com -> <static ip>
# open https://coder.ragingbucket.com, create the admin account, then:
coder login https://coder.ragingbucket.com
make create-template        # push the quicklysign-dev workspace template
make open-coder
```

Create a `quicklysign-dev` workspace in the UI, then inside it (one-time,
persists on the workspace disk):

```bash
gh auth login                 # GitHub
setup-repos                   # clones the QuicklySign repos (repos.json)
claude                        # Claude Code login (browser-code flow over SSH)
codex login --device-auth     # Codex login
```

Daily flow from Warp (see `docs/operations.md`):

```bash
coder config-ssh                                  # once, locally
ssh quicklysign-dev.coder -t 'worklane trading-refactor'
```

## Agent work lanes

```bash
agent-run claude trading-refactor --repo quicklysign-python3 --ttl 4h
agent-run claude sharepoint-sync --repo quicklysign-office-365 --repo quicklysign-python3
agent-status                  # SESSION/AGENT/REPO/STATE/LAST_OUTPUT/LAST_CHANGE/TTL_LEFT
worklane trading-refactor     # attach; shows resume hints after VM restarts
```

Lanes are worktree-first: each lane gets its own git worktree(s) under
`~/lanes/<lane>/` on a branch named after the lane; the `~/src` clones stay
pristine. Multiple `--repo` flags build a multi-repo feature lane.

While a lane is **active** (agent hooks report work, terminal output, file
changes, busy child processes) the watchdog extends the Coder autostop
deadline. Waiting-for-input lanes get a 3-minute grace, then stop extending —
the workspace autostops, and you pick up later with `claude --continue` (from
the lane dir) / `codex resume --last`. Details: `docs/idle-detection.md`.

## Cost drivers (us-west1, rough estimates)

| Item | ~Cost | Notes |
|---|---|---|
| Control plane `e2-small` | ~$13/mo | always on; the price of "Coder is always reachable" |
| Control plane disk + static IP | ~$5/mo | |
| Cloud SQL `db-f1-micro` + 10 GB | ~$10/mo | always on (Coder requires Postgres) |
| Workspace disk 200 GB pd-balanced | ~$20/mo | charged **even when the workspace is stopped** |
| Workspace `t2d-standard-4` Spot | ~$0.03–0.05/hr | only while running; ~60–91% below on-demand |
| Stopped workspace | disk only | VM is deleted on stop; restart ~30 s |

Fixed floor ≈ **$48/mo** + a few cents per workspace-hour. Spot caveat: Google
can preempt the VM at any time (30 s notice). That equals a normal stop here —
the disk persists, restart and resume. Don't run irreplaceable long
unattended jobs without checkpoints.

## Repo map

```
infra/terraform/          control plane: VPC, Cloud SQL, secrets, IAM, VM
coder/templates/quicklysign-dev/   workspace template + scripts + repos.json
scripts/                  bootstrap / deploy / template push / open
docs/                     architecture, operations, idle-detection, security
```

## TODO — values/decisions still open

- [x] **DNS**: `coder.ragingbucket.com A 35.252.103.129` (Cloudflare, **DNS only** — do not proxy; it breaks ACME and the WebSocket relay).
- [x] **repos.json**: the 5 active QuicklySign repos (python3, monitoring, ml, office-365, conversion-v2). Edit + `make create-template` to change.
- [ ] **Logins** (once per workspace): `gh auth login`, `claude`, `codex login --device-auth`.
- [ ] Optional: GitHub external auth via a Coder OAuth app later (replaces per-workspace `gh auth login`); subdomain wildcard (`CODER_WILDCARD_ACCESS_URL`) only if you want dashboard port-forwarding — needs a DNS-01 wildcard cert, deliberately skipped for now.
