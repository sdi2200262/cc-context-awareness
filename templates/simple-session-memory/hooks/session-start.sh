#!/usr/bin/env bash
# simple-session-memory — SessionStart hook (matcher: "compact")
# After compaction, finds the most recent session memory log and injects
# it as additionalContext so Claude can restore context from the previous session.
# Falls back to the most recent archive if no session directories exist.
#
# Session directories are named session-YYYY-MM-DD-NNN/ with the log file
# session-YYYY-MM-DD-NNN.md inside. Lexicographic sort = chronological order.
#
# Hook event: SessionStart (matcher: "compact")

set -euo pipefail

INPUT="$(cat)"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
[[ -z "$SESSION_ID" ]] && exit 0

MEMORY_DIR=".claude/memory"
[[ ! -d "$MEMORY_DIR" ]] && exit 0

# Find the most recent session directory (lexicographic sort — date+counter guarantees order)
LATEST_DIR="$(ls -d "$MEMORY_DIR"/session-*/ 2>/dev/null | sort | tail -1 || true)"

if [[ -n "$LATEST_DIR" ]]; then
  DIR_NAME="$(basename "$LATEST_DIR")"
  LATEST_LOG="${LATEST_DIR}${DIR_NAME}.md"

  if [[ -f "$LATEST_LOG" ]]; then
    LOG_CONTENT="$(cat "$LATEST_LOG")"
    jq -n \
      --arg content "$LOG_CONTENT" \
      --arg name "$DIR_NAME" '{
        "hookSpecificOutput": {
          "hookEventName": "SessionStart",
          "additionalContext": ("SESSION MEMORY RESTORED AFTER COMPACTION\n\nThe following memory log has been loaded. Read it and continue from where work left off.\n\nSession: " + $name + "\n\n" + $content + "\n\n---\nCOMPACTION RULES:\n1. Compaction resets the context window. Always create a new session directory and log in .claude/memory/ — even if this log has the same session_id as your current session.\n2. Add  continues: " + $name + "  to the new log'\''s YAML frontmatter to link it to this pre-compaction session.\n3. Update .claude/memory/index.md with the new session entry.")
        }
      }'
    exit 0
  fi
fi

# No session directory with a valid log — fall back to most recent archive
LATEST_ARCHIVE="$(ls -t "$MEMORY_DIR/archive"/archive-*.md 2>/dev/null | head -1 || true)"

if [[ -n "$LATEST_ARCHIVE" ]]; then
  ARCHIVE_CONTENT="$(cat "$LATEST_ARCHIVE")"
  ARCHIVE_NAME="$(basename "$LATEST_ARCHIVE")"
  jq -n \
    --arg content "$ARCHIVE_CONTENT" \
    --arg name "$ARCHIVE_NAME" '{
      "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ("SESSION MEMORY RESTORED AFTER COMPACTION\n\nNo recent session log was found. Loading the most recent archive (covers multiple prior sessions).\n\nArchive: " + $name + "\n\n" + $content + "\n\n---\nCOMPACTION RULES:\n1. Create a new session directory and log in .claude/memory/.\n2. Update .claude/memory/index.md with the new session entry.")
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
