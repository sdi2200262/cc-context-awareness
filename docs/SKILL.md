---
name: configure-context-awareness
description: Configure the cc-context-awareness context window warning system. Use when the user wants to change context warning thresholds, messages, status bar appearance, or other cc-context-awareness settings.
---

# cc-context-awareness Configuration

cc-context-awareness monitors Claude Code context window usage and warns you when it's getting full. It uses a status line to show usage, a hook to inject warnings into the conversation, and a reset handler to clear stale state after compaction.

## Config File

cc-context-awareness can be installed **locally** (per-project) or **globally**:

| Mode | Config location | Settings file |
|------|-----------------|---------------|
| Local (default) | `./.claude/cc-context-awareness/config.json` | `./.claude/settings.local.json` |
| Global | `~/.claude/cc-context-awareness/config.json` | `~/.claude/settings.json` |

**Priority:** Local settings override global (per Claude Code's settings hierarchy). If both exist, the local config is effective in that project.

Always read the current config before making changes. Use the Edit tool — never overwrite the whole file.

## What To Do

1. Read `~/.claude/cc-context-awareness/config.json`
2. Refer to the config schema and examples below
3. Make targeted edits based on what the user wants

## Conflict Handling

### StatusLine conflicts

If another tool is using the `statusLine` slot, cc-context-awareness can **wrap** or **merge** with it. The statusline script writes a flag file that the hook reads — this bridge must be preserved for warnings to fire.

#### ccstatusline integration (most common case)

[ccstatusline](https://github.com/sirmalloc/ccstatusline) is a popular status line formatter. If the user has it installed, their `settings.json` will have a `statusLine` entry like:

```json
{
  "statusLine": "bunx ccstatusline@latest"
}
```
or
```json
{
  "statusLine": "npx ccstatusline@latest"
}
```

**When the user already has ccstatusline installed, use a wrapper script.**

**Step 1:** Identify the ccstatusline command from `~/.claude/settings.json` (or the local `.claude/settings.json`/`settings.local.json`).

**Step 2:** Create a wrapper script at `~/.claude/statusline-wrapper.sh`:

```bash
#!/usr/bin/env bash
# ~/.claude/statusline-wrapper.sh
# Runs ccstatusline (display) then cc-context-awareness (flag writing)
INPUT=$(cat)
echo "$INPUT" | bunx ccstatusline@latest   # or: npx ccstatusline@latest
echo "$INPUT" | ~/.claude/cc-context-awareness/context-awareness-statusline.sh
```

Make it executable:
```bash
chmod +x ~/.claude/statusline-wrapper.sh
```

**Step 3:** Update `settings.json` to use the wrapper:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-wrapper.sh"
  }
}
```

**Hiding the cc-context-awareness bar (optional):** ccstatusline already has a `ContextPercentage` widget that shows context usage visually. If the user doesn't want a duplicate bar, they can suppress cc-context-awareness's own output while keeping its flag-writing active. In the wrapper script, redirect cc-context-awareness output to `/dev/null`:

```bash
#!/usr/bin/env bash
# Wrapper: ccstatusline (display) + cc-context-awareness (flag only, no display)
INPUT=$(cat)
echo "$INPUT" | bunx ccstatusline@latest
echo "$INPUT" | ~/.claude/cc-context-awareness/context-awareness-statusline.sh > /dev/null
```

This preserves the full threshold/hook functionality while using ccstatusline exclusively for display.

**For local installs:** The cc-context-awareness scripts are at `./.claude/cc-context-awareness/`. Adjust the wrapper paths accordingly:

```bash
#!/usr/bin/env bash
INPUT=$(cat)
echo "$INPUT" | bunx ccstatusline@latest
echo "$INPUT" | "$(pwd)/.claude/cc-context-awareness/context-awareness-statusline.sh" > /dev/null
```

#### Generic wrapper (other statusline tools)

For any other statusline tool:

```bash
#!/usr/bin/env bash
INPUT=$(cat)
echo "$INPUT" | /path/to/other/statusline.sh
echo "$INPUT" | ~/.claude/cc-context-awareness/context-awareness-statusline.sh
```

**Option 2: Merge**

Copy the flag-writing logic from `~/.claude/cc-context-awareness/context-awareness-statusline.sh` into the existing statusline script. The critical parts are:
1. Reading thresholds from `~/.claude/cc-context-awareness/config.json`
2. Writing the trigger file to `/tmp/.cc-ctx-trigger-{session_id}` when thresholds are crossed
3. Tracking fired tiers in `/tmp/.cc-ctx-fired-{session_id}`
4. Clearing both files on compaction via the `SessionStart` reset handler

The hook reads from the trigger file, so as long as that file is written correctly, warnings will fire.

### Other conflicts

- If the user has other hooks in `settings.json`, never remove them — only modify cc-context-awareness entries
- If editing thresholds, ensure each `level` value is unique

## Config Schema

### `thresholds` (array of objects)

Each threshold triggers a warning when context usage reaches that percentage.

| Field | Type | Description |
|-------|------|-------------|
| `percent` | number | Context usage percentage to trigger at (0–100) |
| `level` | string | Unique tier identifier (e.g. `"warning"`, `"critical"`). Must be unique across thresholds. |
| `message` | string | Message injected into conversation. Supports `{percentage}` and `{remaining}` placeholders |

### `repeat_mode` (string)

Controls when warnings re-fire.

| Value | Behavior |
|-------|----------|
| `"once_per_tier_reset_on_compaction"` | Each tier fires once. Resets if usage drops below the threshold (e.g. after compaction). **Default.** |
| `"once_per_tier"` | Each tier fires once per session. Never resets. |
| `"every_turn"` | Fires on every turn while above the threshold. |

### `statusline` (object)

Controls the status bar appearance.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Show the status line |
| `bar_width` | number | `20` | Width of the progress bar in characters |
| `bar_filled` | string | `"█"` | Character for filled portion |
| `bar_empty` | string | `"░"` | Character for empty portion |
| `format` | string | `"context {bar} {percentage}%"` | Format string. Supports `{bar}` and `{percentage}` |
| `color_normal` | string | `"37"` | ANSI color code for normal state (37=white) |
| `color_warning` | string | `"31"` | ANSI color code for warning state (31=red) |
| `warning_indicator` | string | `""` | Appended to bar when above a threshold. Empty by default (color change is the indicator). |

### `hook_event` (string)

Which Claude Code hook event triggers the context injection.

| Value | Behavior |
|-------|----------|
| `"PreToolUse"` | Fires before every tool call inside the agentic loop. **Default.** |
| `"PostToolUse"` | Fires after every tool call inside the agentic loop. |
| `"UserPromptSubmit"` | Fires once per user prompt. No mid-loop coverage. |

Changing this value also requires re-running the installer to update `settings.json`:
```bash
./install.sh --hook-event PostToolUse
```

### `flag_dir` (string)

Directory for flag files. Default: `"/tmp"`.

## Example Modifications

### Add a critical tier at 95%

Add to the `thresholds` array:
```json
{
  "percent": 95,
  "level": "critical",
  "message": "CRITICAL: Context window is at {percentage}% ({remaining}% remaining). You MUST inform the user immediately and either /compact or wrap up the current task NOW."
}
```

### Lower the warning threshold to 70%

Modify the existing threshold's `percent` field from `80` to `70`.

### Add multiple tiers

Replace the `thresholds` array with:
```json
[
  {"percent": 60, "level": "info", "message": "Context usage at {percentage}%. Consider planning for compaction."},
  {"percent": 80, "level": "warning", "message": "Context at {percentage}% ({remaining}% left). Suggest /compact to the user."},
  {"percent": 95, "level": "critical", "message": "CRITICAL: {percentage}% context used. Wrap up or /compact immediately."}
]
```

### Change bar style to simple ASCII

```json
{
  "bar_filled": "#",
  "bar_empty": "-"
}
```

### Use yellow for warnings instead of red

Set `color_warning` to `"33"` (ANSI yellow).

### Make warnings fire every turn

Set `repeat_mode` to `"every_turn"`.

### Custom warning message with specific instructions

```json
{
  "message": "Context at {percentage}%. Before continuing, summarize what you've done so far and what remains, then ask the user if they want to /compact."
}
```

## Templates

Ready-to-use configurations for common use cases. Templates add hooks and config on top of a base cc-context-awareness install.

### simple-session-memory

When the user asks about memory management, session continuity after compaction, saving state before context runs out, or automated handoff — this template is the right recommendation.

The simple-session-memory template adds:
- Memory-trigger thresholds at 50%, 65%, 80% context usage → Claude writes/appends `.claude/memory/session-YYYY-MM-DD-NNN.md` (counter-based; session_id in frontmatter)
- A `SessionStart` hook (matcher: `compact`) → after compaction, loads the most recent memory log (or archive) as `additionalContext`
- A `SessionStart` hook (matcher: `compact`) → every 5 session logs, the `memory-archiver` custom agent (`.claude/agents/memory-archiver.md`) archives all but the newest into `.claude/memory/archive/`
- A session index at `.claude/memory/index.md` → maintained by Claude at each 50% checkpoint; gives fresh sessions a quick orientation into recent history

**Install (must have cc-context-awareness already installed):**
```bash
# From repo:
./templates/simple-session-memory/install.sh           # local
./templates/simple-session-memory/install.sh --global  # global

