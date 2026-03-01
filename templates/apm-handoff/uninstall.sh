#!/usr/bin/env bash
# apm-handoff — Uninstaller
# Removes the Handoff threshold from cc-context-awareness config,
# the detection hook, and its settings.json entry.
#
# Defaults to local uninstall; use --global for system-wide.

set -euo pipefail

# Defaults
GLOBAL=false

# Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    --global) GLOBAL=true; shift ;;
    -h|--help)
      echo "Usage: uninstall.sh [OPTIONS]"
      echo ""
      echo "Uninstalls the apm-handoff threshold, hook, and settings entries."
      echo ""
      echo "Options:"
      echo "  --global    Uninstall from ~/.claude/ instead of locally"
      echo "  -h, --help  Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1 (use --help for usage)"; exit 1 ;;
  esac
done

# ── Set paths based on uninstall mode ────────────────────────────────────────

if [ "$GLOBAL" = true ]; then
  CLAUDE_DIR="$HOME/.claude"
  SETTINGS_FILE="$CLAUDE_DIR/settings.json"
  UNINSTALL_MODE="global"
else
  CLAUDE_DIR="$(pwd)/.claude"
  SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
  UNINSTALL_MODE="local"
fi

HOOKS_DIR="$CLAUDE_DIR/apm-handoff/hooks"
CC_CONTEXT_DIR="$CLAUDE_DIR/cc-context-awareness"
CONFIG_FILE="$CC_CONTEXT_DIR/config.json"

DETECT_CMD="$HOOKS_DIR/detect-apm-handoff.sh"

echo "Uninstalling apm-handoff ($UNINSTALL_MODE)..."

# ── Remove installed hook script ─────────────────────────────────────────────

if [ -d "$HOOKS_DIR" ]; then
  rm -rf "$HOOKS_DIR"
  echo "  Removed $HOOKS_DIR"
else
  echo "  $HOOKS_DIR not found (already removed or wrong mode?)"
fi

# Remove parent dir if empty
PARENT_DIR="$CLAUDE_DIR/apm-handoff"
if [ -d "$PARENT_DIR" ] && [ -z "$(ls -A "$PARENT_DIR" 2>/dev/null)" ]; then
  rmdir "$PARENT_DIR" 2>/dev/null || true
fi

# ── Remove Handoff threshold from cc-context-awareness config ────────────────

if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
  CURRENT_CONFIG="$(cat "$CONFIG_FILE")"
  HAS_APM=false
  if echo "$CURRENT_CONFIG" | jq -r '.thresholds[].level' 2>/dev/null | grep -q "^apm-handoff"; then
    HAS_APM=true
  fi

  if [ "$HAS_APM" = true ]; then
    UPDATED_CONFIG="$(echo "$CURRENT_CONFIG" | jq '
      .thresholds = [.thresholds[] | select(.level | test("^apm-handoff") | not)]
    ')"
    echo "$UPDATED_CONFIG" > "$CONFIG_FILE"
    echo "  Removed Handoff threshold from cc-context-awareness config"
  else
    echo "  No Handoff threshold found in cc-context-awareness config (skipped)"
  fi
elif [ ! -f "$CONFIG_FILE" ]; then
  echo "  cc-context-awareness config not found (skipped threshold cleanup)"
else
  echo "  Warning: jq not found - could not clean up cc-context-awareness config"
  echo "  Manually remove the \"apm-handoff\" threshold entry from:"
  echo "    $CONFIG_FILE"
fi

# ── Remove hook from settings ────────────────────────────────────────────────

SETTINGS_FILENAME="$(basename "$SETTINGS_FILE")"

remove_cmd_from_settings() {
  local settings="$1" cmd="$2"
  echo "$settings" | jq --arg cmd "$cmd" '
    if has("hooks") then
      .hooks = (.hooks | to_entries | map(
        .value = [.value[] | select(.hooks | all(.command != $cmd))]
      ) | map(select(.value | length > 0)) | from_entries)
    else . end |
    if has("hooks") and (.hooks | length == 0) then del(.hooks) else . end
  '
}

if [ -f "$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
  SETTINGS="$(cat "$SETTINGS_FILE")"

  if ! echo "$SETTINGS" | jq empty 2>/dev/null; then
    echo "  Warning: $SETTINGS_FILE contains invalid JSON - skipping settings cleanup"
  else
    SETTINGS="$(remove_cmd_from_settings "$SETTINGS" "$DETECT_CMD")"

    SETTINGS_LEN="$(echo "$SETTINGS" | jq 'length')"
    if [ "$SETTINGS_LEN" = "0" ]; then
      rm -f "$SETTINGS_FILE"
      echo "  Removed empty $SETTINGS_FILENAME"
    else
      echo "$SETTINGS" > "$SETTINGS_FILE"
      echo "  Updated $SETTINGS_FILENAME (removed apm-handoff hook)"
    fi
  fi
elif [ ! -f "$SETTINGS_FILE" ]; then
  echo "  No $SETTINGS_FILENAME found (nothing to patch)"
else
  echo "  Warning: jq not found - could not patch $SETTINGS_FILENAME"
  echo "  Manually remove the detect-apm-handoff.sh hook entry."
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "✓ apm-handoff uninstalled ($UNINSTALL_MODE)."
echo ""
echo "  If you appended APM Handoff instructions to CLAUDE.md, remove them manually."
echo "  Restart Claude Code to apply changes."
echo ""
