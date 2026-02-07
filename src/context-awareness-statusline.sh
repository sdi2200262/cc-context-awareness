#!/usr/bin/env bash
# cc-context-awareness — Status line sensor
# Reads context window data from stdin, manages threshold flags, renders status bar.

set -euo pipefail

CONFIG_FILE="$HOME/.claude/cc-context-awareness/config.json"

# Read JSON from stdin
INPUT="$(cat)"

# Extract fields
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
USED_PCT="$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0')"
REMAINING_PCT="$(echo "$INPUT" | jq -r '.context_window.remaining_percentage // 100')"

if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Load config (fall back to defaults if missing)
if [ -f "$CONFIG_FILE" ]; then
  CONFIG="$(cat "$CONFIG_FILE")"
else
  CONFIG='{}'
fi

FLAG_DIR="$(echo "$CONFIG" | jq -r '.flag_dir // "/tmp"')"
BAR_WIDTH="$(echo "$CONFIG" | jq -r '.statusline.bar_width // 20')"
BAR_FILLED="$(echo "$CONFIG" | jq -r '.statusline.bar_filled // "█"')"
BAR_EMPTY="$(echo "$CONFIG" | jq -r '.statusline.bar_empty // "░"')"
FORMAT="$(echo "$CONFIG" | jq -r '.statusline.format // "context {bar} {percentage}%"')"
COLOR_NORMAL="$(echo "$CONFIG" | jq -r '.statusline.color_normal // "37"')"
COLOR_WARNING="$(echo "$CONFIG" | jq -r '.statusline.color_warning // "31"')"
WARNING_INDICATOR="$(echo "$CONFIG" | jq -r '.statusline.warning_indicator // " ⚠"')"
REPEAT_MODE="$(echo "$CONFIG" | jq -r '.repeat_mode // "once_per_tier_reset_on_compaction"')"

FIRED_FILE="${FLAG_DIR}/.cc-ctx-fired-${SESSION_ID}"
TRIGGER_FILE="${FLAG_DIR}/.cc-ctx-trigger-${SESSION_ID}"

# Load fired-tiers tracking
if [ -f "$FIRED_FILE" ]; then
  FIRED="$(cat "$FIRED_FILE")"
else
  FIRED='{}'
fi

# Track whether any threshold is currently exceeded
ANY_EXCEEDED=false

# Process thresholds (sorted by percent ascending)
THRESHOLDS="$(echo "$CONFIG" | jq -c '.thresholds // [] | sort_by(.percent) | .[]')"

while IFS= read -r threshold; do
  [ -z "$threshold" ] && continue

  T_PCT="$(echo "$threshold" | jq -r '.percent')"
  T_LEVEL="$(echo "$threshold" | jq -r '.level')"
  T_MSG="$(echo "$threshold" | jq -r '.message')"

  if [ "$USED_PCT" -ge "$T_PCT" ] 2>/dev/null; then
    ANY_EXCEEDED=true

    ALREADY_FIRED="$(echo "$FIRED" | jq -r --arg lvl "$T_LEVEL" '.[$lvl] // false')"

    if [ "$ALREADY_FIRED" != "true" ] || [ "$REPEAT_MODE" = "every_turn" ]; then
      # Substitute placeholders in message
      MSG="$(echo "$T_MSG" | sed "s/{percentage}/${USED_PCT}/g" | sed "s/{remaining}/${REMAINING_PCT}/g")"

      # Write trigger flag
      jq -n \
        --argjson pct "$USED_PCT" \
        --argjson rem "$REMAINING_PCT" \
        --arg level "$T_LEVEL" \
        --arg message "$MSG" \
        '{"percentage": $pct, "remaining": $rem, "level": $level, "message": $message}' \
        > "$TRIGGER_FILE"

      # Mark tier as fired
      FIRED="$(echo "$FIRED" | jq --arg lvl "$T_LEVEL" '. + {($lvl): true}')"
    fi
  else
    # Usage dropped below threshold — reset tier (compaction reset)
    ALREADY_FIRED="$(echo "$FIRED" | jq -r --arg lvl "$T_LEVEL" '.[$lvl] // false')"
    if [ "$ALREADY_FIRED" = "true" ] && [ "$REPEAT_MODE" != "once_per_tier" ]; then
      FIRED="$(echo "$FIRED" | jq --arg lvl "$T_LEVEL" 'del(.[$lvl])')"
    fi
  fi
done <<< "$THRESHOLDS"

# Persist fired-tiers tracking
echo "$FIRED" > "$FIRED_FILE"

# Render status bar
FILLED_COUNT=$(( USED_PCT * BAR_WIDTH / 100 ))
EMPTY_COUNT=$(( BAR_WIDTH - FILLED_COUNT ))

BAR=""
for (( i=0; i<FILLED_COUNT; i++ )); do
  BAR="${BAR}${BAR_FILLED}"
done
for (( i=0; i<EMPTY_COUNT; i++ )); do
  BAR="${BAR}${BAR_EMPTY}"
done

# Build output from format string
OUTPUT="$FORMAT"
OUTPUT="${OUTPUT//\{bar\}/$BAR}"
OUTPUT="${OUTPUT//\{percentage\}/$USED_PCT}"

# Append warning indicator if any threshold exceeded
if [ "$ANY_EXCEEDED" = true ]; then
  OUTPUT="${OUTPUT}${WARNING_INDICATOR}"
  COLOR="$COLOR_WARNING"
else
  COLOR="$COLOR_NORMAL"
fi

# Print with ANSI color
printf '\033[%sm%s\033[0m' "$COLOR" "$OUTPUT"
