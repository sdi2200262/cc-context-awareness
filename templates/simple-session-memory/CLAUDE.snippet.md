# Session Memory System

This project uses an automated session memory system. Follow these instructions throughout every session.

## At Session Start

If `.claude/memory/index.md` exists, read it. It lists recent sessions and archives — use it to orient yourself without reading full logs unless needed.

## Memory Log Location and Naming

Session memory logs are stored in `.claude/memory/` with this naming convention:

```
session-YYYY-MM-DD-NNN.md
```

Where `NNN` is derived by counting existing `session-*.md` files directly in `.claude/memory/` (not in `archive/`) and adding 1, zero-padded to 3 digits. The session ID is stored in the frontmatter, not the filename.

## When to Write Memory

The cc-context-awareness system injects reminders at 50%, 65%, and 80% context usage. Each reminder includes your current session ID. When you receive one:

- **First reminder (50%)**: Check `.claude/memory/` for a file with `session_id: <your session ID>` in its frontmatter. If none exists, create a new one using the counter. Also update `index.md`.
- **Later reminders (65%, 80%)**: Find your existing log for this session and append to it.

## Creating a New Log

1. Count existing `session-*.md` files directly in `.claude/memory/` (not in `archive/`)
2. Add 1, zero-pad to 3 digits (e.g. `007`)
3. Create `.claude/memory/session-YYYY-MM-DD-NNN.md`

## Memory Log Format

```markdown
---
date: YYYY-MM-DD
session_id: <full session ID from the reminder>
context_at_log: <percentage>%
---

## Current Work
[What task or project is being worked on and its current state]

## Completed This Session
[What was accomplished — specific files, features, fixes]

## Key Decisions
[Important technical or design choices made, and why]

## Files Modified
[Key files created or changed with brief descriptions]
- `path/to/file.ts` — description of change

## In Progress
[Anything started but not finished]

## Next Steps
[Specific actions to take next session — enough detail to continue immediately]

## Notes
[User preferences, known issues, environment details, other context]
```

Subsequent updates append with a separator:

```markdown
---
*Updated at 65% context*

[Updated sections only]
```

## Session Index (`index.md`)

`.claude/memory/index.md` is a running index of all sessions. When creating a new session log (at 50%), add or update the row for this session:

```markdown
# Session Memory Index

| File | Date | Summary |
|------|------|---------|
| session-YYYY-MM-DD-NNN.md | YYYY-MM-DD | One-sentence summary of current work |

## Archives
| Archive | Covers |
|---------|--------|
| archive-YYYY-MM-DD.md | sessions NNN–NNN (date range) |
```

Keep the most recent sessions at the top of the table. The Archives section is managed by the archival subagent — do not edit it manually.

## After Compaction

When resuming after compaction, a hook automatically loads the most recent session log (or archive if no individual log exists) as context. The `session_id` in that log belongs to the previous session — your current session has a different ID. Create a new log for your current session using the counter, and update `index.md`.

## Archival

When 5 session logs accumulate, a hook injects archival instructions at the start of the next post-compaction session. When you see these instructions, launch a subagent to synthesize the older logs into `.claude/memory/archive/`. The newest session log is always preserved — never archived — so the previous session's context is never lost.

## Integration with Claude Code Auto-Memory

Claude Code's native auto-memory (`MEMORY.md` in `~/.claude/projects/<project>/memory/`) and this session memory system serve **different purposes and different namespaces** — they do not conflict:

| System | Location | Purpose | Loaded |
|--------|----------|---------|--------|
| Native auto-memory | `~/.claude/projects/.../memory/MEMORY.md` | Stable cross-session knowledge: preferences, conventions, architecture | Every session start (auto) |
| Session logs | `.claude/memory/session-*.md` | Per-session work history: what was done, decisions, next steps | After compaction (via hook), or on-demand |
| Session index | `.claude/memory/index.md` | Index of all sessions for quick orientation | On-demand (read at session start per instructions above) |

**Synergy:** If Claude Code auto-memory is active and you write to `MEMORY.md` this session, add a brief pointer:

```markdown
## Session Memory
Session-specific work logs at `.claude/memory/` — see `index.md` for history.
```

This ensures every fresh session (not just post-compaction) sees a reminder to check the session index. Keep it brief — `MEMORY.md` has a 200-line display limit.
