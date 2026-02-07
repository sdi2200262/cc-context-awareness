#!/usr/bin/env bash
# cc-context-awareness — Installer
# Works both from a cloned repo and via curl pipe.

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/cobuterman/cc-context-awareness/main"
INSTALL_DIR="$HOME/.claude/cc-context-awareness"
SKILL_DIR="$HOME/.claude/skills/configure-context-awareness"
SETTINGS_FILE="$HOME/.claude/settings.json"

OVERWRITE=false
NO_SKILL=false

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --overwrite) OVERWRITE=true ;;
    --no-skill) NO_SKILL=true ;;
    -h|--help)
      echo "Usage: install.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --overwrite    Replace existing statusLine config in settings.json"
      echo "  --no-skill     Skip the agent skill; install a standalone configuration guide instead"
      echo "  -h, --help     Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $arg (use --help for usage)"; exit 1 ;;
  esac
done

# ── Dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed."
  echo ""
  echo "Install it:"
  echo "  macOS:  brew install jq"
  echo "  Ubuntu: sudo apt-get install jq"
  echo "  Other:  https://jqlang.github.io/jq/download/"
  exit 1
fi

# ── Detect source mode ───────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if [ -d "$SCRIPT_DIR/src" ] && [ -f "$SCRIPT_DIR/src/context-awareness-statusline.sh" ]; then
  MODE="local"
else
  MODE="remote"
fi

# ── Helper: get source file ──────────────────────────────────────────────────

get_file() {
  local rel_path="$1"
  local dest="$2"

  if [ "$MODE" = "local" ]; then
    cp "$SCRIPT_DIR/$rel_path" "$dest"
  else
    if ! curl -fsSL "${REPO_URL}/${rel_path}" -o "$dest" 2>/dev/null; then
      echo "  Error: Failed to download $rel_path"
      echo "  Check your internet connection or try installing from a cloned repo."
      exit 1
    fi
  fi
}

# ── Install files ────────────────────────────────────────────────────────────

echo "Installing cc-context-awareness..."

# Create install directory (fail gracefully if we can't)
if ! mkdir -p "$INSTALL_DIR" 2>/dev/null; then
  echo "Error: Cannot create $INSTALL_DIR"
  echo "Check that ~/.claude/ exists and is writable."
  exit 1
fi

get_file "src/context-awareness-statusline.sh" "$INSTALL_DIR/context-awareness-statusline.sh"
get_file "src/context-awareness-hook.sh" "$INSTALL_DIR/context-awareness-hook.sh"

# Only copy default config if config.json doesn't already exist (preserve user customizations)
if [ ! -f "$INSTALL_DIR/config.json" ]; then
  get_file "src/config.default.json" "$INSTALL_DIR/config.json"
  echo "  Created default config.json"
else
  echo "  Existing config.json preserved (not overwritten)"
fi

chmod +x "$INSTALL_DIR/context-awareness-statusline.sh"
chmod +x "$INSTALL_DIR/context-awareness-hook.sh"

echo "  Installed scripts to $INSTALL_DIR"

# ── Skill or configuration guide ─────────────────────────────────────────────

if [ "$NO_SKILL" = true ]; then
  get_file "docs/configuration-guide.md" "$INSTALL_DIR/configuration-guide.md"
  echo "  Installed configuration guide to $INSTALL_DIR"
  echo "  Skipped agent skill (--no-skill)"
else
  mkdir -p "$SKILL_DIR"
  get_file "docs/SKILL.md" "$SKILL_DIR/SKILL.md"
  echo "  Installed agent skill to $SKILL_DIR"
fi

# ── Patch settings.json ─────────────────────────────────────────────────────

STATUSLINE_CMD="$HOME/.claude/cc-context-awareness/context-awareness-statusline.sh"
HOOK_CMD="$HOME/.claude/cc-context-awareness/context-awareness-hook.sh"

STATUSLINE_VALUE="$(jq -n --arg cmd "$STATUSLINE_CMD" '{"type": "command", "command": $cmd}')"
HOOK_ENTRY="$(jq -n --arg cmd "$HOOK_CMD" '{"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}')"

