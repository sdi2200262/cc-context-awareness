---
name: configure-context-awareness
description: Configure the cc-context-awareness context window warning system. Use when the user wants to change context warning thresholds, messages, or other cc-context-awareness settings.
---

# cc-context-awareness Configuration

cc-context-awareness monitors Claude Code context window usage and warns you when it's getting full. It uses a statusLine bridge to extract percentage data, a PreToolUse hook to evaluate thresholds and inject warnings, and a SessionStart reset handler to clear stale state after compaction.

## Config File

cc-context-awareness can be installed **locally** (per-project) or **globally**:

| Mode | Config location | Settings file |
|------|-----------------|---------------|
| Local (default) | `./.claude/cc-context-awareness/config.json` | `./.claude/settings.local.json` |
| Global | `~/.claude/cc-context-awareness/config.json` | `~/.claude/settings.json` |

**Priority:** Local settings override global (per Claude Code's settings hierarchy). If both exist, the local config is effective in that project.

Always read the current config before making changes. Use the Edit tool — never overwrite the whole file.

## What To Do

1. Read `.claude/cc-context-awareness/config.json` (or `~/.claude/cc-context-awareness/config.json` for global)
2. Refer to the config schema and examples below
3. Make targeted edits based on what the user wants

## Conflict Handling

### StatusLine composition

The bridge script is a transparent pipe prefix that extracts percentage data from stdin and passes the original JSON through to any downstream statusLine tool. If the user has another statusLine tool (like [ccstatusline](https://github.com/sirmalloc/ccstatusline)), the bridge is automatically prepended:

```
bridge.sh | bunx ccstatusline@latest
```

This happens automatically during install — no manual wrapper scripts needed. The bridge extracts and caches the percentage data, then passes the full JSON through unchanged.

If the user wants to remove cc-context-awareness while keeping their downstream tool, the uninstaller restores the original statusLine value.

### Hooks

If the user has other hooks in `settings.json`, cc-context-awareness never removes them — only its own entries are modified.

## Config Schema

### `thresholds` (array of objects)

Each threshold triggers a warning when context usage reaches that percentage.

| Field | Type | Description |
|-------|------|-------------|
| `percent` | number | Context usage percentage to trigger at (0–100) |
| `level` | string | Unique tier identifier (e.g. `"warning"`, `"critical"`). Must be unique across thresholds. |
| `message` | string | Message injected into conversation. Supports `{percentage}`, `{remaining}`, and `{session_id}` placeholders |

### `repeat_mode` (string)

Controls when warnings re-fire.

| Value | Behavior |
|-------|----------|
| `"once_per_tier_reset_on_compaction"` | Each tier fires once. Resets if usage drops below the threshold (e.g. after compaction). **Default.** |
| `"once_per_tier"` | Each tier fires once per session. Never resets. |
| `"every_turn"` | Fires on every turn while above the threshold. |

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

### Make warnings fire every turn

Set `repeat_mode` to `"every_turn"`.

### Custom warning message with specific instructions

```json
{
  "message": "Context at {percentage}%. Before continuing, summarize what you've done so far and what remains, then ask the user if they want to /compact."
}
```

## Templates

Ready-to-use configurations for common use cases. Templates add hooks and config on top of a base cc-context-awareness install. One template active at a time.

### simple-session-memory

When the user asks about memory management, session continuity after compaction, saving state before context runs out, or automated handoff — this template is the right recommendation.

The simple-session-memory template adds:
- Memory-trigger thresholds at 50%, 65%, 80% context usage
- A `SessionStart` hook (matcher: `compact`) for loading memory after compaction
- A `SessionStart` hook (matcher: `compact`) for triggering archival when 5+ logs accumulate
- A session index at `.claude/memory/index.md`

**Install:**
```bash
npx cc-context-awareness install simple-session-memory        # local
npx cc-context-awareness install simple-session-memory --global  # global
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

See `templates/simple-session-memory/README.md` for full details, memory log format, and archival behavior.

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
