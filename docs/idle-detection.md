# Agent-Aware Idle Detection

## Overview
Coder's built-in inactivity detection monitors SSH, VS Code, and JetBrains sessions. However, long-running agentic tasks (like `claude` or `codex` CLI) may not trigger these activity signals if the human is disconnected.

To prevent premature shutdown of the workspace during agent work, we implement an `agent-watchdog.sh` script.

## Heuristics for "Active Work"

A session is considered **Active** if any of the following are true within the configured windows:

1.  **Terminal Output**: The tmux pane associated with the agent session has received new output in the last `ACTIVE_OUTPUT_WINDOW_SECONDS` (default: 180s).
2.  **File Activity**: Any files in the workspace (excluding `.git`, `node_modules`, `__pycache__`) have been modified in the last `ACTIVE_FILE_CHANGE_WINDOW_SECONDS` (default: 300s).
3.  **Active Processes**: Child processes associated with common dev tasks are running (e.g., `npm`, `pytest`, `uv`, `go test`, `docker`).
4.  **Grace Period**: If an agent is "Waiting for Input", it is granted a `WAITING_FOR_INPUT_GRACE_SECONDS` (default: 180s) before it is considered idle.

## Mechanism

### `agent-run`
A wrapper script that:
- Starts the agent in a named tmux session.
- Writes metadata to `~/.local/share/agent-sessions/<name>.json`.
- Records the start time and requested TTL.

### `agent-watchdog.sh`
A background service (systemd user unit) that:
- Iterates through all registered sessions in `~/.local/share/agent-sessions/`.
- Inspects the corresponding tmux pane for recent activity (using `tmux capture-pane` and checksums or timestamps).
- If active, executes `coder schedule extend 45m`.
- If a session exceeds its `MAX_AGENT_TTL_SECONDS` (default: 8h), it stops bumping the deadline.

## Configuration Defaults
```bash
ACTIVE_OUTPUT_WINDOW_SECONDS=180
ACTIVE_FILE_CHANGE_WINDOW_SECONDS=300
WAITING_FOR_INPUT_GRACE_SECONDS=180
DEFAULT_AGENT_TTL_SECONDS=14400 # 4 hours
MAX_AGENT_TTL_SECONDS=28800     # 8 hours
WATCHDOG_INTERVAL_SECONDS=60
AUTOSTOP_BUMP_MINUTES=45
```
