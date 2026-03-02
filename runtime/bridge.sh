#!/usr/bin/env bash
# cc-context-awareness — StatusLine bridge
# Extracts context window percentage, writes it to a session-scoped file.
# Passes the original JSON through to stdout only when piped to a downstream
# statusLine tool. When standalone, suppresses output to keep the status line clean.

set -euo pipefail

INPUT="$(cat)"
if SID_PCT="$(echo "$INPUT" | jq -r '[.session_id // "", .context_window.used_percentage // 0] | @tsv' 2>/dev/null)"; then
  read -r SID PCT <<< "$SID_PCT"
  [[ -n "$SID" ]] && echo "$PCT" > "/tmp/.cc-ctx-pct-${SID}"
fi
# Only pass through to stdout if piped to a downstream tool
[ -p /dev/stdout ] && echo "$INPUT"
