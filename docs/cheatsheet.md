# QuicklySign Coder — Cheat Sheet

Workspace: **quicklysign-dev** · URL: **https://coder.ragingbucket.com** · SSH host: **quicklysign-dev.coder**

---

## Local (your Mac / Warp)

```bash
coder login https://coder.ragingbucket.com   # once
coder config-ssh                              # once per machine → creates <ws>.coder host

coder list                                    # workspaces + status + "outdated?"
coder start   quicklysign-dev                 # power on (VM rebuilt, ~30s; disk persists)
coder stop    quicklysign-dev                 # power off (VM deleted, disk kept)
coder restart quicklysign-dev                 # rebuild on the SAME template version
coder update  quicklysign-dev                 # rebuild on the LATEST template version  ← use after `make create-template`

ssh quicklysign-dev.coder                     # plain shell (lets Warp warpify) → then run `worklane`
make forward                                  # mirror workspace app/admin ports to localhost (follows devcontainer ports)
make open-coder                               # open the dashboard
```

`restart` ≠ `update`: a plain restart keeps the old template; pushing a new template needs **`coder update`** to take effect.

## Make targets (repo admin, run locally)

```bash
make bootstrap            # enable GCP APIs / check auth
make deploy-control-plane # terraform apply (VPC, Cloud SQL, control-plane VM)
make create-template      # push workspace template after editing coder/templates/...  (then `coder update`)
make forward              # dynamic port-forward
make plan / fmt / validate / destroy
```

---

## Inside the workspace — work lanes

A **lane** = a named tmux session + a git worktree per repo on a branch named after the lane. `~/src` clones stay pristine; worktrees live in `~/lanes/<lane>/`.

```bash
# create + start a lane (auto-creates worktree(s); attaches you)
agent-run claude trading-refactor --repo quicklysign-python3 --ttl 4h
agent-run claude sharepoint-app   --repo quicklysign-office-365 --repo quicklysign-python3   # multi-repo
agent-run codex  scratch          --repo ~/scratch --no-worktree                            # run as-is, no worktree

worklane sharepoint-app           # attach (or recreate after a restart) + show resume hints
worklane                          # list known lanes
agent-status                      # all lanes: agent / repo / state / last output / TTL left
lane-init <lane> <repos...>       # scaffold worktrees WITHOUT starting an agent
setup-repos                       # (re)clone the repos from repos.json into ~/src
list-app-ports                    # what `make forward` would mirror
```

Flags for `agent-run`: `--repo` (repeatable), `--ttl <1h|90m|300s>` (default 1h, max 4h — an **inactivity** timeout the watchdog resets on activity, not a lifetime cap), `--no-worktree`, `-- <extra agent args>`.

## Resuming agents (after a stop / restart / Spot preemption)

tmux sessions are gone; disk, credentials, and agent history persist.

```bash
worklane <lane>          # recreate the session in the right dir, prints the resume hint
claude --continue        # Claude: most recent session in THIS directory   (NOT `--resume <name>`)
claude --resume          # Claude: pick from a list (named after the lane)
codex resume --last      # Codex: most recent session in this dir
```

## tmux quick keys

```
Ctrl-b d     detach (lane keeps running)        Ctrl-b c   new window
Ctrl-b [     scroll mode (q to exit)            Ctrl-b "   split horizontal / %  vertical
tmux ls      list sessions
```

---

## Idle / autostop (the watchdog)

While a lane is **active** (agent hooks, terminal output, file changes, busy children) the watchdog extends the autostop deadline. Idle/waiting → 3-min grace, then it stops extending and the workspace autostops. The lane TTL is an **inactivity timeout** (default 1h): it resets on every active tick, so active work is never force-stopped; a lane only expires after 1h idle (and revives the moment work resumes).

**An open SSH/Warp connection does NOT keep the workspace alive** (template `activity_bump = 0`). Only active agent work extends it. For hands-on (non-agent) work, run in a lane or `coder schedule extend quicklysign-dev 2h`.

```bash
coder schedule show   quicklysign-dev      # current deadline
coder schedule extend quicklysign-dev 2h   # manual override
tail -f ~/.local/state/agent-watchdog.log  # decisions + bumps
systemctl --user status agent-watchdog
```

## Port forwarding (devcontainer apps)

```bash
make forward                                       # local; follows dynamic ports, mirrors remote→same local port
ssh quicklysign-dev.coder list-app-ports           # see current app ports
DEV_PORT_LO=8000 ssh quicklysign-dev.coder list-app-ports   # raise the host-listener floor
```

## Warp over SSH

`ssh quicklysign-dev.coder` (plain) → accept **"Install Warp's SSH extension"** → then `worklane`.
Settings → Warpify: keep **"Use Tmux Warpification" OFF** (it breaks here). Verify: `ls -d ~/.warp/remote-server`.

## One-time per workspace (persists on disk)

```bash
gh auth login        # GitHub → then setup-repos
claude               # browser-code login (works over SSH)
codex login --device-auth
gemini               # Google OAuth (if using gemini-cli)
```

---

## Repos (`repos.json`)

quicklysign-python3 · quicklysign-monitoring · quicklysign-ml · quicklysign-office-365 · quicklysign-conversion-v2
Edit `coder/templates/quicklysign-dev/repos.json` → `make create-template` → `coder update`.

## Naming convention

One name across all layers: **Warp tab title = tmux session = Claude session = lane** (e.g. `sharepoint-app`).
