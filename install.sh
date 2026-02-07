#!/usr/bin/env bash
# cc-context-awareness — Installer
# Works both from a cloned repo and via curl pipe.
# Defaults to local (per-project) install; use --global for system-wide.

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main"

# Defaults
GLOBAL=false
OVERWRITE=false
NO_SKILL=false
HOOK_EVENT=""

# Supported hook events for validation
SUPPORTED_EVENTS="PreToolUse PostToolUse UserPromptSubmit"

# Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    --global) GLOBAL=true; shift ;;
    --overwrite) OVERWRITE=true; shift ;;
    --no-skill) NO_SKILL=true; shift ;;
    --hook-event)
      if [ -z "${2:-}" ]; then
        echo "Error: --hook-event requires a value"
        echo "Supported: $SUPPORTED_EVENTS"
        exit 1
      fi
      HOOK_EVENT="$2"
      # Validate
      if ! echo "$SUPPORTED_EVENTS" | grep -qw "$HOOK_EVENT"; then
        echo "Error: Unsupported hook event '$HOOK_EVENT'"
        echo "Supported: $SUPPORTED_EVENTS"
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      echo "Usage: install.sh [OPTIONS]"
      echo ""
      echo "By default, installs locally to ./.claude/ (per-project config)."
      echo "Use --global to install to ~/.claude/ (system-wide config)."
      echo ""
      echo "Options:"
      echo "  --global               Install globally to ~/.claude/ instead of locally"
      echo "  --overwrite            Replace existing statusLine config in settings"
      echo "  --no-skill             Skip the agent skill; install a standalone configuration guide instead"
      echo "  --hook-event <event>   Hook event to use for context injection (default: PreToolUse)"
      echo "                         Supported: PreToolUse, PostToolUse, UserPromptSubmit"
      echo "  -h, --help             Show this help"
      echo ""
      echo "Examples:"
      echo "  ./install.sh                     # Local install (this project only)"
      echo "  ./install.sh --global            # Global install (all projects)"
      echo "  ./install.sh --hook-event PostToolUse"
      echo ""
      echo "Hook events:"
      echo "  PreToolUse         Fires before every tool call inside the agentic loop (default)"
      echo "  PostToolUse        Fires after every tool call inside the agentic loop"
      echo "  UserPromptSubmit   Fires once per user prompt (no mid-loop coverage)"
      exit 0
      ;;
    *) echo "Unknown option: $1 (use --help for usage)"; exit 1 ;;
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

# ── Set paths based on install mode ───────────────────────────────────────────

if [ "$GLOBAL" = true ]; then
  CLAUDE_DIR="$HOME/.claude"
  INSTALL_DIR="$CLAUDE_DIR/cc-context-awareness"
  SKILL_DIR="$CLAUDE_DIR/skills/configure-context-awareness"
  SETTINGS_FILE="$CLAUDE_DIR/settings.json"
  INSTALL_MODE="global"
else
  CLAUDE_DIR="$(pwd)/.claude"
  INSTALL_DIR="$CLAUDE_DIR/cc-context-awareness"
  SKILL_DIR="$CLAUDE_DIR/skills/configure-context-awareness"
  SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
  INSTALL_MODE="local"
fi

# ── Detect source mode ───────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if [ -d "$SCRIPT_DIR/src" ] && [ -f "$SCRIPT_DIR/src/context-awareness-statusline.sh" ]; then
  SOURCE_MODE="local"
else
  SOURCE_MODE="remote"
fi

# ── Helper: get source file ──────────────────────────────────────────────────

get_file() {
  local rel_path="$1"
  local dest="$2"

  if [ "$SOURCE_MODE" = "local" ]; then
    cp "$SCRIPT_DIR/$rel_path" "$dest"
  else
    if ! curl -fsSL "${REPO_URL}/${rel_path}" -o "$dest" 2>/dev/null; then
      echo "  Error: Failed to download $rel_path"
      echo "  Check your internet connection or try installing from a cloned repo."
      exit 1
    fi
  fi
}

# ── Resolve hook event ───────────────────────────────────────────────────────

