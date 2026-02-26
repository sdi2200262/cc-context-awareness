#!/usr/bin/env bash
# simple-session-memory — Archival check hook (SessionStart, matcher: "compact")
# Counts session logs in pure bash. If >= 5 accumulate, injects an instruction
# into the session context telling Claude to delegate to the memory-archiver agent.
# The custom agent does the actual condensation — no bash string concatenation.
#
# Hook event: SessionStart (matcher: "compact")
# Runs AFTER session-start.sh so session context is loaded first.

set -euo pipefail

MEMORY_DIR=".claude/memory"

[[ ! -d "$MEMORY_DIR" ]] && exit 0

# Collect session logs sorted newest-first (Bash 3.2+ compatible).
# The glob is non-recursive — only matches files directly in .claude/memory/,
# never in .claude/memory/archive/. The regex further ensures only
# session-YYYY-MM-DD-NNN.md filenames are counted, excluding archive-*.md.
LOGS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && LOGS+=("$line")
done < <(ls -t "$MEMORY_DIR"/session-*.md 2>/dev/null \
  | grep -E "session-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+\.md$" \
  || true)

COUNT="${#LOGS[@]}"

# Nothing to do
[[ "$COUNT" -lt 5 ]] && exit 0

# Newest log is preserved; everything else needs archiving
TO_ARCHIVE=("${LOGS[@]:1}")
ARCHIVE_COUNT="${#TO_ARCHIVE[@]}"

# Build file list for the instruction
FILES_LIST=""
for f in "${TO_ARCHIVE[@]}"; do
  FILES_LIST="${FILES_LIST}  - .claude/memory/$(basename "$f")
"
done

TODAY="$(date +%Y-%m-%d)"
ARCHIVE_TARGET=".claude/memory/archive/archive-${TODAY}.md"

jq -n \
  --arg files "$FILES_LIST" \
  --arg n "$ARCHIVE_COUNT" \
  --arg target "$ARCHIVE_TARGET" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": ("SESSION MEMORY ARCHIVAL NEEDED\n\n" + $n + " session logs have accumulated. Before proceeding with any other work, delegate to the memory-archiver agent to archive them.\n\nFiles to archive:\n" + $files + "\nArchive target: " + $target + "\n\nThe newest session log is NOT in this list and must NOT be deleted.")
    }
  }'
