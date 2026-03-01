# cc-context-awareness

Tell Claude what to do based on how much context it has used. Configurable thresholds inject custom instructions into [Claude Code](https://docs.anthropic.com/en/docs/claude-code) conversations at specific usage levels — trigger pre-compaction workflows, save session state, or change behavior before context runs out.

<p align="center">
  <img src="docs/diagram.svg" alt="cc-context-awareness architecture diagram" width="800"/>
</p>

## Quick Install

```bash
npx cc-context-awareness
```

This opens an interactive menu. Or install directly:

```bash
npx cc-context-awareness install                          # install base system
npx cc-context-awareness install simple-session-memory    # install a template
npx cc-context-awareness install apm-handoff --global     # install globally
```

| Mode | Scripts | Settings | Use case |
|------|---------|----------|----------|
| Local (default) | `./.claude/cc-context-awareness/` | `./.claude/settings.local.json` | Different thresholds per project |
| Global (`--global`) | `~/.claude/cc-context-awareness/` | `~/.claude/settings.json` | Same config everywhere |

**Priority:** Local settings override global. If you have both installed, the local config is used in that project.

Restart Claude Code after installing.

<details>
<summary><strong>simple-session-memory template</strong> — automated session memory on top of cc-context-awareness</summary>

Claude writes memory logs at 50/65/80% context, restores them after compaction, and archives old logs via a custom agent.

```bash
npx cc-context-awareness install simple-session-memory
npx cc-context-awareness install simple-session-memory --global  # global
```

See [Templates](#templates) for details.

</details>

<details>
<summary><strong>apm-handoff template</strong> - automatic Handoff triggers for APM agents</summary>

Agents never silently hit the context wall. At 70% context (configurable), the agent automatically initiates its Handoff procedure. A SessionStart hook then signals the incoming agent that a Handoff is pending. For use with [APM](https://github.com/sdi2200262/agentic-project-management) v1.0.0-dev.

```bash
npx cc-context-awareness install apm-handoff
npx cc-context-awareness install apm-handoff --global  # global
```

See [Templates](#templates) for details.

</details>

### Install Options

| Flag | Effect |
|------|--------|
| `--global` | Install globally to `~/.claude/` instead of locally to `./.claude/` |
| `--no-skill` | Skip the agent skill; install a standalone configuration guide instead |
| `--no-claude-md` | Skip appending template instructions to `CLAUDE.md` |

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Node.js](https://nodejs.org/) >= 18 (for `npx`)
- [`jq`](https://jqlang.github.io/jq/download/) (runtime dependency for bash scripts) — install with `brew install jq` (macOS) or `sudo apt-get install jq` (Ubuntu)

## What It Does

Claude Code has built-in context awareness, but it's hardcoded — a single warning at 20% remaining that you can't change. This tool makes it configurable: set thresholds at any percentage, inject any instruction, and trigger workflows automatically. Configurable thresholds are a [commonly](https://github.com/anthropics/claude-code/issues/14258) [requested](https://github.com/anthropics/claude-code/issues/11819) [feature](https://github.com/anthropics/claude-code/issues/6621) not yet available natively.

| | Claude Code built-in | cc-context-awareness |
|---|---|---|
| Thresholds | Hardcoded (20% remaining) | Fully configurable |
| Multiple tiers | No | Yes (e.g. 60%, 80%, 95%) |
| Custom messages | No | Yes — inject any instruction |
| Trigger workflows | No | Yes — pre-compaction saves, behavioral changes |

## How It Works

The goal is to inject custom instructions into Claude's conversation when context thresholds are crossed. Claude Code's extension points don't support this directly, so this tool bridges two mechanisms:

1. **Bridge** (statusLine) — a transparent pipe prefix that extracts `used_percentage` from the JSON Claude Code sends to statusLine scripts, writes it to a session-scoped file (`/tmp/.cc-ctx-pct-{session_id}`), and passes the original JSON through to any downstream statusLine tool
2. **Threshold evaluator** (PreToolUse hook) — reads the percentage from the bridge's file, evaluates thresholds from config.json, and injects the message as `additionalContext` into Claude's conversation
3. **Reset handler** (SessionStart hook) — runs after `/compact` or auto-compaction, clears stale state files so the post-compaction agent starts clean

This happens inside the agentic loop — Claude receives your custom instructions mid-task, not just at the end. Files are session-scoped, so multiple Claude Code instances don't interfere.

### How the bridge composes with other statusLine tools

The bridge is a transparent pipe prefix. If you already have a statusLine tool like [ccstatusline](https://github.com/sirmalloc/ccstatusline), the installer automatically prepends the bridge:

```
bridge.sh | bunx ccstatusline@latest
```

The bridge extracts percentage data from stdin, writes it to a file, and passes the full JSON through to your existing tool unchanged. No wrapper scripts or manual configuration needed.

### Compaction handling

After `/compact` or auto-compaction, the `session_id` stays the same but context drops sharply. A `SessionStart` reset handler clears stale state files and plants a compaction marker — if the bridge writes percentage data before the evaluator runs, the evaluator sees the marker and resets instead of using stale data.

## Templates

Ready-to-use configurations that install hooks and config on top of the base system. One template active at a time — installing a new one replaces the previous.

### simple-session-memory

Automated session memory for single-agent sessions. Claude writes incremental memory logs at 50%, 65%, and 80% context usage, reads them back after compaction, and archives old logs via a dedicated custom agent.

```
50% context  →  writes initial session log
65% context  →  appends progress update
80% context  →  appends final update + suggests /compact
auto-compact →  memory log loaded as context after compaction
every 5 logs →  custom agent archives into a compressed summary
```

See [`templates/simple-session-memory/README.md`](templates/simple-session-memory/README.md) for full details.

### apm-handoff

Automatic Handoff triggers for [APM](https://github.com/sdi2200262/agentic-project-management) (Agentic Project Management) agents. Agents never silently hit the context wall - at 70% (configurable), they automatically initiate a Handoff. A SessionStart detection hook then signals the incoming agent that a Handoff is pending.

```
70% context  → agent automatically triggers Handoff procedure
new session  → hook detects pending Handoff, signals incoming agent
```

See [`templates/apm-handoff/README.md`](templates/apm-handoff/README.md) for full details.

## Use Cases

<details>

These examples leverage the core benefit: **deterministic steering**. Claude receives real context data, not guesses — so your instructions can be precise, whether you're running interactive sessions or autonomous agent loops.

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

The default configuration warns at 80% context usage with a message telling Claude to proactively inform you and suggest `/compact`. This catches the most common problem — sessions silently hitting context limits and triggering unexpected compaction that loses context. With the threshold warning Claude can pause and request guidance from User on how to address remaining work.

### Graduated multi-tier warnings

Add thresholds at 60%, 80%, and 95% with escalating urgency. For example:
- At 60%, Claude mentions context is getting used up.
- At 80%, it actively suggests compaction.
- At 95%, it stops what it's doing and insists on wrapping up or compacting.

Useful for long coding sessions where you want progressive nudges rather than a single alarm.

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

Inform Claude at every 20% of context usage so it can make decisions based on real data. Instead of a single warning at the end, Claude knows exactly where it stands throughout the session. Useful when Claude is executing long-horizon tasks — multi-file refactors, extended debugging, or multi-step plans — and needs to pace its work, prioritize what to tackle first, and decide when to wrap up rather than start something new.

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

### Ralph Loops and autonomous agents

[Ralph Loops](https://github.com/snarktank/ralph) (named after Ralph Wiggum) are autonomous agent loops that repeatedly feed Claude the same prompt until completion — progress persists in files and git, not context. They can run for hours, but context exhaustion is a real risk: the agent may start a new iteration cycle right before hitting the limit, losing work or behaving erratically.

This tool can steer Ralph Loops by injecting instructions before context runs out:

```json
{
  "thresholds": [
    {"percent": 70, "level": "ralph-warning", "message": "Context at {percentage}%. You are in an autonomous loop. Finish your current iteration cleanly — commit progress, update status files, and prepare for a potential context reset."},
    {"percent": 90, "level": "ralph-stop", "message": "Context at {percentage}%. STOP starting new work. Complete the current iteration, commit all changes, write a handoff summary to HANDOFF.md, and signal loop completion."}
  ]
}
```

This ensures the agent wraps up cleanly before compaction, rather than getting cut off mid-iteration.

</details>

## Configuration

<details>

Config file: `.claude/cc-context-awareness/config.json` (local) or `~/.claude/cc-context-awareness/config.json` (global).

By default, an agent skill is installed that teaches Claude the full config schema (see [Agent Skill](#agent-skill)). If you installed with `--no-skill`, a standalone configuration guide is placed at `.claude/cc-context-awareness/configuration-guide.md` instead.

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
| `message` | string | Message injected into conversation. Supports `{percentage}`, `{remaining}`, and `{session_id}` placeholders |

#### `repeat_mode` (string)

| Value | Behavior |
|-------|----------|
| `"once_per_tier_reset_on_compaction"` | Each tier fires once. Resets if usage drops below threshold. **Default.** |
| `"once_per_tier"` | Each tier fires once per session. Never resets. |
| `"every_turn"` | Fires on every turn while above the threshold. |

#### `flag_dir` (string)

Directory for flag files. Default: `"/tmp"`.

</details>

## Agent Skill

<details>

By default, the installer adds an agent skill at `.claude/skills/configure-context-awareness/SKILL.md`. This teaches Claude the full config schema, examples, and conflict handling rules so you can say things like:

- *"Add a critical warning at 95% context usage"*
- *"Make context warnings fire every turn"*

If you'd rather not have the skill registered, install with `--no-skill`:

```bash
npx cc-context-awareness install --no-skill
```

</details>

## CLI Commands

```bash
npx cc-context-awareness                     # Interactive menu
npx cc-context-awareness install             # Install base (interactive template selection)
npx cc-context-awareness install <template>  # Install a specific template
npx cc-context-awareness remove <template>   # Remove a template
npx cc-context-awareness list                # List available templates
npx cc-context-awareness status              # Show what's installed
npx cc-context-awareness uninstall           # Remove everything
```

Add `--global` to any command to target `~/.claude/` instead of `./.claude/`.

## Uninstall

```bash
npx cc-context-awareness uninstall           # local
npx cc-context-awareness uninstall --global  # global
```

This removes all installed files (including the skill and active template), cleans up settings entries, and deletes flag files. Other hooks and settings are left intact.

## Known Limitations

- **One-turn delay**: The bridge writes percentage data after each assistant message; the evaluator reads it on the next tool call. With `PreToolUse` (default) this delay is minimal.
- **Requires `jq` and bash 3.2+** (satisfied by default on macOS and most Linux).
- **Flag files in `/tmp`**: Small and ephemeral. Change `flag_dir` in config if `/tmp` is unavailable.
- **One template at a time**: Installing a new template replaces the previous one.

## License

MIT
