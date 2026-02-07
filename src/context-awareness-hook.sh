#!/usr/bin/env bash
# cc-context-awareness — Hook actuator
# Reads trigger flag file and outputs additionalContext for Claude Code.

set -euo pipefail

CONFIG_FILE="$HOME/.claude/cc-context-awareness/config.json"

# Read JSON from stdin
INPUT="$(cat)"

# Extract session_id
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"

if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Load config to get flag_dir
if [ -f "$CONFIG_FILE" ]; then
  FLAG_DIR="$(jq -r '.flag_dir // "/tmp"' "$CONFIG_FILE")"
else
  FLAG_DIR="/tmp"
fi

TRIGGER_FILE="${FLAG_DIR}/.cc-ctx-trigger-${SESSION_ID}"

# Check for trigger flag
if [ ! -f "$TRIGGER_FILE" ]; then
  exit 0
fi

# Read trigger data
TRIGGER="$(cat "$TRIGGER_FILE")"
MESSAGE="$(echo "$TRIGGER" | jq -r '.message // empty')"

if [ -z "$MESSAGE" ]; then
  rm -f "$TRIGGER_FILE"
  exit 0
fi

# Output additionalContext for Claude Code
jq -n --arg msg "$MESSAGE" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $msg
  }
}'

# Remove trigger flag so it doesn't fire again
rm -f "$TRIGGER_FILE"
