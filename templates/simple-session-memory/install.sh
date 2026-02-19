#!/usr/bin/env bash
# simple-session-memory — Installer
# Installs the session memory system hooks and patches cc-context-awareness
# config and Claude Code settings.json.
#
# Defaults to local install (project .claude/). Use --global for ~/.claude/.

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/templates/simple-session-memory"

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
      echo "Installs the simple-session-memory template for cc-context-awareness."
      echo ""
      echo "Options:"
      echo "  --global         Install globally to ~/.claude/ instead of locally"
      echo "  --no-claude-md   Skip appending instructions to CLAUDE.md"
      echo "  -h, --help       Show this help"
      echo ""
      echo "Requirements:"
      echo "  - cc-context-awareness must already be installed"
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
HOOKS_DIR="$CLAUDE_DIR/simple-session-memory/hooks"
CONFIG_FILE="$CC_CONTEXT_DIR/config.json"

if [ "$GLOBAL" = true ]; then
  SETTINGS_FILE="$CLAUDE_DIR/settings.json"
else
  SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
fi

# ── Verify cc-context-awareness is installed ─────────────────────────────────

if [ ! -f "$CC_CONTEXT_DIR/config.json" ]; then
  echo "Error: cc-context-awareness not found at $CC_CONTEXT_DIR"
  echo ""
  echo "Install cc-context-awareness first:"
  if [ "$GLOBAL" = true ]; then
    echo "  curl -fsSL https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/install.sh | bash -s -- --global"
  else
    echo "  curl -fsSL https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/install.sh | bash"
  fi
  exit 1
fi

# ── Detect source mode ───────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if [ -d "$SCRIPT_DIR/hooks" ] && [ -f "$SCRIPT_DIR/hooks/stop-check.sh" ]; then
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

# ── Install hook scripts ──────────────────────────────────────────────────────

echo "Installing simple-session-memory ($INSTALL_MODE)..."

mkdir -p "$HOOKS_DIR"

get_file "hooks/session-start.sh" "$HOOKS_DIR/session-start.sh"
get_file "hooks/stop-check.sh"    "$HOOKS_DIR/stop-check.sh"

chmod +x "$HOOKS_DIR/session-start.sh"
chmod +x "$HOOKS_DIR/stop-check.sh"

echo "  Installed hooks to $HOOKS_DIR"

# ── Patch cc-context-awareness config with memory thresholds ─────────────────

THRESHOLDS_FILE="$SCRIPT_DIR/cc-context-awareness.thresholds.json"
if [ ! -f "$THRESHOLDS_FILE" ] && [ "$SOURCE_MODE" = "remote" ]; then
  THRESHOLDS_FILE="/tmp/simple-session-memory-thresholds.json"
  curl -fsSL "${REPO_URL}/cc-context-awareness.thresholds.json" -o "$THRESHOLDS_FILE" 2>/dev/null
fi

if [ -f "$THRESHOLDS_FILE" ]; then
  # Memory threshold levels to check for (avoid duplicate patching)
  MEMORY_LEVELS=("memory-50" "memory-65" "memory-80")

  CURRENT_CONFIG="$(cat "$CONFIG_FILE")"

  # Check if any memory threshold already exists
  ALREADY_PATCHED=false
  for level in "${MEMORY_LEVELS[@]}"; do
    if echo "$CURRENT_CONFIG" | jq -r '.thresholds[].level' 2>/dev/null | grep -q "^${level}$"; then
      ALREADY_PATCHED=true
      break
    fi
  done

  if [ "$ALREADY_PATCHED" = true ]; then
    echo "  cc-context-awareness config: memory thresholds already present (skipped)"
  else
    NEW_THRESHOLDS="$(cat "$THRESHOLDS_FILE")"
    UPDATED_CONFIG="$(echo "$CURRENT_CONFIG" | jq --argjson new "$NEW_THRESHOLDS" '
      .thresholds = ($new + .thresholds)
    ')"
    echo "$UPDATED_CONFIG" > "$CONFIG_FILE"
    echo "  Patched cc-context-awareness config: added memory thresholds at 50%, 65%, 80%"
  fi
else
  echo "  Warning: Could not find threshold config — patch cc-context-awareness config manually"
  echo "    Add thresholds from: templates/simple-session-memory/cc-context-awareness.thresholds.json"
fi

# ── Patch settings.json with hooks ───────────────────────────────────────────

SESSION_START_CMD="$HOOKS_DIR/session-start.sh"
STOP_CHECK_CMD="$HOOKS_DIR/stop-check.sh"

SESSION_START_ENTRY="$(jq -n --arg cmd "$SESSION_START_CMD" \
  '{"matcher": "compact", "hooks": [{"type": "command", "command": $cmd}]}')"

STOP_ENTRY="$(jq -n --arg cmd "$STOP_CHECK_CMD" \
  '{"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}')"

