#!/usr/bin/env bash
# apm-handoff — SessionStart hook
# Scans APM Handoff Bus files for pending handoff prompts and injects
# a deterministic signal as additionalContext so the incoming agent knows
# a Handoff is waiting before it processes any commands.
#
# Hook event: SessionStart (matcher: "")

set -euo pipefail

# Consume stdin (required by hook protocol)
cat > /dev/null

BUS_DIR=".apm/bus"
[[ ! -d "$BUS_DIR" ]] && exit 0

# Scan all apm-handoff.md files for non-empty content
PENDING=""
for handoff_file in "$BUS_DIR"/*/apm-handoff.md; do
  [[ ! -f "$handoff_file" ]] && continue
  [[ ! -s "$handoff_file" ]] && continue

  # Extract agent directory name (e.g. "manager", "python-agent")
  agent_dir="$(basename "$(dirname "$handoff_file")")"
  if [ -z "$PENDING" ]; then
    PENDING="$agent_dir ($handoff_file)"
  else
    PENDING="$PENDING\n$agent_dir ($handoff_file)"
  fi
done

# No pending handoffs — exit silently
[[ -z "$PENDING" ]] && exit 0

# Build the additionalContext message
MESSAGE="APM HANDOFF DETECTED\n\nPending Handoff prompts found:\n$(echo -e "$PENDING" | sed 's/^/- /')\n\nIf you are being initiated as one of the agents listed above, you are an incoming agent replacing an outgoing agent that performed a Handoff. Your initiation command contains the procedure for processing the Handoff Bus and rebuilding context."

jq -n --arg msg "$(echo -e "$MESSAGE")" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $msg
  }
}'
