#!/usr/bin/env bash
# cc-context-awareness — Uninstaller
# Removes all installed files and cleans up settings.
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
      echo "By default, uninstalls from ./.claude/ (local install)."
      echo "Use --global to uninstall from ~/.claude/ (global install)."
      echo ""
      echo "Options:"
      echo "  --global    Uninstall from ~/.claude/ instead of locally"
      echo "  -h, --help  Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1 (use --help for usage)"; exit 1 ;;
  esac
done

# ── Set paths based on uninstall mode ─────────────────────────────────────────

if [ "$GLOBAL" = true ]; then
  CLAUDE_DIR="$HOME/.claude"
  INSTALL_DIR="$CLAUDE_DIR/cc-context-awareness"
  SKILL_DIR="$CLAUDE_DIR/skills/configure-context-awareness"
  SETTINGS_FILE="$CLAUDE_DIR/settings.json"
  UNINSTALL_MODE="global"
else
  CLAUDE_DIR="$(pwd)/.claude"
  INSTALL_DIR="$CLAUDE_DIR/cc-context-awareness"
  SKILL_DIR="$CLAUDE_DIR/skills/configure-context-awareness"
  SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
  UNINSTALL_MODE="local"
fi

HOOK_CMD="$INSTALL_DIR/context-awareness-hook.sh"
RESET_CMD="$INSTALL_DIR/context-awareness-reset.sh"
STATUSLINE_CMD="$INSTALL_DIR/context-awareness-statusline.sh"

# All hook events we may have registered under
SUPPORTED_EVENTS="PreToolUse PostToolUse UserPromptSubmit SessionStart"

echo "Uninstalling cc-context-awareness ($UNINSTALL_MODE)..."

# ── Remove installed files ───────────────────────────────────────────────────

if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
  echo "  Removed $INSTALL_DIR"
else
  echo "  $INSTALL_DIR not found (already removed or wrong mode?)"
  echo "  Hint: Use --global if you installed globally, or omit it for local."
fi

if [ -d "$SKILL_DIR" ]; then
  rm -rf "$SKILL_DIR"
  echo "  Removed $SKILL_DIR"
fi

# Clean up empty skills directory if we created it
if [ -d "$CLAUDE_DIR/skills" ]; then
  if [ -z "$(ls -A "$CLAUDE_DIR/skills" 2>/dev/null)" ]; then
    rmdir "$CLAUDE_DIR/skills" 2>/dev/null || true
  fi
fi

# ── Patch settings ───────────────────────────────────────────────────────────

SETTINGS_FILENAME="$(basename "$SETTINGS_FILE")"

if [ -f "$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
  SETTINGS="$(cat "$SETTINGS_FILE")"

  # Remove statusLine if it points to our script
  CURRENT_SL_CMD="$(echo "$SETTINGS" | jq -r '.statusLine.command // ""')"
  if [ "$CURRENT_SL_CMD" = "$STATUSLINE_CMD" ]; then
    SETTINGS="$(echo "$SETTINGS" | jq 'del(.statusLine)')"
    echo "  Removed statusLine from $SETTINGS_FILENAME"
  fi

  # Remove our hook from ALL supported events
  for evt in $SUPPORTED_EVENTS; do
    for cmd in "$HOOK_CMD" "$RESET_CMD"; do
      HAS_EVENT="$(echo "$SETTINGS" | jq --arg evt "$evt" '.hooks[$evt] // null | type == "array"')"

      if [ "$HAS_EVENT" = "true" ]; then
        SETTINGS="$(echo "$SETTINGS" | jq --arg cmd "$cmd" --arg evt "$evt" '
          .hooks[$evt] = [
            .hooks[$evt][] |
            select(.hooks | all(.command != $cmd))
          ]
        ')"

        # If the array is now empty, remove the key
        ARR_LEN="$(echo "$SETTINGS" | jq --arg evt "$evt" '.hooks[$evt] | length')"
        if [ "$ARR_LEN" = "0" ]; then
          SETTINGS="$(echo "$SETTINGS" | jq --arg evt "$evt" 'del(.hooks[$evt])')"
        fi
      fi
    done
  done

  # If hooks object is now empty, remove it too
  HOOKS_EXISTS="$(echo "$SETTINGS" | jq 'has("hooks")')"
  if [ "$HOOKS_EXISTS" = "true" ]; then
    HOOKS_LEN="$(echo "$SETTINGS" | jq '.hooks | length')"
    if [ "$HOOKS_LEN" = "0" ]; then
      SETTINGS="$(echo "$SETTINGS" | jq 'del(.hooks)')"
    fi
  fi

  # If settings is now empty (just {}), remove the file entirely
  SETTINGS_LEN="$(echo "$SETTINGS" | jq 'length')"
  if [ "$SETTINGS_LEN" = "0" ]; then
    rm -f "$SETTINGS_FILE"
    echo "  Removed empty $SETTINGS_FILENAME"
  else
    echo "$SETTINGS" > "$SETTINGS_FILE"
    echo "  Updated $SETTINGS_FILENAME"
  fi
elif [ ! -f "$SETTINGS_FILE" ]; then
  echo "  No $SETTINGS_FILENAME found (nothing to patch)"
else
  echo "  Warning: jq not found, could not patch $SETTINGS_FILENAME"
  echo "  Manually remove the statusLine and hook entries."
fi

# ── Clean up flag files ──────────────────────────────────────────────────────

rm -f /tmp/.cc-ctx-trigger-* /tmp/.cc-ctx-fired-* /tmp/.cc-ctx-compacted-*
echo "  Cleaned up flag files"

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "✓ cc-context-awareness uninstalled successfully ($UNINSTALL_MODE)."
echo "  Restart Claude Code to apply changes."
