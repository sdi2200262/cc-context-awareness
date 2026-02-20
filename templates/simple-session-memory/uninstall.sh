#!/usr/bin/env bash
# simple-session-memory — Uninstaller
# Removes hooks, cleans up settings, and removes memory thresholds from
# cc-context-awareness config. Memory logs are preserved.
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
      echo "Uninstalls simple-session-memory hooks and config patches."
      echo "Memory logs in .claude/memory/ are NOT deleted."
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

HOOKS_DIR="$CLAUDE_DIR/simple-session-memory/hooks"
CC_CONTEXT_DIR="$CLAUDE_DIR/cc-context-awareness"
CONFIG_FILE="$CC_CONTEXT_DIR/config.json"

SESSION_START_CMD="$HOOKS_DIR/session-start.sh"
ARCHIVAL_CMD="$HOOKS_DIR/archival.sh"

echo "Uninstalling simple-session-memory ($UNINSTALL_MODE)..."

# ── Remove installed hook scripts ─────────────────────────────────────────────

if [ -d "$HOOKS_DIR" ]; then
  rm -rf "$HOOKS_DIR"
  echo "  Removed $HOOKS_DIR"
else
  echo "  $HOOKS_DIR not found (already removed or wrong mode?)"
fi

# Remove parent dir if empty
PARENT_DIR="$CLAUDE_DIR/simple-session-memory"
if [ -d "$PARENT_DIR" ] && [ -z "$(ls -A "$PARENT_DIR" 2>/dev/null)" ]; then
  rmdir "$PARENT_DIR" 2>/dev/null || true
fi

# ── Remove memory thresholds from cc-context-awareness config ─────────────────

if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
  MEMORY_LEVELS=("memory-50" "memory-65" "memory-80")
  CURRENT_CONFIG="$(cat "$CONFIG_FILE")"
  HAS_MEMORY=false
  for level in "${MEMORY_LEVELS[@]}"; do
    if echo "$CURRENT_CONFIG" | jq -r '.thresholds[].level' 2>/dev/null | grep -q "^${level}$"; then
      HAS_MEMORY=true
      break
    fi
  done

  if [ "$HAS_MEMORY" = true ]; then
    UPDATED_CONFIG="$(echo "$CURRENT_CONFIG" | jq '
      .thresholds = [.thresholds[] | select(.level | test("^memory-") | not)]
    ')"
    echo "$UPDATED_CONFIG" > "$CONFIG_FILE"
    echo "  Removed memory thresholds from cc-context-awareness config"
  else
    echo "  No memory thresholds found in cc-context-awareness config (skipped)"
  fi
elif [ ! -f "$CONFIG_FILE" ]; then
  echo "  cc-context-awareness config not found (skipped threshold cleanup)"
else
  echo "  Warning: jq not found — could not clean up cc-context-awareness config"
  echo "  Manually remove the memory-50, memory-65, memory-80 threshold entries."
fi

# ── Remove hooks from settings ────────────────────────────────────────────────

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
    echo "  Warning: $SETTINGS_FILE contains invalid JSON — skipping settings cleanup"
  else
    SETTINGS="$(remove_cmd_from_settings "$SETTINGS" "$SESSION_START_CMD")"
    SETTINGS="$(remove_cmd_from_settings "$SETTINGS" "$ARCHIVAL_CMD")"

    SETTINGS_LEN="$(echo "$SETTINGS" | jq 'length')"
    if [ "$SETTINGS_LEN" = "0" ]; then
      rm -f "$SETTINGS_FILE"
      echo "  Removed empty $SETTINGS_FILENAME"
    else
      echo "$SETTINGS" > "$SETTINGS_FILE"
      echo "  Updated $SETTINGS_FILENAME (removed simple-session-memory hooks)"
    fi
  fi
elif [ ! -f "$SETTINGS_FILE" ]; then
  echo "  No $SETTINGS_FILENAME found (nothing to patch)"
else
  echo "  Warning: jq not found — could not patch $SETTINGS_FILENAME"
  echo "  Manually remove the session-start.sh and archival.sh hook entries."
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "✓ simple-session-memory uninstalled ($UNINSTALL_MODE)."
echo ""
echo "  Memory logs preserved at: $CLAUDE_DIR/memory/"
echo "  Restart Claude Code to apply changes."
echo ""
