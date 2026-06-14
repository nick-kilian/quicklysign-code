# Operations

## Initial deployment

```bash
gcloud auth login && gcloud auth application-default login
make bootstrap              # enables APIs in quicklysign-terraform-dev
make deploy-control-plane   # terraform apply; prints the DNS record
```

Create the printed DNS record (`coder.ragingbucket.com A <static-ip>`), wait
~2 minutes for VM bootstrap + Let's Encrypt, then:

```bash
open https://coder.ragingbucket.com    # first visit creates the admin account
coder login https://coder.ragingbucket.com
make create-template
```

Create a workspace from the `quicklysign-dev` template in the UI (or
`coder create --template quicklysign-dev quicklysign`). First start takes a
few minutes (tool install); subsequent starts ~30 s.

### One-time inside the workspace (persists on the disk)

```bash
gh auth login                # GitHub → then: setup-repos
claude                       # press 'c' for the login URL, paste code back (SSH-friendly)
codex login --device-auth    # device-code flow
```

## Warp workflow

Warp is the local cockpit; tmux is the remote cockpit; agent resume is the
recovery mechanism.

```bash
coder config-ssh             # once per machine: adds `<workspace>.coder` SSH hosts
```

Then one Warp tab per lane, named to match the lane:

```bash
ssh quicklysign-dev.coder -t 'worklane trading-refactor'
ssh quicklysign-dev.coder -t 'worklane frontend-form-fix'
```

(`coder ssh quicklysign-dev` works too; the `config-ssh` host plays nicer
with Warp features.) Connecting via SSH counts as Coder activity, so the
workspace won't stop under you while a tab is attached.

Name alignment convention — one name across all four layers:

```
Warp tab title == tmux session == Claude session name == lane
trading-refactor / frontend-form-fix / api-performance / cloud-tasks-debug
```

## Daily commands

Lanes are **worktree-first**: pointing `--repo` at a `~/src` checkout (bare
name or path) automatically creates a per-lane git worktree at
`~/lanes/<lane>/<repo>` on a branch named after the lane. The `~/src` clones
stay pristine — they are fetch sources, never working copies. Two lanes can
work the same repo without touching each other's diffs.

```bash
# single-repo lane: worktree at ~/lanes/trading-refactor/quicklysign-python3
agent-run claude trading-refactor --repo quicklysign-python3 --ttl 4h

# multi-repo feature lane: one parent dir, a worktree per repo, same branch
agent-run claude sharepoint-metadata-sync \
  --repo quicklysign-office-365 --repo quicklysign-python3

# escape hatch: run directly in an arbitrary directory
agent-run codex scratch-task --repo ~/scratch --no-worktree

# inspect
agent-status                  # lanes, states, TTLs
tmux ls

# attach / detach
worklane trading-refactor     # attach (Ctrl-b d to detach, lane keeps working)
```

Branches: the lane's worktrees reuse an existing local/`origin` branch named
after the lane if one exists (continuing in-flight work), otherwise the branch
is created from each repo's default. `lane-init <lane> <repos…> [--branch <n>]`
scaffolds the worktrees without starting an agent.

Tear-down once merged: `git -C ~/src/<repo> worktree remove ~/lanes/<lane>/<repo>`
per repo, then `rm -rf ~/lanes/<lane>`.

## Accessing workspace app / admin UIs locally

quicklysign-python3 runs under devcontainers, which publish each worktree's app
and admin UIs to **dynamic** host ports (32768+). Rather than chase those with
hand-rolled `ssh -L` per port, run the follower from your Mac:

```bash
make forward                              # follows quicklysign-dev.coder
# or: ./scripts/forward-ports.sh <workspace>.coder [poll-seconds]
```

It opens one shared SSH master and keeps `-L` forwards in sync with whatever
the workspace is serving — mirroring each remote port to the **same** local
port (we assume no local clashes). Start a new devcontainer and its port shows
up locally within a poll (default 5s); tear it down and the forward drops:

```
+ http://localhost:32768 (quicklysign-python3-app:3000)
+ http://localhost:8025  (host:8025)
- localhost:32768 (gone)
```

Leave it running in its own Warp tab. It **never starts a stopped workspace**
(that would defeat autostop): when the workspace stops it goes dormant and
waits, then re-attaches on its own once the workspace is next started — so it
follows restarts / Spot preemption without keeping the workspace alive. Ctrl-C
tears everything down. The remote side is enumerated by `list-app-ports` on the
workspace (Docker-published ports + host listeners in `DEV_PORT_LO..DEV_PORT_HI`,
default 3000–9999); run it over SSH to see what would be forwarded:

```bash
ssh quicklysign-dev.coder list-app-ports
```

## After a workspace stop/start (incl. Spot preemption)

tmux sessions and processes are gone; disk state, credentials, and agent
session history persist.

```bash
coder start quicklysign-dev          # or the UI
ssh quicklysign-dev.coder -t 'worklane trading-refactor'
# inside the fresh session, as hinted by worklane:
claude --continue                    # Claude: most recent session in this dir
codex resume --last                  # Codex: most recent session in this directory
```

## Watching the watchdog

```bash
tail -f ~/.local/state/agent-watchdog.log     # decisions + bumps
coder schedule show quicklysign-dev           # current deadline
systemctl --user status agent-watchdog        # service health
coder schedule extend quicklysign-dev 2h      # manual override
```

## Maintenance

| Task | How |
|---|---|
| Update Coder server | `gcloud compute ssh coder-control-plane --tunnel-through-iap` → `sudo apt-get update && sudo apt-get install -y coder && sudo systemctl restart coder` (or re-run the install script) |
| Update workspace scripts/repos.json | edit, then `make create-template`; workspaces pick it up on next start |
| Control plane logs | `journalctl -u coder -f` on the VM (also in Cloud Logging) |
| Workspace agent logs | `/tmp/coder-agent.log` on the workspace |
| Tear down a workspace | delete in the Coder UI (deletes VM **and** its disk) |
| Tear down everything | `make destroy` (Cloud SQL needs `deletion_protection = false` first — intentional) |

## Spot preemption behaviour

Google may reclaim a Spot VM with ~30 s notice. Configured action is DELETE,
which is identical to a normal Coder stop: the persistent disk survives,
Coder shows the workspace as unreachable/stopped, and you `coder start` +
resume. Cost trade-off: ~60–91% cheaper compute for occasionally having to
restart. If preemptions get annoying in `us-west1-a`, change the template
`zone` variable… but note existing workspace disks are zonal and stay behind.
