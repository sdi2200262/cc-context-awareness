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

- [`jq`](https://jqlang.github.io/jq/download/) (runtime dependency)
- [Node.js](https://nodejs.org/) >= 18 (for `npx`)

## Install

```bash
npx cc-context-awareness@latest install simple-session-memory
npx cc-context-awareness@latest install simple-session-memory --global  # global
```

The base system is installed automatically if not already present.

### Install Options

| Flag | Effect |
|------|--------|
| `--global` | Install to `~/.claude/` (all projects) instead of `./.claude/` (this project) |
| `--no-claude-md` | Skip appending memory instructions to `CLAUDE.md` |

## What Gets Installed

```
.claude/
  agents/
    memory-archiver.md              # Custom archival agent (sonnet, acceptEdits)
  memory/
    index.md                        # Running index of all sessions
    archive/                        # Synthesized archives of older sessions
  simple-session-memory/
    hooks/
      session-start.sh              # Loads memory after compaction
      archival.sh                   # Triggers archival when >= 5 logs accumulate
      approve-memory-write.sh       # PreToolUse hook — approves .claude/memory/ writes
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

`.claude/memory/index.md` is a three-tier information hierarchy maintained by Claude and the memory-archiver agent. It gives fresh sessions quick orientation into what's been worked on.

```markdown
# Session Memory Index

## Active Sessions

| Session | Date | Summary |
|---------|------|---------|
| session-2026-02-19-007.md | 2026-02-19 | Completed auth middleware refactor |

## Archives

| Archive | Period | Summary |
|---------|--------|---------|
| archive-2026-02-15.md | Feb 10 – Feb 18 | Auth system and API rate limiting |

## Appendices

### February 2026

#### archive-2026-02-15.md (Feb 10 – Feb 18)
Built out authentication middleware and API rate limiting. Key decisions: ...
```

**Active Sessions** is maintained by Claude during normal sessions. **Archives** and **Appendices** are managed by the memory-archiver agent during archival. Appendices provide a mid-signal tier — more detail than the table, less than the full archive files. Prior-month appendices are automatically compressed into single-paragraph summaries.

## Archival

When 5 session logs accumulate in `.claude/memory/`, `archival.sh` fires at the start of the next post-compaction session (after `session-start.sh` restores context). It injects instructions telling Claude to delegate to the `memory-archiver` custom agent (`.claude/agents/memory-archiver.md`), which:

1. Archives all logs **except the most recent** (the newest is always preserved)
2. Creates a synthesized archive at `.claude/memory/archive/archive-YYYY-MM-DD.md`
3. Updates `index.md` — moves entries to Archives, writes Appendix summaries, compresses prior-month appendices
4. Returns a deletion manifest — the calling agent handles all file removals

The custom agent uses the `sonnet` model by default (configurable to `haiku` in the agent file) and has `acceptEdits` permission mode. A `PreToolUse` hook (`approve-memory-write.sh`) in the agent's frontmatter outputs `permissionDecision: "allow"` for `.claude/memory/` paths, bypassing the permission system entirely. This is critical for background subagents, which auto-deny any tool not pre-approved upfront.

After archival there is always exactly one individual session log remaining — the previous session — so there is never a context gap between sessions. Archives preserve key decisions, outcomes, and context useful for future sessions.

## Migration

After upgrading, run the migration skill to bring existing installations up to date:

```
/migrate-simple-session-memory
```

The skill audits CLAUDE.md, index.md, settings.local.json, and the approve-memory-write hook — fixing any differences from the current release format. It's idempotent: if everything is current, it reports "no migration needed."

## Design Notes

**Why threshold-triggered writes, not hooks?** Claude Code hooks can't run LLM prompts at `PreCompact`. Since cc-context-awareness already injects instructions at configurable thresholds, it's the natural mechanism for triggering memory writes. Stop hooks weren't used because they stall sessions in non-interactive permission modes.

**Why a custom agent for archival, not bash?** Bash can concatenate logs, but an LLM can *synthesize* them — dropping noise and preserving signal. `archival.sh` does the cheap count check in pure bash; the memory-archiver agent (sonnet, `acceptEdits`) only runs when needed.

**Why a PreToolUse hook for permissions?** Background subagents auto-deny any tool not pre-approved upfront — neither `permissionMode: acceptEdits` nor `permissions.allow` rules reliably propagate. The `approve-memory-write.sh` hook uses `permissionDecision: "allow"` in the PreToolUse output to bypass the permission system entirely for `.claude/memory/` paths. This is defined in the agent's frontmatter (scoped to the agent's lifetime) and also registered in settings (as a project-level fallback). For non-memory paths, the hook exits 0 with no output, falling through to the normal permission check.

**Compaction safety:** After compaction, cc-context-awareness uses a compaction marker to prevent stale threshold evaluations. This protects all thresholds including `memory-50/65/80`.

**Native auto-memory compatibility:** Session logs (`.claude/memory/`) and Claude Code's auto-memory (`~/.claude/projects/.../memory/MEMORY.md`) occupy different namespaces and complement each other — session logs for per-session work history, auto-memory for stable cross-session knowledge.

## Uninstall

```bash
npx cc-context-awareness@latest remove simple-session-memory
npx cc-context-awareness@latest remove simple-session-memory --global  # global
```

This removes hooks, cleans up settings, and removes the `memory-50`/`memory-65`/`memory-80` thresholds from cc-context-awareness config. Memory logs at `.claude/memory/` are preserved.
