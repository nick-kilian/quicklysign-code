# Agent-aware idle detection

## The gap this fills

Coder's built-in activity bump only counts **connection** activity: SSH, IDE
sessions, the web terminal. In-workspace background processes explicitly do
not count ([Coder discussion #18897](https://github.com/coder/coder/discussions/18897)).
So a Claude Code session grinding through a refactor with no human attached
would let the workspace hit its 1-hour autostop mid-task.

The fix is `agent-watchdog`, a systemd **user** service on every workspace
that extends the autostop deadline — but only while agents are doing useful
work.

### Connection activity is deliberately disabled

We set the template's **`activity_bump = 0`** so that an open connection does
*not* extend the deadline either. The reasoning: a Warp window left attached to
an idle SSH/tmux session would otherwise keep the workspace (and its cost) alive
indefinitely. With the bump at zero, `agent-watchdog`'s explicit
`coder schedule extend` is the **only** thing that pushes the deadline out — so
the workspace stays up exactly when an agent is working and stops otherwise,
regardless of idle connections.

Trade-off: **manual (non-agent) work also won't auto-extend.** A plain
interactive session stops at the `default_ttl` deadline (1 h from start) unless
an agent lane is active. To hold the workspace open for hands-on work, run it in
an agent lane or bump manually: `coder schedule extend quicklysign-dev 2h`.

> Setting `activity_bump = 0` via the CLI is a no-op on coder < 2.34 (the zero
> value is dropped, omitempty); it was applied via the API and persists as a
> template-level setting. See `scripts/create-template.sh`.

## Signals (best to worst)

1. **Agent lifecycle hooks** (precise, event-driven):
   - *Claude Code*: hooks in `~/.claude/settings.json` —
     `UserPromptSubmit`/`PreToolUse`/`PostToolUse` → **working**;
     `Stop`/`Notification` → **waiting for input**; `SessionEnd` → idle.
   - *Codex*: `notify` in `~/.codex/config.toml` fires on
     `agent-turn-complete` → **waiting**. (Codex has no "started working"
     notify; it falls back to the heuristics below for the working signal.)
   - Both call `agent-activity-hook`, which writes
     `~/.local/share/agent-sessions/signals/<cwd-key>.state` (+ an
     `.activity` timestamp file).
2. **tmux pane content change**: hash of `tmux capture-pane` differs between
   watchdog ticks.
3. **Busy child processes** in the lane's pane: `pytest|npm|pnpm|uv|docker|
   make|cargo|tsc|jest|vitest|…`. Bare `node`/`python` are deliberately
   excluded — the agents and their MCP servers run on those and would read as
   permanently busy.
4. **Recent file changes** in the lane's repo (`.git`, `node_modules`,
   `.venv`, `__pycache__` pruned).

"A tmux session exists" is **not** a signal.

## Decision rules (per lane, every tick)

```
tmux session gone                  -> finished  (never bumps)
now - last_active > ttl_seconds    -> expired   (inactivity timeout; revives on activity)
hook says "waiting":
    within grace window            -> waiting-grace  (still bumps)
    busy children or file changes  -> active         (work outlasted the prompt)
    otherwise                      -> waiting        (stops bumping)
hook says "working" recently       -> active
pane changed / files changed /
busy children within windows       -> active
otherwise                          -> idle           (stops bumping)
```

If **any** lane is active (or in waiting-grace), the watchdog checks the
workspace deadline via `coder list --output json` and, when less than the
bump amount remains, runs:

```
coder schedule extend <workspace> 60m
```

This is the current supported CLI mechanism (verified June 2026; alias of the
older `override-stop`; equivalent API: `PUT /api/v2/workspaces/{id}/extend`).
The deadline therefore hovers ≤60 min ahead while work continues and runs out
naturally when it stops — so the bump window doubles as the idle grace: work
stops, the workspace coasts ~1 h, then autostops. Decisions are logged to
`~/.local/state/agent-watchdog.log`.

### Authentication

At boot the startup script mints a **long-lived Coder API token** (server max
168h/7d) using the freshly-injected owner session token, persists it to
`~/.config/agent-watchdog/api-token`, and writes it into
`~/.config/agent-watchdog/env` (mode 0600) for the systemd unit; it is reused
across boots until it stops validating. The short-lived owner session token is
only an initial fallback — it is OIDC-session-bound and expired ~13 h into
uptime, which silently broke `coder schedule extend` and autostopped the
workspace with active sessions. Agent tokens (`CODER_AGENT_TOKEN`) cannot call
the user-level extend endpoint, so a user/API token is required.

## Configuration

Defaults live in `agent-watchdog.sh`; override any of them in
`~/.config/agent-watchdog/config` (plain shell, persists on the disk):

```bash
ACTIVE_OUTPUT_WINDOW_SECONDS=180     # output within 3 min  => active
ACTIVE_FILE_CHANGE_WINDOW_SECONDS=300 # file change within 5 min => active
WAITING_FOR_INPUT_GRACE_SECONDS=180  # waiting gets 3 min grace
DEFAULT_AGENT_TTL_SECONDS=3600       # INACTIVITY timeout (reset on activity), 1 h
MAX_AGENT_TTL_SECONDS=14400          # ceiling for per-lane --ttl overrides
WATCHDOG_INTERVAL_SECONDS=60
AUTOSTOP_BUMP_MINUTES=60
```

## Lifecycle example

1. `agent-run claude trading-refactor --repo ~/src/quicklysign-python3 --ttl 4h`
2. You disconnect. Claude keeps working → hooks fire → watchdog bumps the
   deadline whenever <60 min remain.
3. Claude finishes and asks a question → `Stop` hook → waiting; 3 min grace
   passes → lane stops bumping.
4. No other activity → deadline expires → Coder stops the workspace (VM
   deleted, disk persists).
5. Later: `coder start`, then `worklane trading-refactor` → fresh tmux session
   with the hint `claude --resume trading-refactor`. Codex lanes:
   `codex resume --last` from the repo directory.

## Known limitations (deliberate trade-offs)

- Signals are keyed by the lane's working directory; two lanes in the same
  repo directory share hook signals (use separate worktrees if that matters).
- Codex "working" detection is heuristic-only (no start-of-turn notify); in
  the worst case an actively-working-but-silent Codex lane is treated as
  waiting after the grace period.
- tmux-resurrect/continuum (optional, see `.tmux.conf`) restore *layouts*
  only — never running agent processes. The durable mechanism is agent resume
  plus the metadata under `~/.local/share/agent-sessions/`.
- If the watchdog dies, systemd restarts it; if it stays dead, the workspace
  simply autostops on Coder's normal schedule — the failure mode is "stops
  too early", never "runs forever". The TTL cap bounds the opposite risk.
