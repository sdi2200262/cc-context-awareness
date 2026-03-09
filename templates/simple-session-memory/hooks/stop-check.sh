#!/usr/bin/env bash
# simple-session-memory — Stop hook
# Ensures a session memory log is written before Claude stops.
# If no log exists for the current session (identified by session_id in frontmatter),
# blocks Claude from stopping and asks it to write one.
# Uses stop_hook_active to prevent infinite loops.
#
# Directory convention: .claude/memory/session-YYYY-MM-DD-NNN/session-YYYY-MM-DD-NNN.md
#   - NNN is a per-day counter derived from existing directories
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

# ── Helper: find log for this session via frontmatter grep ───────────────────
find_session_log() {
  local dirs
  dirs="$(ls -d "$MEMORY_DIR"/session-*/ 2>/dev/null || true)"
  [[ -z "$dirs" ]] && return
  grep -rl "session_id: ${SESSION_ID}" $dirs 2>/dev/null \
    | head -1 || true
}

# ── Helper: reserve the next counter and return the target path ──────────────
next_log_path() {
  local today highest dir_name current_nnn next padded stem
  today="$(date +%Y-%m-%d)"
  highest="$(ls -d "$MEMORY_DIR"/session-${today}-*/ 2>/dev/null | sort | tail -1 || true)"
  if [[ -n "$highest" ]]; then
    dir_name="$(basename "$highest")"
    current_nnn="${dir_name##*-}"
    next=$(( 10#$current_nnn + 1 ))
  else
    next=1
  fi
  padded="$(printf "%03d" "$next")"
  stem="session-${today}-${padded}"
  mkdir -p "${MEMORY_DIR}/${stem}"
  echo "${MEMORY_DIR}/${stem}/${stem}.md"
}

# ── Helper: flag for archival if 5+ session directories exist ────────────────
check_archival() {
  local count
  count="$( (ls -d "$MEMORY_DIR"/session-*/ 2>/dev/null || true) | wc -l)"
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
