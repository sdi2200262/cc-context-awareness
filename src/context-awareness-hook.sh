#!/usr/bin/env bash
# cc-context-awareness — Hook actuator
# Reads trigger flag file and outputs additionalContext for Claude Code.
# Designed to be fast in the common case (no trigger file present).

set -euo pipefail

CONFIG_FILE="$HOME/.claude/cc-context-awareness/config.json"

# Read JSON from stdin
INPUT="$(cat)"

# Extract session_id
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"

if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Load config: flag_dir and hook_event in a single jq call
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_VALUES="$(jq -r '[.flag_dir // "/tmp", .hook_event // "PreToolUse"] | @tsv' "$CONFIG_FILE")"
  IFS=$'\t' read -r FLAG_DIR HOOK_EVENT <<< "$CONFIG_VALUES"
else
  FLAG_DIR="/tmp"
  HOOK_EVENT="PreToolUse"
fi

TRIGGER_FILE="${FLAG_DIR}/.cc-ctx-trigger-${SESSION_ID}"

# Fast path: no trigger file, exit immediately
if [ ! -f "$TRIGGER_FILE" ]; then
  exit 0
fi

# Trigger file exists — read it and inject context
TRIGGER="$(cat "$TRIGGER_FILE")"
MESSAGE="$(echo "$TRIGGER" | jq -r '.message // empty')"

if [ -z "$MESSAGE" ]; then
  rm -f "$TRIGGER_FILE"
  exit 0
fi

# Output additionalContext for Claude Code
jq -n --arg msg "$MESSAGE" --arg evt "$HOOK_EVENT" '{
  "hookSpecificOutput": {
    "hookEventName": $evt,
    "additionalContext": $msg
  }
}'

# Remove trigger flag so it doesn't fire again
rm -f "$TRIGGER_FILE"
