#!/usr/bin/env bash
# cc-context-awareness — Compaction reset handler
# Clears stale flag files after /compact or auto-compaction.
# Registered as a SessionStart hook (matcher: "compact").

set -euo pipefail

# Read JSON from stdin and extract session_id
SESSION_ID="$(cat | jq -r '.session_id // empty')"

[[ -z "$SESSION_ID" ]] && exit 0

# Determine config file location (local takes precedence over global)
if [[ -f "./.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="./.claude/cc-context-awareness/config.json"
elif [[ -f "$HOME/.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="$HOME/.claude/cc-context-awareness/config.json"
else
  CONFIG_FILE=""
fi

# Load flag_dir from config
if [[ -n "$CONFIG_FILE" ]]; then
  FLAG_DIR="$(jq -r '.flag_dir // "/tmp"' "$CONFIG_FILE")"
else
  FLAG_DIR="/tmp"
fi

# Remove stale flag files for this session
rm -f "${FLAG_DIR}/.cc-ctx-trigger-${SESSION_ID}"
rm -f "${FLAG_DIR}/.cc-ctx-fired-${SESSION_ID}"

# Plant compaction marker so the statusline knows to skip stale writes.
# Without this, a late-running statusline (from the last pre-compaction message)
# can re-create the trigger file with stale percentage data after we've cleaned up.
touch "${FLAG_DIR}/.cc-ctx-compacted-${SESSION_ID}"
