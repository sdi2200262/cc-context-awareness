#!/usr/bin/env bash
# simple-session-memory — PreToolUse hook for Write|Edit
# Outputs permissionDecision:"allow" for .claude/memory/ paths,
# bypassing the permission system. This is critical for background
# subagents (like memory-archiver) which auto-deny unapproved tools.
# For all other paths, exits 0 with no output (falls through to
# the normal permission check).

set -euo pipefail

INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

case "$FP" in
  .claude/memory/*|*/.claude/memory/*)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "Session memory system: .claude/memory/ write approved"
      }
    }'
    ;;
  *)
    # No decision — fall through to normal permission check
    exit 0
    ;;
esac
