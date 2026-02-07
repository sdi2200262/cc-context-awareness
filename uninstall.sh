#!/usr/bin/env bash
# cc-context-awareness — Uninstaller
# Removes all installed files and cleans up settings.json.

set -euo pipefail

INSTALL_DIR="$HOME/.claude/cc-context-awareness"
SKILL_DIR="$HOME/.claude/skills/configure-context-awareness"
SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_CMD="$HOME/.claude/cc-context-awareness/context-awareness-hook.sh"
STATUSLINE_CMD="$HOME/.claude/cc-context-awareness/context-awareness-statusline.sh"

echo "Uninstalling cc-context-awareness..."

# ── Remove installed files ───────────────────────────────────────────────────

if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
  echo "  Removed $INSTALL_DIR"
else
  echo "  $INSTALL_DIR not found (already removed)"
fi

if [ -d "$SKILL_DIR" ]; then
  rm -rf "$SKILL_DIR"
  echo "  Removed $SKILL_DIR"
else
  echo "  $SKILL_DIR not found (already removed)"
fi

# ── Patch settings.json ─────────────────────────────────────────────────────

if [ -f "$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
  SETTINGS="$(cat "$SETTINGS_FILE")"

  # Remove statusLine if it points to our script
  CURRENT_SL_CMD="$(echo "$SETTINGS" | jq -r '.statusLine.command // ""')"
  if [ "$CURRENT_SL_CMD" = "$STATUSLINE_CMD" ]; then
    SETTINGS="$(echo "$SETTINGS" | jq 'del(.statusLine)')"
    echo "  Removed statusLine from settings"
  fi

  # Remove our hook from UserPromptSubmit
  HAS_UPS="$(echo "$SETTINGS" | jq '.hooks.UserPromptSubmit // null | type == "array"')"

  if [ "$HAS_UPS" = "true" ]; then
    SETTINGS="$(echo "$SETTINGS" | jq --arg cmd "$HOOK_CMD" '
      .hooks.UserPromptSubmit = [
        .hooks.UserPromptSubmit[] |
        select(.hooks | all(.command != $cmd))
      ]
    ')"

    # If the array is now empty, remove the key
    UPS_LEN="$(echo "$SETTINGS" | jq '.hooks.UserPromptSubmit | length')"
    if [ "$UPS_LEN" = "0" ]; then
      SETTINGS="$(echo "$SETTINGS" | jq 'del(.hooks.UserPromptSubmit)')"

      # If hooks object is now empty, remove it too
      HOOKS_LEN="$(echo "$SETTINGS" | jq '.hooks | length')"
      if [ "$HOOKS_LEN" = "0" ]; then
        SETTINGS="$(echo "$SETTINGS" | jq 'del(.hooks)')"
      fi
    fi

    echo "  Removed hook from settings"
  fi

  echo "$SETTINGS" > "$SETTINGS_FILE"
  echo "  Updated $SETTINGS_FILE"
elif [ ! -f "$SETTINGS_FILE" ]; then
  echo "  No settings.json found (nothing to patch)"
else
  echo "  Warning: jq not found, could not patch settings.json"
  echo "  Manually remove the statusLine and hook entries."
fi

# ── Clean up flag files ──────────────────────────────────────────────────────

rm -f /tmp/.cc-ctx-trigger-* /tmp/.cc-ctx-fired-*
echo "  Cleaned up flag files"

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "✓ cc-context-awareness uninstalled successfully."
echo "  Restart Claude Code to apply changes."
