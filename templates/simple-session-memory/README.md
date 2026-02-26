# simple-session-memory template


A lightweight automated memory system for single-agent Claude Code sessions. Inspired by the handover protocol in [Agentic PM](https://github.com/sdi2200262/agentic-project-management), adapted for solo sessions where one agent logs its own work incrementally and picks it back up after compaction.

## What It Does

Turns cc-context-awareness threshold warnings into an automated session journal. Claude writes memory at 50%, 65%, and 80% context usage — catching auto-compaction early — then reads the log back after compaction to restore context without losing work.

```
50% context  →  Claude writes initial session log
65% context  →  Claude appends a progress update
80% context  →  Claude appends final update + suggests /compact
Auto-compact →  After resuming, memory log is loaded as context
Every 5 logs →  The memory-archiver agent synthesizes them into an archive
```

Memory logs are named `.claude/memory/session-YYYY-MM-DD-NNN.md` where `NNN` is derived by counting existing logs in `.claude/memory/` at write time. The session ID is stored in the YAML frontmatter, not the filename — this makes logs easy to sort and archive without encoding volatile identifiers into paths. Each log captures:
- Current task and project state
- Work completed this session
- Key decisions made
- Files modified
- What's in progress
- Specific next steps for continuation
- Any other relevant context

## Requirements

- `jq`
- cc-context-awareness is **installed automatically** if not already present

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/templates/simple-session-memory/install.sh | bash
curl -fsSL https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/templates/simple-session-memory/install.sh | bash -s -- --global  # global
```

Or from a cloned repo: `./templates/simple-session-memory/install.sh` (add `--global` for all projects).

### Install Options

| Flag | Effect |
|------|--------|
| `--global` | Install to `~/.claude/` (all projects) instead of `./.claude/` (this project) |
| `--no-claude-md` | Skip appending memory instructions to `CLAUDE.md` |

## What Gets Installed

```
.claude/
  agents/
    memory-archiver.md              # Custom archival agent (haiku, acceptEdits)
  memory/
    index.md                        # Running index of all sessions
    archive/                        # Synthesized archives of older sessions
  simple-session-memory/
    hooks/
      session-start.sh              # Loads memory after compaction
      archival.sh                   # Triggers archival when ≥ 5 logs accumulate
CLAUDE.md                           # Instructions appended (optional)
```

**Thresholds added** to cc-context-awareness config (prepended to your existing ones):

| Threshold | Level | Action |
|-----------|-------|--------|
| 50% | `memory-50` | Claude writes initial session log |
| 65% | `memory-65` | Claude appends progress update |
| 80% | `memory-80` | Claude appends final update + suggests /compact |

## Memory Log Format

```markdown
---
date: YYYY-MM-DD
session_id: abc12345
context_at_log: 50%
---

## Current Work
What task is being worked on and its current state.

## Completed This Session
Specific files changed, features added, bugs fixed.

## Key Decisions
Technical choices made and why.

## Files Modified
- `src/index.ts` — added auth middleware
- `tests/auth.test.ts` — new tests for login flow

## In Progress
Work started but not finished.

## Next Steps
Specific actions for next session — enough to continue without reading the codebase again.

## Notes
User preferences, known issues, environment details.
```

Updates are appended with a separator:

```markdown
---
*Updated at 65% context*

[New information since last checkpoint]
```

## Session Index

`.claude/memory/index.md` is a running table of all sessions, maintained by Claude at each 50% checkpoint. It gives fresh sessions (not just post-compaction restores) a quick orientation into what's been worked on.

```markdown
# Session Memory Index

| File | Date | Summary |
|------|------|---------|
| session-2026-02-19-007.md | 2026-02-19 | Completed auth middleware refactor |
| session-2026-02-18-006.md | 2026-02-18 | Added API rate limiting |

## Archives
| Archive | Covers |
|---------|--------|
| archive-2026-02-15.md | sessions 001–005 (2026-02-10 to 2026-02-15) |
```

The table stays at the top; the Archives section is managed by the memory-archiver agent.

## Archival

When 5 session logs accumulate in `.claude/memory/`, `archival.sh` fires at the start of the next post-compaction session (after `session-start.sh` restores context). It injects instructions telling Claude to delegate to the `memory-archiver` custom agent (`.claude/agents/memory-archiver.md`), which:

1. Archives all logs **except the most recent** (the newest is always preserved)
2. Creates a synthesized archive at `.claude/memory/archive/archive-YYYY-MM-DD.md`
3. Updates `index.md` — moves archived entries to the Archives section
4. Deletes the archived source logs

The custom agent uses the `haiku` model for cost efficiency and has `acceptEdits` permission mode so it can write to `.claude/` without prompting. This solves permission issues that occur when using a generic subagent via the Task tool.

After archival there is always exactly one individual session log remaining — the previous session — so there is never a context gap between sessions. Archives preserve key decisions, outcomes, and context useful for future sessions.

## Design Notes

**Why threshold-triggered writes, not hooks?** Claude Code hooks can't run LLM prompts at `PreCompact`. Since cc-context-awareness already injects instructions at configurable thresholds, it's the natural mechanism for triggering memory writes. Stop hooks weren't used because they stall sessions in non-interactive permission modes.

**Why a custom agent for archival, not bash?** Bash can concatenate logs, but an LLM can *synthesize* them — dropping noise and preserving signal. `archival.sh` does the cheap count check in pure bash; the memory-archiver agent (haiku, `acceptEdits`) only runs when needed and avoids the permission errors that generic Task-tool subagents hit when writing to `.claude/`.

**Compaction safety:** After compaction, cc-context-awareness uses a compaction marker to prevent late-running statusline updates from re-creating stale trigger files. This protects all thresholds including `memory-50/65/80`.

**Native auto-memory compatibility:** Session logs (`.claude/memory/`) and Claude Code's auto-memory (`~/.claude/projects/.../memory/MEMORY.md`) occupy different namespaces and complement each other — session logs for per-session work history, auto-memory for stable cross-session knowledge.

## Uninstall

```bash
# Local uninstall
./templates/simple-session-memory/uninstall.sh

# Global uninstall
./templates/simple-session-memory/uninstall.sh --global
```

Or via curl:
```bash
curl -fsSL https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/templates/simple-session-memory/uninstall.sh | bash
```

The uninstaller removes hooks, cleans up settings, and removes the `memory-50`/`memory-65`/`memory-80` thresholds from cc-context-awareness config. Memory logs at `.claude/memory/` are preserved.
