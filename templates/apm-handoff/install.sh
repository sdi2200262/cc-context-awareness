#!/usr/bin/env bash
# apm-handoff — Installer
# Adds an automatic Handoff threshold and a SessionStart detection hook
# to cc-context-awareness for APM agents.
#
# Defaults to local install (project .claude/). Use --global for ~/.claude/.

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/templates/apm-handoff"

# Defaults
GLOBAL=false
NO_CLAUDE_MD=false

# Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    --global) GLOBAL=true; shift ;;
    --no-claude-md) NO_CLAUDE_MD=true; shift ;;
    -h|--help)
      echo "Usage: install.sh [OPTIONS]"
      echo ""
      echo "Installs the apm-handoff template."
      echo "cc-context-awareness is installed automatically if not already present."
      echo ""
      echo "Options:"
      echo "  --global         Install globally to ~/.claude/ instead of locally"
      echo "  --no-claude-md   Skip appending instructions to CLAUDE.md"
      echo "  -h, --help       Show this help"
      echo ""
      echo "Requirements:"
      echo "  - jq"
      exit 0
      ;;
    *) echo "Unknown option: $1 (use --help for usage)"; exit 1 ;;
  esac
done

# ── Dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed."
  echo "  macOS:  brew install jq"
  echo "  Ubuntu: sudo apt-get install jq"
  exit 1
fi

# ── Set paths based on install mode ──────────────────────────────────────────

if [ "$GLOBAL" = true ]; then
  CLAUDE_DIR="$HOME/.claude"
  INSTALL_MODE="global"
else
  CLAUDE_DIR="$(pwd)/.claude"
  INSTALL_MODE="local"
fi

CC_CONTEXT_DIR="$CLAUDE_DIR/cc-context-awareness"
HOOKS_DIR="$CLAUDE_DIR/apm-handoff/hooks"
CONFIG_FILE="$CC_CONTEXT_DIR/config.json"

if [ "$GLOBAL" = true ]; then
  SETTINGS_FILE="$CLAUDE_DIR/settings.json"
else
  SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
fi

# ── Detect script location ──────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# ── Ensure cc-context-awareness is installed ─────────────────────────────────

MAIN_INSTALL_SCRIPT="$SCRIPT_DIR/../../install.sh"
MAIN_INSTALL_URL="https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/install.sh"

if [ ! -f "$CC_CONTEXT_DIR/config.json" ]; then
  echo "cc-context-awareness not found - installing it automatically..."
  echo ""

  if [ -f "$MAIN_INSTALL_SCRIPT" ]; then
    if [ "$GLOBAL" = true ]; then
      "$MAIN_INSTALL_SCRIPT" --global
    else
      "$MAIN_INSTALL_SCRIPT"
    fi
  else
    if [ "$GLOBAL" = true ]; then
      curl -fsSL "$MAIN_INSTALL_URL" | bash -s -- --global
    else
      curl -fsSL "$MAIN_INSTALL_URL" | bash
    fi
  fi

  echo ""

  if [ ! -f "$CC_CONTEXT_DIR/config.json" ]; then
    echo "Error: cc-context-awareness installation failed. Install it manually and re-run:"
    if [ "$GLOBAL" = true ]; then
      echo "  curl -fsSL $MAIN_INSTALL_URL | bash -s -- --global"
    else
      echo "  curl -fsSL $MAIN_INSTALL_URL | bash"
    fi
    exit 1
  fi
fi

# ── Detect source mode ───────────────────────────────────────────────────────

if [ -d "$SCRIPT_DIR/hooks" ] && [ -f "$SCRIPT_DIR/hooks/detect-apm-handoff.sh" ]; then
  SOURCE_MODE="local"
else
  SOURCE_MODE="remote"
fi

get_file() {
  local rel_path="$1"
  local dest="$2"
  if [ "$SOURCE_MODE" = "local" ]; then
    cp "$SCRIPT_DIR/$rel_path" "$dest"
  else
    if ! curl -fsSL "${REPO_URL}/${rel_path}" -o "$dest" 2>/dev/null; then
      echo "  Error: Failed to download $rel_path"
      exit 1
    fi
  fi
}

