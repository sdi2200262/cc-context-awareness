#!/usr/bin/env bash
# simple-session-memory — SessionStart hook (matcher: "compact")
# After compaction, finds the most recent session memory log and injects
# it as additionalContext so Claude can restore context from the previous session.
# Falls back to the most recent archive if no individual session logs exist.
#
# Hook event: SessionStart (matcher: "compact")

set -euo pipefail

INPUT="$(cat)"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
[[ -z "$SESSION_ID" ]] && exit 0

MEMORY_DIR=".claude/memory"
[[ ! -d "$MEMORY_DIR" ]] && exit 0

# Find the most recent session log (by modification time)
LATEST_LOG="$(ls -t "$MEMORY_DIR"/session-*.md 2>/dev/null \
  | grep -E "session-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+\.md$" \
  | head -1 || true)"

if [[ -n "$LATEST_LOG" ]]; then
  LOG_CONTENT="$(cat "$LATEST_LOG")"
  LOG_NAME="$(basename "$LATEST_LOG")"
  jq -n \
    --arg content "$LOG_CONTENT" \
    --arg name "$LOG_NAME" '{
      "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ("SESSION MEMORY RESTORED AFTER COMPACTION\n\nThe previous session was auto-compacted. The following memory log has been loaded — read it and continue from where work left off.\n\nMemory log: " + $name + "\n\n" + $content + "\n\n---\nIMPORTANT: The session_id in the frontmatter belongs to the previous session. Your current session has a new session_id. If you need to write memory updates, create a new log using the counter in .claude/memory/.session-count.")
      }
    }'
  exit 0
fi

# No session log — fall back to most recent archive
LATEST_ARCHIVE="$(ls -t "$MEMORY_DIR/archive"/archive-*.md 2>/dev/null | head -1 || true)"

if [[ -n "$LATEST_ARCHIVE" ]]; then
  ARCHIVE_CONTENT="$(cat "$LATEST_ARCHIVE")"
  ARCHIVE_NAME="$(basename "$LATEST_ARCHIVE")"
  jq -n \
    --arg content "$ARCHIVE_CONTENT" \
    --arg name "$ARCHIVE_NAME" '{
      "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ("SESSION MEMORY RESTORED AFTER COMPACTION\n\nNo recent session log was found. Loading the most recent session archive (covers multiple prior sessions).\n\nArchive: " + $name + "\n\n" + $content + "\n\n---\nIMPORTANT: This archive covers multiple prior sessions. Your current session has a new session_id. Create a new session log using the counter in .claude/memory/.session-count.")
      }
    }'
  exit 0
fi

# Nothing found
jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Session resumed after compaction. No prior session memory found. Start fresh."
  }
}'
