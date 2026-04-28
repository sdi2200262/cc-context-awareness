#!/usr/bin/env bash
# simple-session-memory — Archival check hook (SessionStart, matcher: "compact")
# Counts session directories in .claude/memory/. If >= 5 accumulate, injects an
# instruction into the session context telling Claude to delegate to the
# memory-archiver agent. The custom agent does the actual condensation.
#
# Hook event: SessionStart (matcher: "compact")
# Runs AFTER session-start.sh so session context is loaded first.

set -euo pipefail

MEMORY_DIR=".claude/memory"

[[ ! -d "$MEMORY_DIR" ]] && exit 0

# Collect session directories sorted newest-first (lexicographic reverse).
# The glob is non-recursive — only matches directories directly in .claude/memory/.
DIRS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DIRS+=("$line")
done < <(ls -d "$MEMORY_DIR"/session-*/ 2>/dev/null | sort -r || true)

COUNT="${#DIRS[@]}"

# Nothing to do
[[ "$COUNT" -lt 5 ]] && exit 0

# Newest session is preserved; everything else needs archiving
TO_ARCHIVE=("${DIRS[@]:1}")
ARCHIVE_COUNT="${#TO_ARCHIVE[@]}"

# Build file list (log paths inside directories) for the archiver to read
FILES_LIST=""
for d in "${TO_ARCHIVE[@]}"; do
  NAME="$(basename "$d")"
  FILES_LIST="${FILES_LIST}  - .claude/memory/${NAME}/${NAME}.md
"
done

# Build directory list for the deletion manifest
DIRS_LIST=""
for d in "${TO_ARCHIVE[@]}"; do
  NAME="$(basename "$d")"
  DIRS_LIST="${DIRS_LIST}  - .claude/memory/${NAME}/
"
done

TODAY="$(date +%Y-%m-%d)"
ARCHIVE_NAME="archive-${TODAY}"

jq -n \
  --arg files "$FILES_LIST" \
  --arg dirs "$DIRS_LIST" \
  --arg n "$ARCHIVE_COUNT" \
  --arg name "$ARCHIVE_NAME" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": ("SESSION MEMORY ARCHIVAL NEEDED\n\n" + $n + " session directories have accumulated. Before proceeding with any other work, delegate to the memory-archiver agent to archive them.\n\nSession logs to archive (read these):\n" + $files + "\nAlso check each session directory for supplementary files and read those too.\n\nArchive name: " + $name + "  (the agent will create .claude/memory/archives/" + $name + "/ containing " + $name + ".md and any supplementary attachments worth preserving)\n\nThe newest session directory is NOT in this list and must NOT be deleted.\n\nIMPORTANT — After the memory-archiver agent returns:\n1. Read the deletion manifest in its final message (the ```deletion-manifest``` fenced block).\n2. Delete each directory listed under delete_directories using: rm -r .claude/memory/<session-name>/\n3. Use relative paths. Delete one directory per command.\nThe archiver does NOT delete anything itself — you must handle all deletions here.")
    }
  }'