if [ ! -f "$SETTINGS_FILE" ]; then
  # Create settings.json from scratch
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  jq -n \
    --argjson sl "$STATUSLINE_VALUE" \
    --argjson hook "$HOOK_ENTRY" \
    '{
      "statusLine": $sl,
      "hooks": {
        "UserPromptSubmit": [$hook]
      }
    }' > "$SETTINGS_FILE"
  echo "  Created $SETTINGS_FILE"
else
  # Patch existing settings.json
  SETTINGS="$(cat "$SETTINGS_FILE")"

  # Validate it's valid JSON before proceeding
  if ! echo "$SETTINGS" | jq empty 2>/dev/null; then
    echo "  Error: $SETTINGS_FILE contains invalid JSON."
    echo "  Fix the file manually, then re-run the installer."
    echo "  Scripts were installed but settings.json was not patched."
    exit 1
  fi

  # Handle statusLine
  HAS_STATUSLINE="$(echo "$SETTINGS" | jq 'has("statusLine")')"

  if [ "$HAS_STATUSLINE" = "true" ]; then
    EXISTING_CMD="$(echo "$SETTINGS" | jq -r '.statusLine.command // ""')"

    if [ "$EXISTING_CMD" = "$STATUSLINE_CMD" ]; then
      echo "  statusLine already configured for cc-context-awareness"
    elif [ "$OVERWRITE" = true ]; then
      SETTINGS="$(echo "$SETTINGS" | jq --argjson sl "$STATUSLINE_VALUE" '.statusLine = $sl')"
      echo "  Replaced existing statusLine config (--overwrite)"
    else
      echo ""
      echo "  ╭─ statusLine conflict ──────────────────────────────────────╮"
      echo "  │ Another tool is using the statusLine:                      │"
      echo "  │   $EXISTING_CMD"
      echo "  │                                                            │"
      echo "  │ Claude Code only supports one statusLine command.          │"
      echo "  │ Re-run with --overwrite to replace it, or merge manually.  │"
      echo "  ╰────────────────────────────────────────────────────────────╯"
      echo ""
      echo "  Continuing without statusLine (hook will still be installed)."
    fi
  else
    SETTINGS="$(echo "$SETTINGS" | jq --argjson sl "$STATUSLINE_VALUE" '. + {statusLine: $sl}')"
    echo "  Added statusLine config"
  fi

  # Handle hooks.UserPromptSubmit
  HAS_HOOKS_KEY="$(echo "$SETTINGS" | jq 'has("hooks")')"

  if [ "$HAS_HOOKS_KEY" = "true" ]; then
    HAS_UPS="$(echo "$SETTINGS" | jq '.hooks | has("UserPromptSubmit")')"

    if [ "$HAS_UPS" = "true" ]; then
      # Check if our hook is already present
      ALREADY_HAS="$(echo "$SETTINGS" | jq --arg cmd "$HOOK_CMD" '
        .hooks.UserPromptSubmit // [] |
        any(
          .hooks[]? | .command == $cmd
        )
      ')"

      if [ "$ALREADY_HAS" = "true" ]; then
        echo "  Hook already registered"
      else
        SETTINGS="$(echo "$SETTINGS" | jq --argjson hook "$HOOK_ENTRY" '
          .hooks.UserPromptSubmit += [$hook]
        ')"
        echo "  Appended hook to existing UserPromptSubmit hooks (existing hooks preserved)"
      fi
    else
      SETTINGS="$(echo "$SETTINGS" | jq --argjson hook "$HOOK_ENTRY" '
        .hooks.UserPromptSubmit = [$hook]
      ')"
      echo "  Added UserPromptSubmit hook"
    fi
  else
    SETTINGS="$(echo "$SETTINGS" | jq --argjson hook "$HOOK_ENTRY" '
      . + {hooks: {UserPromptSubmit: [$hook]}}
    ')"
    echo "  Added hooks config"
  fi

  echo "$SETTINGS" > "$SETTINGS_FILE"
  echo "  Updated $SETTINGS_FILE"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "✓ cc-context-awareness installed successfully!"
echo ""
echo "  Status bar:  Shows context usage in Claude Code's status line"
echo "  Warnings:    Automatically injected when context reaches 80%"
echo "  Config:      $INSTALL_DIR/config.json"
if [ "$NO_SKILL" = true ]; then
  echo "  Guide:       $INSTALL_DIR/configuration-guide.md"
else
  echo "  Skill:       Ask Claude to 'configure context awareness'"
fi
echo ""
echo "  Restart Claude Code to activate."