# ── Install hook script ─────────────────────────────────────────────────────

echo "Installing apm-handoff ($INSTALL_MODE)..."

mkdir -p "$HOOKS_DIR"

get_file "hooks/detect-apm-handoff.sh" "$HOOKS_DIR/detect-apm-handoff.sh"
chmod +x "$HOOKS_DIR/detect-apm-handoff.sh"

echo "  Installed hook to $HOOKS_DIR"

# ── Patch cc-context-awareness config with Handoff threshold ─────────────────

THRESHOLDS_TMP=""
cleanup_thresholds_tmp() {
  if [ -n "$THRESHOLDS_TMP" ] && [ -f "$THRESHOLDS_TMP" ]; then
    rm -f "$THRESHOLDS_TMP"
  fi
}
trap cleanup_thresholds_tmp EXIT

THRESHOLDS_FILE="$SCRIPT_DIR/cc-context-awareness.thresholds.json"
if [ ! -f "$THRESHOLDS_FILE" ] && [ "$SOURCE_MODE" = "remote" ]; then
  THRESHOLDS_TMP="$(mktemp /tmp/apm-handoff-thresholds.XXXXXX.json)"
  if ! curl -fsSL "${REPO_URL}/cc-context-awareness.thresholds.json" -o "$THRESHOLDS_TMP"; then
    echo "  Error: Failed to download thresholds configuration from GitHub"
    echo "  Check your network connection and try again"
    exit 1
  fi
  THRESHOLDS_FILE="$THRESHOLDS_TMP"
fi

if [ ! -f "$THRESHOLDS_FILE" ]; then
  echo "  Error: Thresholds configuration is required but unavailable"
  exit 1
fi

if ! NEW_THRESHOLDS="$(jq -c . "$THRESHOLDS_FILE" 2>/dev/null)"; then
  echo "  Error: Thresholds configuration is invalid JSON"
  exit 1
fi

if ! echo "$NEW_THRESHOLDS" | jq -e 'type == "array" and length > 0 and all(.[]; has("level"))' >/dev/null 2>&1; then
  echo "  Error: Thresholds configuration format is invalid"
  exit 1
fi

