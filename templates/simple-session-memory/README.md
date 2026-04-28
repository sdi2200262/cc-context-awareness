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

## Session Model

Each session log represents one Claude's context window. Multiple Claudes work one after the other on the same project, each leaving a log for the next. Two scenarios create a new log:

| Scenario | Trigger | `continues:` | Previous context loaded? |
|----------|---------|-------------|--------------------------|
| **Continuation** | `/compact` or autocompaction | Yes | Yes — hook injects previous log |
| **Fresh session** | `/clear`, new CC session | No | No — orient from index |

**Continuation** means the user's workstream carries across a context reset — same work, new context window, with a handoff summary. **Fresh session** means a new workstream begins independently, with no prior context injected.

Logs are never overwritten or reused across context windows.

Detailed logging instructions live in a dedicated skill (`.claude/skills/log-session-memory/SKILL.md`), keeping the CLAUDE.md snippet slim. The 50% threshold tells Claude to read the skill; later thresholds are self-contained with just the append format.

## Directory-per-Session

Each session gets its own directory containing the log and any supplementary files:

```
.claude/memory/
  session-2026-03-04-001/
    session-2026-03-04-001.md     # the session log
    exploration-findings.md        # supplementary (optional)
    refactor-plan.md               # supplementary (optional)
  session-2026-03-04-002/
    session-2026-03-04-002.md
  index.md
  archives/
```

Session directories are named `session-YYYY-MM-DD-NNN` where `NNN` is a per-day counter (resets daily). The log file inside shares the directory name. Supplementary files (analysis, plans, research) live alongside the log — no separate attachments convention needed. The co-location makes relationships clear and cleanup simple (`rm -r` the whole directory).

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
    archives/                       # Synthesized archives (one directory per archive)
  skills/
    log-session-memory/SKILL.md     # Detailed logging procedure (read by 50% threshold)
    migrate-simple-session-memory/  # Migration skill for upgrades
  simple-session-memory/
    hooks/
      session-start.sh              # Loads memory after compaction
      archival.sh                   # Triggers archival when >= 5 sessions accumulate
      approve-memory-write.sh       # PreToolUse hook — approves .claude/memory/ writes
    CLAUDE.snippet.md               # Reference copy of CLAUDE.md instructions
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

At 65% and 80% context, the log is updated in place — existing sections are edited to reflect current state and `context_at_log` in the frontmatter is bumped. No appending or duplicating sections.

## Session Index

`.claude/memory/index.md` is a three-tier information hierarchy maintained by Claude and the memory-archiver agent. It gives fresh sessions quick orientation and serves as the project's historical record and process knowledge store.

```markdown
# Session Memory Index

## Active Sessions

| Session | Date | Summary |
|---------|------|---------|
| session-2026-02-19-007 | 2026-02-19 | Completed auth middleware refactor |

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

## Content Placement

| Store | Location | Content | Character |
|-------|----------|---------|-----------|
| **Session logs** | `.claude/memory/session-*/` | Per-session work, decisions, handoff data | Ephemeral. One Claude's context window. |
| **Session index** | `.claude/memory/index.md` | Execution history, durable observations, process knowledge | Historical. Accumulates. |
| **Auto-memory** | `MEMORY.md` (CC native) | Current repo state, working technical notes | Living. Changes with code. No history. |

`MEMORY.md` reflects the present (what is the current state?). `index.md` accumulates the past (what happened and what was learned?). They complement each other without overlap.

## Archival

When 5 session directories accumulate in `.claude/memory/`, `archival.sh` fires at the start of the next post-compaction session (after `session-start.sh` restores context). It injects instructions telling Claude to delegate to the `memory-archiver` custom agent (`.claude/agents/memory-archiver.md`), which:

1. Archives all sessions **except the most recent** (the newest is always preserved)
2. Creates a synthesized archive directory at `.claude/memory/archives/archive-YYYY-MM-DD/` containing the archive log and any supplementary attachments worth preserving verbatim (load-bearing specs, structured data, reference material that downstream sessions cite by content)
3. Updates `index.md` — moves entries to Archives, writes Appendix summaries with durable observations, compresses prior-month appendices
4. Returns a deletion manifest — the calling agent handles all directory removals

The custom agent uses the `sonnet` model by default (configurable to `haiku` in the agent file) and has `acceptEdits` permission mode. A `PreToolUse` hook (`approve-memory-write.sh`) in the agent's frontmatter outputs `permissionDecision: "allow"` for `.claude/memory/` paths, bypassing the permission system entirely. This is critical for background subagents, which auto-deny any tool not pre-approved upfront.

After archival there is always exactly one session directory remaining — the previous session — so there is never a context gap between sessions. Archives preserve key decisions, outcomes, and context useful for future sessions.

## Migration

After upgrading, run the migration skill to bring existing installations up to date:

```
/migrate-simple-session-memory
```

The skill audits CLAUDE.md, index.md, settings.local.json, and the session directory structure — fixing any differences from the current release format. It handles converting flat session logs to directory-per-session layout and migrating attachments. It's idempotent: if everything is current, it reports "no migration needed."

## Design Notes

**Why threshold-triggered writes, not hooks?** Claude Code hooks can't run LLM prompts at `PreCompact`. Since cc-context-awareness already injects instructions at configurable thresholds, it's the natural mechanism for triggering memory writes. Stop hooks weren't used because they stall sessions in non-interactive permission modes.

**Why a custom agent for archival, not bash?** Bash can concatenate logs, but an LLM can *synthesize* them — dropping noise and preserving signal. `archival.sh` does the cheap count check in pure bash; the memory-archiver agent (sonnet, `acceptEdits`) only runs when needed.

**Why a PreToolUse hook for permissions?** Background subagents auto-deny any tool not pre-approved upfront — neither `permissionMode: acceptEdits` nor `permissions.allow` rules reliably propagate. The `approve-memory-write.sh` hook uses `permissionDecision: "allow"` in the PreToolUse output to bypass the permission system entirely for `.claude/memory/` paths. This is defined in the agent's frontmatter (scoped to the agent's lifetime) and also registered in settings (as a project-level fallback). For non-memory paths, the hook exits 0 with no output, falling through to the normal permission check.

**Why directory-per-session?** Co-locating session logs with their supplementary files simplifies organization, cleanup, and archival. No separate `attachments/` convention needed — everything for a session lives in one place. Deleting a session is `rm -r` on one directory.

**Compaction safety:** After compaction, cc-context-awareness uses a compaction marker to prevent stale threshold evaluations. This protects all thresholds including `memory-50/65/80`.

**Native auto-memory compatibility:** Session logs (`.claude/memory/session-*/`) and Claude Code's auto-memory (`~/.claude/projects/.../memory/MEMORY.md`) occupy different namespaces and serve different purposes — session logs for ephemeral per-session work history, auto-memory for current codebase state. The session index (`.claude/memory/index.md`) is the historical record; auto-memory is the living document.

## Uninstall

```bash
npx cc-context-awareness@latest remove simple-session-memory
npx cc-context-awareness@latest remove simple-session-memory --global  # global
```

This removes hooks, cleans up settings, and removes the `memory-50`/`memory-65`/`memory-80` thresholds from cc-context-awareness config. Memory logs at `.claude/memory/` are preserved.