# Priority: --hook-event flag > existing config.json > default (PreToolUse)
if [ -z "$HOOK_EVENT" ]; then
  if [ -f "$INSTALL_DIR/config.json" ]; then
    HOOK_EVENT="$(jq -r '.hook_event // "PreToolUse"' "$INSTALL_DIR/config.json")"
  else
    HOOK_EVENT="PreToolUse"
  fi
fi

# ── Install files ────────────────────────────────────────────────────────────

echo "Installing cc-context-awareness ($INSTALL_MODE)..."

# Create install directory (fail gracefully if we can't)
if ! mkdir -p "$INSTALL_DIR" 2>/dev/null; then
  echo "Error: Cannot create $INSTALL_DIR"
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

# Update hook_event in config.json to match selected event
CURRENT_EVENT="$(jq -r '.hook_event // ""' "$INSTALL_DIR/config.json")"
if [ "$CURRENT_EVENT" != "$HOOK_EVENT" ]; then
  TMP_CONFIG="$(jq --arg evt "$HOOK_EVENT" '.hook_event = $evt' "$INSTALL_DIR/config.json")"
  echo "$TMP_CONFIG" > "$INSTALL_DIR/config.json"
  echo "  Set hook_event to $HOOK_EVENT in config.json"
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

# ── Patch settings ───────────────────────────────────────────────────────────

# Use absolute paths for scripts so they work regardless of cwd
STATUSLINE_CMD="$INSTALL_DIR/context-awareness-statusline.sh"
HOOK_CMD="$INSTALL_DIR/context-awareness-hook.sh"

STATUSLINE_VALUE="$(jq -n --arg cmd "$STATUSLINE_CMD" '{"type": "command", "command": $cmd}')"
HOOK_ENTRY="$(jq -n --arg cmd "$HOOK_CMD" '{"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}')"

# Helper: remove our hook from a given event array in settings
remove_our_hook() {
  local event="$1"
  local settings="$2"

  local has_event
  has_event="$(echo "$settings" | jq --arg evt "$event" '.hooks[$evt] // null | type == "array"')"

  if [ "$has_event" = "true" ]; then
    settings="$(echo "$settings" | jq --arg cmd "$HOOK_CMD" --arg evt "$event" '
      .hooks[$evt] = [
        .hooks[$evt][] |
        select(.hooks | all(.command != $cmd))
      ]
    ')"

    # Clean up empty arrays
    local arr_len
    arr_len="$(echo "$settings" | jq --arg evt "$event" '.hooks[$evt] | length')"
    if [ "$arr_len" = "0" ]; then
      settings="$(echo "$settings" | jq --arg evt "$event" 'del(.hooks[$evt])')"
    fi
  fi

  echo "$settings"
}

SETTINGS_FILENAME="$(basename "$SETTINGS_FILE")"

if [ ! -f "$SETTINGS_FILE" ]; then
  # Create settings file from scratch
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  jq -n \
    --argjson sl "$STATUSLINE_VALUE" \
    --argjson hook "$HOOK_ENTRY" \
    --arg evt "$HOOK_EVENT" \
    '{
      "statusLine": $sl,
      "hooks": {
        ($evt): [$hook]
      }
    }' > "$SETTINGS_FILE"
  echo "  Created $SETTINGS_FILENAME (hook event: $HOOK_EVENT)"
