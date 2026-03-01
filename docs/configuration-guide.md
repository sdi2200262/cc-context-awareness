# cc-context-awareness Configuration Guide

This is a reference for configuring cc-context-awareness. You can read this guide yourself, or point Claude to it when you want help changing settings.

## Config File Location

cc-context-awareness can be installed **locally** (per-project) or **globally**:

| Mode | Config location | Settings file |
|------|-----------------|---------------|
| Local (default) | `./.claude/cc-context-awareness/config.json` | `./.claude/settings.local.json` |
| Global | `~/.claude/cc-context-awareness/config.json` | `~/.claude/settings.json` |

**Priority:** Local settings override global (per Claude Code's settings hierarchy). If both exist, the local config is effective in that project.

Read the current config before making changes. Use targeted edits — don't overwrite the whole file.

## Handling Conflicts

### StatusLine composition

The bridge script is a transparent pipe prefix that extracts percentage data from stdin and passes the original JSON through to any downstream statusLine tool. If you have another tool like [ccstatusline](https://github.com/sirmalloc/ccstatusline), the bridge is automatically prepended during install:

```
bridge.sh | bunx ccstatusline@latest
```

No manual wrapper scripts needed. The bridge extracts and caches percentage data, then passes the full JSON through unchanged to your existing statusLine tool.

### Hooks

If existing hooks are registered for the same event, cc-context-awareness **appends** to the existing array — it does not replace other hooks.

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

Ready-to-use configurations for common use cases. Each template adds hooks and config on top of a base cc-context-awareness install. One template active at a time.

### simple-session-memory

Adds an automated session memory system. Claude writes incremental memory logs at 50%, 65%, and 80% context usage, and reads the log back after auto-compaction to restore context.

**Install:**
```bash
npx cc-context-awareness install simple-session-memory        # local
npx cc-context-awareness install simple-session-memory --global  # global
```

See `templates/simple-session-memory/README.md` for full details, memory log format, and archival behavior.

### apm-handoff

Automatic Handoff triggers for APM agents at 70% context.

**Install:**
```bash
npx cc-context-awareness install apm-handoff        # local
npx cc-context-awareness install apm-handoff --global  # global
```

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
