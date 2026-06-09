#!/bin/bash
# agent-watchdog.sh: Bumps Coder autostop deadline if agent work is detected

LOG_FILE="$HOME/.local/state/agent-watchdog.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Config (can be moved to a file)
ACTIVE_OUTPUT_WINDOW_SECONDS=180
ACTIVE_FILE_CHANGE_WINDOW_SECONDS=300
WAITING_FOR_INPUT_GRACE_SECONDS=180
WATCHDOG_INTERVAL_SECONDS=60
AUTOSTOP_BUMP_MINUTES=45

echo "$(date) - Watchdog started" >> "$LOG_FILE"

while true; do
    ANY_ACTIVE=false
    
    for meta in "$HOME/.local/share/agent-sessions/"*.json; do
        [ -e "$meta" ] || continue
        
        SESSION_NAME=$(basename "$meta" .json)
        AGENT_TYPE=$(jq -r '.agent_type' "$meta")
        REPO_PATH=$(jq -r '.repo_path' "$meta")
        
        # 1. Check if tmux session still exists
        if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            jq ".status = \"finished\"" "$meta" > "$meta.tmp" && mv "$meta.tmp" "$meta"
            continue
        fi
        
        # 2. Heuristic: Terminal Output Activity
        # Capture pane and check for changes since last run? 
        # Simpler: check if any process is running besides the shell/agent?
        # Or just capture and compare with a temp file.
        LAST_OUTPUT_FILE="/tmp/watchdog_$SESSION_NAME.txt"
        tmux capture-pane -t "$SESSION_NAME" -p > "$LAST_OUTPUT_FILE.new"
        
        if [ -f "$LAST_OUTPUT_FILE" ]; then
            if ! diff -q "$LAST_OUTPUT_FILE" "$LAST_OUTPUT_FILE.new" >/dev/null; then
                ANY_ACTIVE=true
                echo "$(date) - Activity detected in $SESSION_NAME (terminal output)" >> "$LOG_FILE"
                jq ".last_output_time = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "$meta" > "$meta.tmp" && mv "$meta.tmp" "$meta"
            fi
        fi
        mv "$LAST_OUTPUT_FILE.new" "$LAST_OUTPUT_FILE"
        
        # 3. Heuristic: File Activity
        RECENT_FILES=$(find "$REPO_PATH" -maxdepth 3 -not -path '*/.*' -mmin -5 2>/dev/null | wc -l)
        if [ "$RECENT_FILES" -gt 0 ]; then
            ANY_ACTIVE=true
            echo "$(date) - Activity detected in $REPO_PATH (file changes)" >> "$LOG_FILE"
            jq ".last_change_time = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "$meta" > "$meta.tmp" && mv "$meta.tmp" "$meta"
        fi
        
        # 4. Check if we should bump Coder
        if [ "$ANY_ACTIVE" = true ]; then
            # Update metadata status
            jq ".status = \"active\"" "$meta" > "$meta.tmp" && mv "$meta.tmp" "$meta"
            
            echo "$(date) - Bumping Coder deadline for $SESSION_NAME" >> "$LOG_FILE"
            coder schedule extend "${AUTOSTOP_BUMP_MINUTES}m" >> "$LOG_FILE" 2>&1
        else
            # Check if it's waiting
            jq ".status = \"waiting\"" "$meta" > "$meta.tmp" && mv "$meta.tmp" "$meta"
        fi
    done
    
    sleep "$WATCHDOG_INTERVAL_SECONDS"
done