# Via curl (local):
curl -fsSL https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/templates/simple-session-memory/install.sh | bash
```

**What it adds to config.json:**

```json
[
  {"percent": 50, "level": "memory-50", "message": "Context at {percentage}% — MEMORY CHECKPOINT (50%): Write your initial session memory log now..."},
  {"percent": 65, "level": "memory-65", "message": "Context at {percentage}% — MEMORY UPDATE (65%): Append an update to your session memory log..."},
  {"percent": 80, "level": "memory-80", "message": "Context at {percentage}% ({remaining}% remaining) — MEMORY UPDATE (80%): Append a final update..."}
]
```

These thresholds are prepended to any existing thresholds.

**Memory log format** (Claude writes these):
```markdown
---
date: YYYY-MM-DD
session_id: abc12345
context_at_log: 50%
---

## Current Work
## Completed This Session
## Key Decisions
## Files Modified
## In Progress
## Next Steps
## Notes
```

Updates are appended with `---\n*Updated at X%*` separators.

**For ccstatusline users:** The simple-session-memory template works seamlessly alongside ccstatusline. No additional integration needed — just ensure cc-context-awareness is running via the statusline wrapper (see [StatusLine conflicts](#statusline-conflicts)).

## Common ANSI Color Codes

| Code | Color |
|------|-------|
| `30` | Black |
| `31` | Red |
| `32` | Green |
| `33` | Yellow |
| `34` | Blue |
| `35` | Magenta |
| `36` | Cyan |
| `37` | White |