CURRENT_CONFIG="$(cat "$CONFIG_FILE")"
UPDATED_CONFIG="$(echo "$CURRENT_CONFIG" | jq --argjson new "$NEW_THRESHOLDS" '
  ($new | map(.level)) as $new_levels
  | .thresholds = (
      $new
      + ((.thresholds // [])
          | map(select((.level // "") as $lvl | ($new_levels | index($lvl) | not))))
    )
')"

CURRENT_NORMALIZED="$(echo "$CURRENT_CONFIG" | jq -cS .)"
UPDATED_NORMALIZED="$(echo "$UPDATED_CONFIG" | jq -cS .)"

if [ "$CURRENT_NORMALIZED" != "$UPDATED_NORMALIZED" ]; then
  echo "$UPDATED_CONFIG" > "$CONFIG_FILE"
  echo "  Patched cc-context-awareness config: upserted Handoff threshold at 70%"
else
  echo "  cc-context-awareness config: Handoff threshold already up to date"
fi

# ── Patch settings.json with SessionStart hook ──────────────────────────────

DETECT_CMD="$HOOKS_DIR/detect-apm-handoff.sh"

DETECT_ENTRY="$(jq -n --arg cmd "$DETECT_CMD" \
  '{"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}')"

SETTINGS_FILENAME="$(basename "$SETTINGS_FILE")"

if [ ! -f "$SETTINGS_FILE" ]; then
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  jq -n \
    --argjson detect "$DETECT_ENTRY" \
    '{
      "hooks": {
        "SessionStart": [$detect]
      }
    }' > "$SETTINGS_FILE"
  echo "  Created $SETTINGS_FILENAME with Handoff detection hook"
else
  SETTINGS="$(cat "$SETTINGS_FILE")"

  if ! echo "$SETTINGS" | jq empty 2>/dev/null; then
    echo "  Error: $SETTINGS_FILE contains invalid JSON. Fix it and re-run."
    exit 1
  fi

  # Helper: check if a command is already in a hook array
  has_command() {
    local settings="$1" event="$2" cmd="$3"
    echo "$settings" | jq --arg evt "$event" --arg cmd "$cmd" \
      '(.hooks[$evt] // []) | any(.hooks[]?.command == $cmd)' 2>/dev/null || echo "false"
  }

  # Helper: append an entry to a hook event array
  append_hook() {
    local settings="$1" event="$2" entry="$3"
    local has_event
    has_event="$(echo "$settings" | jq --arg evt "$event" 'has("hooks") and (.hooks | has($evt))')"
    if [ "$has_event" = "true" ]; then
      echo "$settings" | jq --argjson e "$entry" --arg evt "$event" '.hooks[$evt] += [$e]'
    else
      echo "$settings" | jq --argjson e "$entry" --arg evt "$event" \
        'if has("hooks") then .hooks[$evt] = [$e] else . + {"hooks": {($evt): [$e]}} end'
    fi
  }

  # SessionStart (detect-apm-handoff.sh)
  if [ "$(has_command "$SETTINGS" "SessionStart" "$DETECT_CMD")" != "true" ]; then
    SETTINGS="$(append_hook "$SETTINGS" "SessionStart" "$DETECT_ENTRY")"
    echo "  Added SessionStart hook (Handoff detection)"
  else
    echo "  SessionStart Handoff detection hook already registered (skipped)"
  fi

  echo "$SETTINGS" > "$SETTINGS_FILE"
  echo "  Updated $SETTINGS_FILENAME"
fi

# ── Optionally append to CLAUDE.md ───────────────────────────────────────────

if [ "$NO_CLAUDE_MD" = false ]; then
  CLAUDE_MD="$(pwd)/CLAUDE.md"
  SNIPPET_FILE="$SCRIPT_DIR/CLAUDE.snippet.md"

  if [ ! -f "$SNIPPET_FILE" ] && [ "$SOURCE_MODE" = "remote" ]; then
    SNIPPET_FILE="/tmp/apm-handoff-claude-snippet.md"
    curl -fsSL "${REPO_URL}/CLAUDE.snippet.md" -o "$SNIPPET_FILE" 2>/dev/null || true
  fi

  if [ -f "$SNIPPET_FILE" ]; then
    if [ -f "$CLAUDE_MD" ]; then
      if grep -q "APM Automatic Handoff" "$CLAUDE_MD" 2>/dev/null; then
        echo "  CLAUDE.md: APM Handoff instructions already present (skipped)"
      else
        echo "" >> "$CLAUDE_MD"
        echo "---" >> "$CLAUDE_MD"
        echo "" >> "$CLAUDE_MD"
        cat "$SNIPPET_FILE" >> "$CLAUDE_MD"
        echo "  Appended APM Handoff instructions to CLAUDE.md"
      fi
    else
      cp "$SNIPPET_FILE" "$CLAUDE_MD"
      echo "  Created CLAUDE.md with APM Handoff instructions"
    fi
  fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "✓ apm-handoff installed ($INSTALL_MODE)!"
echo ""
echo "  Hook:     $HOOKS_DIR/detect-apm-handoff.sh"
echo "  Config:   $CONFIG_FILE (Handoff threshold added)"
echo "  Settings: $SETTINGS_FILE"
echo ""
echo "  How it works:"
echo "    70% context  → agent automatically triggers Handoff procedure"
echo "    New session  → hook detects pending Handoff, signals incoming agent"
echo ""
echo "  Customize the threshold by editing the \"apm-handoff\" entry in:"
echo "    $CONFIG_FILE"
echo ""
echo "  Restart Claude Code to activate."
echo ""
