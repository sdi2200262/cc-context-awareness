#!/usr/bin/env bash
# cc-context-awareness — PreToolUse hook (threshold evaluator)
# Reads context percentage from the bridge's pct file, evaluates thresholds
# from config.json, and outputs additionalContext when thresholds are crossed.

set -euo pipefail

# Read JSON from stdin and extract session_id
SESSION_ID="$(cat | jq -r '.session_id // empty')"
[[ -z "$SESSION_ID" ]] && exit 0

# Read percentage from bridge's pct file
PCT_FILE="/tmp/.cc-ctx-pct-${SESSION_ID}"
[[ ! -f "$PCT_FILE" ]] && exit 0

USED_PCT="$(cat "$PCT_FILE")"
[[ -z "$USED_PCT" || "$USED_PCT" == "0" ]] && exit 0

REMAINING_PCT=$(( 100 - USED_PCT ))

# Determine config file location (local takes precedence over global)
if [[ -f "./.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="./.claude/cc-context-awareness/config.json"
elif [[ -f "$HOME/.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="$HOME/.claude/cc-context-awareness/config.json"
else
  exit 0
fi

# Parse config values
CONFIG_VALUES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  CONFIG_VALUES+=("$line")
done < <(jq -r '
  (.flag_dir // "/tmp"),
  (.repeat_mode // "once_per_tier_reset_on_compaction"),
  ((.thresholds // []) | @json)
' "$CONFIG_FILE")

FLAG_DIR="${CONFIG_VALUES[0]}"
REPEAT_MODE="${CONFIG_VALUES[1]}"
THRESHOLDS_JSON="${CONFIG_VALUES[2]}"

FIRED_FILE="${FLAG_DIR}/.cc-ctx-fired-${SESSION_ID}"
COMPACTED_FILE="${FLAG_DIR}/.cc-ctx-compacted-${SESSION_ID}"

# If a compaction just happened, reset all state and consume the marker.
if [[ -f "$COMPACTED_FILE" ]]; then
  rm -f "$COMPACTED_FILE" "$FIRED_FILE"
  FIRED='{}'
elif [[ -f "$FIRED_FILE" ]]; then
  FIRED="$(cat "$FIRED_FILE")"
else
  FIRED='{}'
fi

# Process all thresholds in a single jq call
THRESHOLD_RESULT="$(jq -c --argjson used "$USED_PCT" --argjson remaining "$REMAINING_PCT" \
  --argjson fired "$FIRED" --arg repeat_mode "$REPEAT_MODE" --arg session_id "$SESSION_ID" '
  # Sort thresholds by percent
  (. | sort_by(.percent)) as $sorted |

  # Track state
  {
    fired: $fired,
    trigger: null
  } |

  # Process each threshold
  reduce $sorted[] as $t (.;
    if $used >= ($t.percent | tonumber) then
      if (.fired[$t.level] != true) or ($repeat_mode == "every_turn") then
        # Fire this threshold
        .trigger = {
          message: ($t.message | gsub("{percentage}"; ($used | tostring)) | gsub("{remaining}"; ($remaining | tostring)) | gsub("{session_id}"; $session_id))
        } |
        .fired[$t.level] = true
      else
        .
      end
    else
      # Below threshold - reset if needed
      if (.fired[$t.level] == true) and ($repeat_mode != "once_per_tier") then
        .fired |= del(.[$t.level])
      else
        .
      end
    end
  )
' <<< "$THRESHOLDS_JSON")"

# Extract results
read -r NEW_FIRED TRIGGER <<< "$(echo "$THRESHOLD_RESULT" | jq -r '[
  (.fired | @json),
  (.trigger | @json)
] | @tsv')"

# Persist fired-tiers tracking
echo "$NEW_FIRED" > "$FIRED_FILE"

# If a threshold was crossed, output additionalContext directly
if [[ "$TRIGGER" != "null" ]]; then
  MESSAGE="$(echo "$TRIGGER" | jq -r '.message // empty')"
  if [[ -n "$MESSAGE" ]]; then
    jq -n --arg msg "$MESSAGE" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": $msg
      }
    }'
  fi
fi
