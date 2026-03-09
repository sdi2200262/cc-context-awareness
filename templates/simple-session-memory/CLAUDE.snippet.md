# Session Memory System

This project uses an automated session memory system that logs work at context thresholds and restores it after compaction.

## Session Model

Each session log represents one Claude's context window. Multiple Claudes work one after the other, each with its own log.

| Scenario | Trigger | `continues:` field | Previous context loaded? |
|----------|---------|-------------------|--------------------------|
| **Continuation** | `/compact` or autocompaction | Yes — links to previous session | Yes — hook injects previous log |
| **Fresh session** | `/clear`, new CC session | No | No — orient from index |

**Continuation** carries the workstream across a context reset with a handoff summary. **Fresh session** starts independently — no prior context injected.

## At Session Start

If `.claude/memory/index.md` exists, read it for orientation.

## Logging

The cc-context-awareness system injects reminders at 50%, 65%, and 80% context usage. At 50%, read the logging guide at `.claude/skills/log-session-memory/SKILL.md` and follow it to create your session log. Later reminders tell you to update the log in place — edit existing sections to reflect current state, update `context_at_log` in frontmatter.

## After Compaction

A hook loads the most recent session log. Always create a **new** session directory and log. Add `continues: <previous-session>` to the YAML frontmatter. Update `index.md`.

## Archival

When 5+ session directories accumulate, a hook injects archival instructions. Delegate to the `memory-archiver` agent (`.claude/agents/memory-archiver.md`), then handle the cleanup it requests.

## Content Placement

| Store | Location | Content | Character |
|-------|----------|---------|-----------|
| **Session logs** | `.claude/memory/session-*/` | Per-session work, decisions, handoff data | Ephemeral. One Claude's context window. |
| **Session index** | `.claude/memory/index.md` | Execution history, durable observations | Historical. Accumulates. |
| **Auto-memory** | `MEMORY.md` (CC native) | Current repo state, working notes | Living. Changes with code. No history. |

- **`MEMORY.md`** reflects the present — when code changes, it changes. Stale entries removed.
- **`index.md`** accumulates the past — session history, durable observations. Entries persist.

If you write to `MEMORY.md`, include a pointer: `## Session Memory` — `Session-specific work logs at .claude/memory/ — see index.md for history.`
