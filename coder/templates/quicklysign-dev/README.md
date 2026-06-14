# quicklysign-dev — Coder workspace template

Provisions a GCP **Spot VM** (`t2d-standard-4`, switchable to `-8`) in
`us-west1-a` with a **200 GB persistent root disk**, Ubuntu 24.04 LTS, Docker,
and the full QuicklySign toolchain.

## How it works

- **The disk is the workspace.** The VM is ephemeral: `coder stop` (and Spot
  preemption) deletes the VM; the root disk (`auto_delete = false`) keeps the
  OS, tools, repos, and all Claude/Codex sessions and credentials. `coder
  start` recreates the VM on the same disk in ~30s.
- **Agent auth** uses `google-instance-identity`: the agent proves itself with
  a Google-signed JWT from the metadata server. No secrets in VM metadata.
- **First boot** installs system packages + Docker as root, then the agent
  startup script installs user tooling (mise/node 22/pnpm, uv/python 3.12,
  devcontainers CLI, Claude Code, Codex, the watchdog). First boot takes a few
  minutes; later boots skip all of it.
- **Startup orchestration** lives in `main.tf` (the root
  `metadata_startup_script` and the agent `startup_script`) rather than a
  separate `startup.sh` — the scripts in `scripts/` are bundled into the agent
  startup script via Terraform `file()`/`base64encode()`, so pushing the
  template updates them in place.

## Files

| File | Purpose |
|---|---|
| `main.tf` / `variables.tf` | the template |
| `repos.json` | QuicklySign repos cloned by `setup-repos` (edit + re-push to change) |
| `repos.example.json` | schema example |
| `scripts/install-dev-tools.sh` | user-level toolchain (one-time) |
| `scripts/install-agent-tools.sh` | Claude/Codex/coder CLIs, hooks, watchdog service |
| `scripts/setup-repos.sh` | clones `repos.json` via `gh` credentials |
| `scripts/agent-run` | start a named agent lane in tmux |
| `scripts/agent-watchdog.sh` | extends Coder autostop while agents work |
| `scripts/agent-status.sh` | lane status table |
| `scripts/agent-activity-hook.sh` | Claude/Codex hook → working/waiting signals |
| `scripts/worklane` | attach to a lane, with resume hints after restarts |

## One-time setup inside a new workspace

Credentials persist on the disk, so each of these happens once per workspace:

```bash
gh auth login          # GitHub (then: setup-repos)
claude                 # Claude Code: browser-code login works over SSH
codex login --device-auth   # Codex: device-code flow for headless
```

## Pushing changes

```bash
make create-template   # from the repo root, or:
coder templates push quicklysign-dev --directory coder/templates/quicklysign-dev --yes
```

Workspaces pick up script/repos.json changes on their next start.
