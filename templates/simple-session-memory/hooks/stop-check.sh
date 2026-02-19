#!/usr/bin/env bash
# simple-session-memory — Stop hook
# Ensures a session memory log is written before Claude stops.
# If no log exists for the current session (identified by session_id in frontmatter),
# blocks Claude from stopping and asks it to write one with a counter-based filename.
# Uses stop_hook_active to prevent infinite loops.
#
# Filename convention: .claude/memory/session-YYYY-MM-DD-NNN.md
#   - NNN is a global counter stored in .claude/memory/.session-count
#   - session_id is in YAML frontmatter, not the filename
#
# Hook event: Stop

set -euo pipefail

INPUT="$(cat)"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
[[ -z "$SESSION_ID" ]] && exit 0

STOP_HOOK_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // false')"

MEMORY_DIR=".claude/memory"
mkdir -p "$MEMORY_DIR"

COUNTER_FILE="$MEMORY_DIR/.session-count"

# ── Helper: find log for this session via frontmatter grep ───────────────────
find_session_log() {
  grep -rl "session_id: ${SESSION_ID}" "$MEMORY_DIR" 2>/dev/null \
    | grep -E "session-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+\.md$" \
    | head -1 || true
}

# ── Helper: reserve the next counter and return the target path ──────────────
next_log_path() {
  local current next padded today
  current="$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)"
  next=$(( current + 1 ))
  padded="$(printf "%03d" "$next")"
  today="$(date +%Y-%m-%d)"
  echo "$next" > "$COUNTER_FILE"
  echo "${MEMORY_DIR}/session-${today}-${padded}.md"
}

# ── Helper: flag for archival if 5+ session logs exist ──────────────────────
check_archival() {
  local count
  count="$(ls -1 "$MEMORY_DIR"/session-*.md 2>/dev/null | wc -l)"
  count="${count// /}"
  [[ "$count" -ge 5 ]] && touch "$MEMORY_DIR/.archive-needed" || true
}

# ── If Claude is continuing after a prior stop hook block, let it stop ────────
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  check_archival
  exit 0
fi

# ── Check if a memory log already exists for this session ────────────────────
EXISTING_LOG="$(find_session_log)"

if [[ -n "$EXISTING_LOG" ]]; then
  check_archival
  exit 0
fi

# ── No memory log — reserve a counter slot and block ─────────────────────────
TARGET="$(next_log_path)"
TODAY="$(date +%Y-%m-%d)"

jq -n --arg path "$TARGET" --arg session_id "$SESSION_ID" --arg date "$TODAY" '{
  "decision": "block",
  "reason": ("Before stopping, write a session memory log to: " + $path + "\n\nThe file MUST start with this YAML frontmatter (copy exactly):\n---\ndate: " + $date + "\nsession_id: " + $session_id + "\ncontext_at_log: <current context %>\n---\n\nThen include these sections:\n\n## Current Work\nWhat task or project you are working on and its current state.\n\n## Completed This Session\nWhat was accomplished — specific files changed, features added, bugs fixed.\n\n## Key Decisions\nImportant technical or design choices made, and why.\n\n## Files Modified\nKey files created or changed with brief descriptions.\n\n## In Progress\nAnything started but not yet finished.\n\n## Next Steps\nExactly what to do next session — specific enough to continue immediately without re-reading the codebase.\n\n## Notes\nUser preferences, known issues, environment details, or other context.\n\nUse the Write tool to create this file, then stop.")
}'
