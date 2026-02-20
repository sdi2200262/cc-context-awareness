# simple-session-memory template


A lightweight automated memory system for single-agent Claude Code sessions. Inspired by the handover protocol in [Agentic PM](https://github.com/sdi2200262/agentic-project-management), adapted for solo sessions where one agent logs its own work incrementally and picks it back up after compaction.

## What It Does

Turns cc-context-awareness threshold warnings into an automated session journal. Claude writes memory at 50%, 65%, and 80% context usage — catching auto-compaction early — then reads the log back after compaction to restore context without losing work.

```
50% context  →  Claude writes initial session log
65% context  →  Claude appends a progress update
80% context  →  Claude appends final update + suggests /compact
Auto-compact →  After resuming, memory log is loaded as context
Every 5 logs →  A subagent synthesizes them into an archive
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

**Via curl (local — this project only):**
```bash
curl -fsSL https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/templates/simple-session-memory/install.sh | bash
```

**Via curl (global — all projects):**
```bash
curl -fsSL https://raw.githubusercontent.com/sdi2200262/cc-context-awareness/main/templates/simple-session-memory/install.sh | bash -s -- --global
```

**From a cloned repo:**
```bash
# Local install (this project only)
./templates/simple-session-memory/install.sh

# Global install (all projects)
./templates/simple-session-memory/install.sh --global
```

### Install Options

| Flag | Effect |
|------|--------|
| `--global` | Install to `~/.claude/` (all projects) instead of `./.claude/` (this project) |
| `--no-claude-md` | Skip appending memory instructions to `CLAUDE.md` |

## What Gets Installed

### Hooks added to settings (local or global)

| Hook event | Matcher | Script | Purpose |
|------------|---------|--------|---------|
| `SessionStart` | `compact` | `session-start.sh` | After compaction: loads most recent memory log (or archive) as context |
| `SessionStart` | `compact` | `archival.sh` | Counts session logs; injects archival instructions if ≥ 5 accumulate |

### cc-context-awareness config changes

Adds three memory-trigger thresholds to your existing cc-context-awareness config:

| Threshold | Level | Action |
|-----------|-------|--------|
| 50% | `memory-50` | Claude writes initial session log |
| 65% | `memory-65` | Claude appends progress update |
| 80% | `memory-80` | Claude appends final update + suggests /compact |

These are prepended to your existing thresholds so memory writes happen before your existing warnings.

### Files created

```
.claude/
  memory/
    index.md                        # Running index of all sessions (auto-maintained)
    archive/                        # Synthesized archives of older sessions
  simple-session-memory/
    hooks/
      session-start.sh
      archival.sh
CLAUDE.md                           # Instructions appended (optional)
```

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

The table stays at the top; the Archives section is managed by the archival subagent.

## Archival

When 5 session logs accumulate in `.claude/memory/`, `archival.sh` fires at the start of the next post-compaction session (after `session-start.sh` restores context). It injects instructions telling Claude to launch a subagent that:

1. Archives all logs **except the most recent** (the newest is always preserved)
2. Creates a synthesized archive at `.claude/memory/archive/archive-YYYY-MM-DD.md`
3. Updates `index.md` — moves archived entries to the Archives section
4. Deletes the archived source logs

After archival there is always exactly one individual session log remaining — the previous session — so there is never a context gap between sessions. Archives preserve key decisions, outcomes, and context useful for future sessions.

## Design Notes

**Why threshold-triggered writes instead of hooks?** Claude Code hooks can run bash scripts but not LLM prompts at `PreCompact` — only `Stop` and a few others support agent/prompt hooks. Since cc-context-awareness already injects instructions into Claude's context at configurable thresholds, it's the natural mechanism for triggering semantic memory writes.

**Why not use a Stop hook?** Stop hooks that block Claude (returning `decision: "block"`) cause problems in non-interactive permission modes — they stall the session waiting for a response that won't come. Instead, the 50%/65%/80% threshold reminders give Claude plenty of opportunity to write a log before any compaction, and the Stop hook is not needed.

**Why a subagent for archival, not bash concatenation?** Concatenating 5 logs is trivial in bash, but a subagent can *synthesize* them — dropping ephemeral details and preserving the signal. The archive is meant to be readable months later, not just a dump. `archival.sh` does the cheap count check in pure bash with zero token cost; the subagent only runs when actually needed.

**Does this conflict with Claude Code's native auto-memory (`MEMORY.md`)?** No — they occupy entirely different namespaces. Native auto-memory lives at `~/.claude/projects/<project>/memory/MEMORY.md` (outside the repo) and is auto-loaded at every session start. Session logs live at `.claude/memory/` (inside the repo) and are loaded by hooks or on-demand. The two are complementary: MEMORY.md stores stable cross-session knowledge (preferences, architecture decisions); session logs store ephemeral per-session work history. If you use both, a one-line pointer in MEMORY.md to `index.md` gives every fresh session awareness of the session log system.

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
