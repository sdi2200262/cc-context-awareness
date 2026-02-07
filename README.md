# cc-context-awareness

Context window awareness for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Get visual feedback on context usage and automatic warnings before you run out.

```
Status line (sensor)        Flag file (bridge)         Hook (actuator)
  reads context %     ──►    writes when threshold  ──►  reads flag, injects
  renders ASCII bar          is crossed                  warning into conversation
```

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/cobuterman/cc-context-awareness/main/install.sh | bash
```

Or clone and install locally:

```bash
git clone https://github.com/cobuterman/cc-context-awareness.git
cd cc-context-awareness
./install.sh
```

Restart Claude Code after installing.

### Install Options

| Flag | Effect |
|------|--------|
| `--overwrite` | Replace an existing `statusLine` config in `settings.json` (see [Handling Conflicts](#handling-conflicts)) |
| `--no-skill` | Skip the agent skill; install a standalone configuration guide instead (see [Agent Skill](#agent-skill)) |

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [`jq`](https://jqlang.github.io/jq/download/) — install with `brew install jq` (macOS) or `sudo apt-get install jq` (Ubuntu)

## What It Does

**Status line** — Shows a live context usage bar at the bottom of your Claude Code session:

```
context ████████████░░░░░░░░ 60%        (normal — white)
context ████████████████░░░░ 82% ⚠      (warning — red)
```

**Automatic warnings** — When context usage crosses a threshold (default: 80%), a warning is injected into the next conversation turn, telling Claude to inform you and suggest compaction.

## How It Works

Claude Code has two extension points that don't normally talk to each other:

1. **Status line** — runs a command after each assistant response, receives context window data, but can only display text
2. **Hooks** — run commands on events (like user prompt submit), can inject context into the conversation, but don't receive context window data

cc-context-awareness bridges them with a flag file on disk:

1. The **status line script** (`context-awareness-statusline.sh`) receives context data from Claude Code, renders the progress bar, and when a threshold is crossed, writes a flag file to `/tmp`
2. The **hook script** (`context-awareness-hook.sh`) runs on each user prompt. If a flag file exists, it reads the warning message, outputs it as `additionalContext` for Claude, and deletes the flag

This creates a one-turn delay (the warning fires on the prompt *after* the threshold is crossed), which is acceptable since context doesn't jump dramatically between turns.

## Handling Conflicts

### Status line

Claude Code only supports **one** `statusLine` command at a time. The installer handles this carefully:

- **No existing statusLine**: Adds ours automatically
- **Our statusLine already set**: No change needed, skips
- **Another tool's statusLine**: Prints a warning with the existing command, does **not** overwrite, and continues installing the hook portion only. The status bar won't work but warnings will still fire via the hook.
- **`--overwrite` flag**: Replaces whatever statusLine is configured with ours

If you want both cc-context-awareness and another status line tool, you'll need to merge them manually into a single script that does both.

### Hooks

Hooks are **additive** — Claude Code supports multiple `UserPromptSubmit` hook entries. The installer:

- Appends our hook to any existing hook array (never replaces other hooks)
- Checks for duplicates before appending (safe to re-run)
- On uninstall, removes only our entry and leaves others intact

### Settings.json validation

If `settings.json` exists but contains invalid JSON, the installer will:

- Print an error message
- Still install the scripts (so you can fix settings.json and re-run)
- Exit without modifying the broken file

<summary><h2>Use Cases</h2></summary>

<details>

### Fine-tuned compaction with persistent memory

The most powerful use case. Instruct Claude to write session state to a memory directory or file *before* auto-compaction wipes it. This way the next compacted session has accurate context on disk and can pick up where it left off — dramatically reducing context gaps.

You can go further: point the threshold message at a file, command, or skill that contains a detailed pre-compaction workflow. Or embed the entire workflow directly into the message itself. Since the message is injected as conversation context, Claude will follow arbitrarily complex instructions.

```json
{
  "thresholds": [
    {
      "percent": 75,
      "level": "prepare",
      "message": "Context at {percentage}%. Before doing anything else: (1) Write a session summary to ~/.claude/memory/session-state.md covering: what task you're working on, what's done, what's in progress, key decisions made, files modified, and what to do next. (2) Then read ~/.claude/memory/compaction-checklist.md and follow its instructions. (3) Then tell the user you've saved state and suggest /compact."
    }
  ]
}
```

You can also keep the message lean and point to external instructions:

```json
{
  "message": "Context at {percentage}%. Read and follow the instructions in ~/.claude/memory/pre-compaction-workflow.md before continuing."
}
```

### Default: Compaction reminder (included out of the box)

The default configuration warns at 80% context usage with a message telling Claude to proactively inform you and suggest `/compact`. This catches the most common problem — sessions silently hitting context limits and triggering unexpected compaction that loses context.

### Graduated multi-tier warnings

Add thresholds at 60%, 80%, and 95% with escalating urgency. At 60%, Claude mentions context is getting used up. At 80%, it actively suggests compaction. At 95%, it stops what it's doing and insists on wrapping up or compacting. Useful for long coding sessions where you want progressive nudges rather than a single alarm.

```json
{
  "thresholds": [
    {"percent": 60, "level": "info", "message": "Context usage at {percentage}%. Consider planning for compaction soon."},
    {"percent": 80, "level": "warning", "message": "Context at {percentage}% ({remaining}% left). Suggest /compact to the user."},
    {"percent": 95, "level": "critical", "message": "CRITICAL: {percentage}% context used. Stop current work, summarize progress, and /compact immediately."}
  ]
}
```

### Continuous context awareness for long-horizon tasks

Inform Claude at every 20% of context usage so it can deterministically manage its session tasks and decisions. Instead of a single warning at the end, Claude knows exactly where it stands throughout the session. Useful when Claude is executing long-horizon tasks — multi-file refactors, extended debugging, or multi-step plans — and needs to pace its work, prioritize what to tackle first, and decide when to wrap up rather than start something new.

```json
{
  "thresholds": [
    {"percent": 20, "level": "ctx-20", "message": "Context usage: {percentage}%. {remaining}% remaining. You have plenty of room."},
    {"percent": 40, "level": "ctx-40", "message": "Context usage: {percentage}%. {remaining}% remaining. Still in good shape."},
    {"percent": 60, "level": "ctx-60", "message": "Context usage: {percentage}%. {remaining}% remaining. Start prioritizing remaining work."},
    {"percent": 80, "level": "ctx-80", "message": "Context usage: {percentage}%. {remaining}% remaining. Wrap up current task and suggest /compact."},
    {"percent": 95, "level": "ctx-95", "message": "Context usage: {percentage}%. {remaining}% remaining. Stop and /compact now."}
  ],
  "repeat_mode": "once_per_tier_reset_on_compaction"
}
```

</details>

<summary><h2>Configuration</h2></summary>

<details>

Config file: `~/.claude/cc-context-awareness/config.json`

By default, an agent skill is installed that teaches Claude the full config schema (see [Agent Skill](#agent-skill)). If you installed with `--no-skill`, a standalone configuration guide is placed at `~/.claude/cc-context-awareness/configuration-guide.md` instead.

### Default Configuration

```json
{
  "thresholds": [
    {
      "percent": 80,
      "level": "warning",
      "message": "You are at {percentage}% context window usage ({remaining}% remaining). Proactively inform the user and suggest using /compact or completing the current task before context runs out."
    }
  ],
  "repeat_mode": "once_per_tier_reset_on_compaction",
  "statusline": {
    "enabled": true,
    "bar_width": 20,
    "bar_filled": "█",
    "bar_empty": "░",
    "format": "context {bar} {percentage}%",
    "color_normal": "37",
    "color_warning": "31",
    "warning_indicator": " ⚠"
  },
  "flag_dir": "/tmp"
}
```

### Configuration Reference

#### `thresholds` (array)

Each threshold triggers a warning when context usage reaches that percentage.

| Field | Type | Description |
|-------|------|-------------|
| `percent` | number | Context usage percentage to trigger at (0–100) |
| `level` | string | Unique tier identifier (e.g. `"warning"`, `"critical"`) |
| `message` | string | Message injected into conversation. Supports `{percentage}` and `{remaining}` placeholders |

#### `repeat_mode` (string)

| Value | Behavior |
|-------|----------|
| `"once_per_tier_reset_on_compaction"` | Each tier fires once. Resets if usage drops below threshold. **Default.** |
| `"once_per_tier"` | Each tier fires once per session. Never resets. |
| `"every_turn"` | Fires on every turn while above the threshold. |

#### `statusline` (object)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Show the status line |
| `bar_width` | number | `20` | Width of the progress bar in characters |
| `bar_filled` | string | `"█"` | Character for filled portion |
| `bar_empty` | string | `"░"` | Character for empty portion |
| `format` | string | `"context {bar} {percentage}%"` | Format string. Supports `{bar}` and `{percentage}` |
| `color_normal` | string | `"37"` | ANSI color code when below all thresholds (37=white) |
| `color_warning` | string | `"31"` | ANSI color code when above any threshold (31=red) |
| `warning_indicator` | string | `" ⚠"` | Appended when above a threshold |

#### `flag_dir` (string)

Directory for flag files. Default: `"/tmp"`.

</details>

<summary><h2>Agent Skill</h2></summary>

<details>

By default, the installer adds an agent skill at `~/.claude/skills/configure-context-awareness/SKILL.md`. This teaches Claude the full config schema, examples, and conflict handling rules so you can say things like:

- *"Add a critical warning at 95% context usage"*
- *"Change the context bar to use simple ASCII characters"*
- *"Make context warnings fire every turn"*

If you'd rather not have the skill registered, install with `--no-skill`:

```bash
./install.sh --no-skill
```

This skips the skill and instead places a standalone configuration guide at `~/.claude/cc-context-awareness/configuration-guide.md`. You can point Claude to it manually:

> Read `~/.claude/cc-context-awareness/configuration-guide.md` and help me change the warning threshold to 70%.

</details>

## Uninstall

```bash
# If you still have the repo cloned:
./uninstall.sh

# Or download and run:
curl -fsSL https://raw.githubusercontent.com/cobuterman/cc-context-awareness/main/uninstall.sh | bash
```

This removes all installed files (including the skill if installed), cleans up `settings.json` entries, and deletes flag files. Other hooks and settings are left intact.

## Reinstalling / Upgrading

Re-run the install script. It will update the scripts and guide but preserve your existing `config.json` customizations.

```bash
./install.sh
```

## Known Limitations

- **One-turn delay**: Warnings fire on the prompt *after* the threshold is crossed. This is inherent to the flag-file bridge architecture.
- **Status line is exclusive**: Claude Code only supports one status line command. See [Handling Conflicts](#handling-conflicts) for how the installer deals with this.
- **Requires `jq`**: Both scripts depend on `jq` for JSON processing.
- **Flag files in `/tmp`**: Flag files are written to `/tmp` by default. They're small and ephemeral, but if `/tmp` is unavailable, change `flag_dir` in the config.

## License

MIT