ARCHIVE_AGENT_ENTRY="$(jq -n '{
  "matcher": "",
  "hooks": [{
    "type": "agent",
    "prompt": "MEMORY ARCHIVAL TASK: Check if the file .claude/memory/.archive-needed exists. If it does NOT exist, return immediately with {\"ok\": true}. If it DOES exist: 1) List all session memory files in .claude/memory/ matching session-*.md (NOT in the archive/ subdirectory). Sort them by filename ascending — the highest counter (last alphabetically) is the most recent. 2) If there are fewer than 5, delete .archive-needed and return {\"ok\": true}. 3) If there are 5 or more: a) Identify the files to archive: ALL files EXCEPT the most recent one (highest counter). Keep the newest file intact — never delete it. b) Create .claude/memory/archive/ if it does not exist. c) Read the files to archive (oldest first). d) Write a consolidated archive to .claude/memory/archive/archive-YYYY-MM-DD.md (use today'\''s date) with this structure: a header, a table of contents listing each source log, then each log separated by horizontal rules and a heading with the source filename. Make the archive a coherent synthesis — preserve key decisions, outcomes, and any information useful for future context. e) Update .claude/memory/index.md: move the archived sessions from the main table to the Archives section (create that section if it does not exist), and add a row for the new archive file showing the date range it covers. If index.md does not exist, create it with an Archives section only. f) Delete the archived source session-*.md files (NOT the most recent one). g) Delete .claude/memory/.archive-needed. Return {\"ok\": true}.",
    "timeout": 180
  }]
}')"

SETTINGS_FILENAME="$(basename "$SETTINGS_FILE")"

if [ ! -f "$SETTINGS_FILE" ]; then
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  jq -n \
    --argjson sessionstart "$SESSION_START_ENTRY" \
    --argjson stop "$STOP_ENTRY" \
    --argjson archive "$ARCHIVE_AGENT_ENTRY" \
    '{
      "hooks": {
        "SessionStart": [$sessionstart],
        "Stop": [$stop, $archive]
      }
    }' > "$SETTINGS_FILE"
  echo "  Created $SETTINGS_FILENAME with simple-session-memory hooks"
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

  # SessionStart (compact)
  if [ "$(has_command "$SETTINGS" "SessionStart" "$SESSION_START_CMD")" != "true" ]; then
    SETTINGS="$(append_hook "$SETTINGS" "SessionStart" "$SESSION_START_ENTRY")"
    echo "  Added SessionStart hook (memory restore after compaction)"
  else
    echo "  SessionStart hook already registered (skipped)"
  fi

  # Stop (memory check)
  if [ "$(has_command "$SETTINGS" "Stop" "$STOP_CHECK_CMD")" != "true" ]; then
    SETTINGS="$(append_hook "$SETTINGS" "Stop" "$STOP_ENTRY")"
    echo "  Added Stop hook (memory write enforcement)"
  else
    echo "  Stop hook already registered (skipped)"
  fi

  # Stop (archive agent) — check by prompt snippet
  HAS_ARCHIVE="$(echo "$SETTINGS" | jq '
    (.hooks.Stop // []) |
    any(.hooks[]?.type == "agent" and (.hooks[]?.prompt | test("MEMORY ARCHIVAL TASK")))
  ' 2>/dev/null || echo "false")"

  if [ "$HAS_ARCHIVE" != "true" ]; then
    SETTINGS="$(append_hook "$SETTINGS" "Stop" "$ARCHIVE_AGENT_ENTRY")"
    echo "  Added Stop agent hook (session archival)"
  else
    echo "  Archive agent hook already registered (skipped)"
  fi

  echo "$SETTINGS" > "$SETTINGS_FILE"
  echo "  Updated $SETTINGS_FILENAME"
fi

# ── Create memory directory ───────────────────────────────────────────────────

MEMORY_DIR="$CLAUDE_DIR/memory"
mkdir -p "$MEMORY_DIR"
mkdir -p "$MEMORY_DIR/archive"
echo "  Created memory directory at $MEMORY_DIR"

# ── Optionally append to CLAUDE.md ───────────────────────────────────────────

if [ "$NO_CLAUDE_MD" = false ]; then
  CLAUDE_MD="$(pwd)/CLAUDE.md"
  SNIPPET_FILE="$SCRIPT_DIR/CLAUDE.snippet.md"

  if [ ! -f "$SNIPPET_FILE" ] && [ "$SOURCE_MODE" = "remote" ]; then
    SNIPPET_FILE="/tmp/simple-session-memory-claude-snippet.md"
    curl -fsSL "${REPO_URL}/CLAUDE.snippet.md" -o "$SNIPPET_FILE" 2>/dev/null || true
  fi

  if [ -f "$SNIPPET_FILE" ]; then
    if [ -f "$CLAUDE_MD" ]; then
      if grep -q "Session Memory System" "$CLAUDE_MD" 2>/dev/null; then
        echo "  CLAUDE.md: session memory instructions already present (skipped)"
      else
        echo "" >> "$CLAUDE_MD"
        echo "---" >> "$CLAUDE_MD"
        echo "" >> "$CLAUDE_MD"
        cat "$SNIPPET_FILE" >> "$CLAUDE_MD"
        echo "  Appended session memory instructions to CLAUDE.md"
      fi
    else
      cp "$SNIPPET_FILE" "$CLAUDE_MD"
      echo "  Created CLAUDE.md with session memory instructions"
    fi
  fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "✓ simple-session-memory installed ($INSTALL_MODE)!"
echo ""
echo "  Hooks:    $HOOKS_DIR"
echo "  Memory:   $MEMORY_DIR"
echo "  Config:   $CONFIG_FILE (memory thresholds added)"
echo "  Settings: $SETTINGS_FILE"
echo ""
echo "  How it works:"
echo "    50% context → Claude writes initial session memory log"
echo "    65% context → Claude appends progress update"
echo "    80% context → Claude appends final update + suggests /compact"
echo "    Auto-compact → After compaction, memory log is loaded as context"
echo "    On stop    → If no log written this session, Claude writes one first"
echo "    Every 5 sessions → Logs archived to $MEMORY_DIR/archive/"
echo ""
echo "  Restart Claude Code to activate."
echo ""
