#!/bin/bash
# agent-status.sh: Show status of agent sessions

printf "%-25s %-10s %-25s %-10s %-15s %-15s\n" "SESSION" "AGENT" "REPO" "STATE" "LAST_OUTPUT" "LAST_CHANGE"

for meta in "$HOME/.local/share/agent-sessions/"*.json; do
    [ -e "$meta" ] || continue
    
    NAME=$(jq -r '.name' "$meta")
    AGENT=$(jq -r '.agent_type' "$meta")
    REPO=$(jq -r '.repo_path' "$meta" | sed "s|$HOME|~|")
    STATE=$(jq -r '.status' "$meta")
    
    LAST_OUT=$(jq -r '.last_output_time // "never"' "$meta")
    LAST_CHG=$(jq -r '.last_change_time // "never"' "$meta")
    
    # Simple relative time if not "never"
    if [ "$LAST_OUT" != "never" ]; then
        LAST_OUT="$(date -d "$LAST_OUT" +"%H:%M:%S")"
    fi
    if [ "$LAST_CHG" != "never" ]; then
        LAST_CHG="$(date -d "$LAST_CHG" +"%H:%M:%S")"
    fi

    printf "%-25s %-10s %-25s %-10s %-15s %-15s\n" "$NAME" "$AGENT" "$REPO" "$STATE" "$LAST_OUT" "$LAST_CHG"
done