else
  # Patch existing settings file
  SETTINGS="$(cat "$SETTINGS_FILE")"

  # Validate it's valid JSON before proceeding
  if ! echo "$SETTINGS" | jq empty 2>/dev/null; then
    echo "  Error: $SETTINGS_FILE contains invalid JSON."
    echo "  Fix the file manually, then re-run the installer."
    echo "  Scripts were installed but $SETTINGS_FILENAME was not patched."
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
      echo "  ╰────────────────────────────────────────────────────────────╯"
      echo ""
      echo "  cc-context-awareness needs to run alongside your statusLine to write"
      echo "  the flag file that the hook reads. You have two options:"
      echo ""
      echo "  Option 1: Wrap your existing statusLine"
      echo "    Create a wrapper script that calls both. Example:"
      echo "      #!/usr/bin/env bash"
      echo "      INPUT=\$(cat)"
      echo "      echo \"\$INPUT\" | /path/to/your/statusline.sh"
      echo "      echo \"\$INPUT\" | $STATUSLINE_CMD"
      echo ""
      echo "  Option 2: Merge the flag logic into your script"
      echo "    Copy the threshold/flag-writing logic from our statusline script"
      echo "    into yours. The key part writes to: /tmp/.cc-ctx-trigger-{session_id}"
      echo ""
      echo "  Option 3: Replace with --overwrite (loses your customizations)"
      echo "      ./install.sh --overwrite"
      echo ""
      echo "  See: https://github.com/sdi2200262/cc-context-awareness#merging-with-other-statusline-tools"
      echo ""
      echo "  Scripts were installed to $INSTALL_DIR but $SETTINGS_FILENAME was not modified."
      exit 1
    fi
  else
    SETTINGS="$(echo "$SETTINGS" | jq --argjson sl "$STATUSLINE_VALUE" '. + {statusLine: $sl}')"
    echo "  Added statusLine config"
  fi

  # Remove our hook from ALL supported events first (handles event switching)
  for evt in $SUPPORTED_EVENTS; do
    SETTINGS="$(remove_our_hook "$evt" "$SETTINGS")"
  done

  # Clean up empty hooks object if needed
  HOOKS_EXISTS="$(echo "$SETTINGS" | jq 'has("hooks")')"
  if [ "$HOOKS_EXISTS" = "true" ]; then
    HOOKS_LEN="$(echo "$SETTINGS" | jq '.hooks | length')"
    if [ "$HOOKS_LEN" = "0" ]; then
      SETTINGS="$(echo "$SETTINGS" | jq 'del(.hooks)')"
    fi
  fi

  # Add our hook to the selected event
  HAS_HOOKS_KEY="$(echo "$SETTINGS" | jq 'has("hooks")')"

  if [ "$HAS_HOOKS_KEY" = "true" ]; then
    HAS_EVENT="$(echo "$SETTINGS" | jq --arg evt "$HOOK_EVENT" '.hooks | has($evt)')"

    if [ "$HAS_EVENT" = "true" ]; then
      SETTINGS="$(echo "$SETTINGS" | jq --argjson hook "$HOOK_ENTRY" --arg evt "$HOOK_EVENT" '
        .hooks[$evt] += [$hook]
      ')"
      echo "  Added hook to $HOOK_EVENT (existing hooks preserved)"
    else
      SETTINGS="$(echo "$SETTINGS" | jq --argjson hook "$HOOK_ENTRY" --arg evt "$HOOK_EVENT" '
        .hooks[$evt] = [$hook]
      ')"
      echo "  Added $HOOK_EVENT hook"
    fi
  else
    SETTINGS="$(echo "$SETTINGS" | jq --argjson hook "$HOOK_ENTRY" --arg evt "$HOOK_EVENT" '
      . + {hooks: {($evt): [$hook]}}
    ')"
    echo "  Added hooks config ($HOOK_EVENT)"
  fi

  echo "$SETTINGS" > "$SETTINGS_FILE"
  echo "  Updated $SETTINGS_FILENAME"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "✓ cc-context-awareness installed successfully ($INSTALL_MODE)!"
echo ""
echo "  Install:     $INSTALL_MODE"
echo "  Config:      $INSTALL_DIR/config.json"
echo "  Settings:    $SETTINGS_FILE"
echo "  Hook event:  $HOOK_EVENT"
if [ "$NO_SKILL" = true ]; then
  echo "  Guide:       $INSTALL_DIR/configuration-guide.md"
else
  echo "  Skill:       Ask Claude to 'configure context awareness'"
fi
echo ""
if [ "$INSTALL_MODE" = "local" ]; then
  echo "  This install applies only to this project directory."
  echo "  Use --global to install system-wide for all projects."
  echo ""
fi
echo "  Restart Claude Code to activate."
echo ""
echo "  To change hook event: ./install.sh --hook-event <event>"
echo "  Supported: $SUPPORTED_EVENTS"
