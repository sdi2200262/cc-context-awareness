# Session Memory System

This project uses an automated session memory system. Follow these instructions throughout every session.

## At Session Start

If `.claude/memory/index.md` exists, read it. It lists recent sessions and archives — use it to orient yourself without reading full logs unless needed.

## Memory Log Location and Naming

Session memory logs are stored in `.claude/memory/` with this naming convention:

```
session-YYYY-MM-DD-NNN.md
```

Where `NNN` is a per-day counter: find the highest NNN among `session-YYYY-MM-DD-*.md` files for **today's date** in `.claude/memory/` (not in `archive/`), and add 1, zero-padded to 3 digits. If no files exist for today, start at 001. The counter resets each new day. The session ID is stored in the frontmatter, not the filename.

## When to Write Memory

The cc-context-awareness system injects reminders at 50%, 65%, and 80% context usage. Each reminder includes your current session ID. When you receive one:

- **First reminder (50%)**: Check `.claude/memory/` for a file with `session_id: <your session ID>` in its frontmatter. If none exists, create a new one using the counter. Also update `index.md` (add a row to Active Sessions).
- **Later reminders (65%, 80%)**: Find your existing log for this session and append to it.

## Creating a New Log

1. List `session-YYYY-MM-DD-*.md` files in `.claude/memory/` (not `archive/`) matching **today's date**
2. Find the highest NNN among them; if none exist, use 000
3. Add 1, zero-pad to 3 digits (e.g. `001`, `002`)
4. Create `.claude/memory/session-YYYY-MM-DD-NNN.md`

## Memory Log Format

```markdown
---
date: YYYY-MM-DD
session_id: <full session ID from the reminder>
context_at_log: <percentage>%
continues: <previous-log-filename>  # optional — only when continuing after compaction
attachments: attachments/<session-filename-stem>/  # optional — only when attachments exist
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

`.claude/memory/index.md` is a three-tier information hierarchy: the **table** for quick orientation, the **appendices** for high-signal summaries, and the **archive files** for full detail.

Format:

```markdown
# Session Memory Index

## Active Sessions

| Session | Date | Summary |
|---------|------|---------|
| session-2026-03-04-002.md | 2026-03-04 | Archival redesign |

## Archives

| Archive | Period | Summary |
|---------|--------|---------|
| archive-2026-03-04.md | Feb 28 – Mar 3 | Implementation and first iteration |

## Appendices

### March 2026

#### archive-2026-03-04.md (Feb 28 – Mar 3)
Established session memory template with hook-based restoration. Key decisions: ...

### February 2026
Early exploration phase. Set up base system with threshold reminders. ...
```

**Ownership rules:**

- **Claude** (normal sessions): add/update rows in **Active Sessions** when creating or updating a session log. Do not edit Archives or Appendices.
- **Archiver**: moves rows from Active Sessions → Archives, writes appendix entries under the current month, and compresses prior-month appendices into single paragraphs.

Keep the most recent sessions at the top of the Active Sessions table.

## After Compaction

Compaction resets the context window. A hook automatically loads the most recent session log (or archive) so you can pick up where work left off, but the pre-compaction context is gone.

**Rule:** Always create a new session log after compaction — even if the loaded log has the same `session_id` as your current session.

To link the new log to the one it continues from, add a `continues:` field to the YAML frontmatter:

```yaml
continues: session-2026-03-04-001.md
```

Update `index.md` with the new log entry.

## Attachments

When supplementary content (analysis findings, research output, detailed tables) exceeds ~50 lines, it belongs in an attachment rather than the session log. The session log should summarize key findings; the attachment holds the full detail.

**Directory convention:**

```
.claude/memory/attachments/<session-filename-stem>/
```

`<session-filename-stem>` is the session log filename without `.md` (e.g., `session-2026-03-04-002`). Add the `attachments:` field to the session log's YAML frontmatter pointing to this directory.

**Lifecycle:** Attachments are ephemeral. During archival, the memory-archiver synthesizes their content into the archive narrative, and the attachment directory is then deleted. They exist only as long as the session log they belong to.

## Archival

When 5+ session logs accumulate, a hook injects archival instructions after the next compaction. When you see these instructions, delegate to the `memory-archiver` agent (defined in `.claude/agents/memory-archiver.md`) to synthesize the older logs into `.claude/memory/archive/`, then handle the file cleanup it requests. The newest session log is always preserved — never archived — so the most recent context is never lost.

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
