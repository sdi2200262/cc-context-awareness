---
name: log-session-memory
description: Create or update a session memory log. Called automatically by context threshold reminders, or manually to force a memory write.
---

# Session Memory Logging Guide

This guide covers the full procedure for creating and updating session memory logs. Read it when a context threshold reminder fires or when you need to write a log manually.

## Session Directory Structure

Each session gets its own directory:

```
.claude/memory/
  session-YYYY-MM-DD-NNN/
    session-YYYY-MM-DD-NNN.md     # the session log
    <supplementary files>         # optional — analysis, plans, research
  index.md
  archive/
```

`NNN` is a per-day counter that resets each calendar day.

## Finding Your Existing Log

Before creating a new log, check if one already exists for your session:

Search `.claude/memory/session-*/session-*.md` for a file with your `session_id` in its YAML frontmatter. If found, that is your log — update it instead of creating a new one.

## Creating a New Session

1. List `session-YYYY-MM-DD-*/` directories in `.claude/memory/` matching **today's date**
2. Find the highest NNN among them; if none exist, use 000
3. Add 1, zero-pad to 3 digits (e.g. `001`, `002`)
4. Create the directory: `.claude/memory/session-YYYY-MM-DD-NNN/`
5. Create the log: `.claude/memory/session-YYYY-MM-DD-NNN/session-YYYY-MM-DD-NNN.md`

## Log Format

```markdown
---
date: YYYY-MM-DD
session_id: <your session ID>
context_at_log: <percentage>%
continues: <previous-session-name>  # only for continuations — omit on fresh sessions
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

## Updating an Existing Log

At 65% and 80% context, update the log **in place** — edit the existing sections to reflect current state. Do not append or duplicate sections. Update `context_at_log` in the YAML frontmatter to the current percentage so the recency of the log is always visible.

At 80%, make **Next Steps** highly specific — exact file paths, function names, what state things are in. Write as if handing off to someone who has never seen this session.

## Supplementary Files

When content exceeds ~50 lines (analysis findings, research output, detailed tables, design specs), write it as a separate file in the session directory alongside the log:

```
.claude/memory/session-2026-03-04-002/
  session-2026-03-04-002.md       # log — summarizes findings
  exploration-findings.md          # supplementary — full detail
  refactor-plan.md                 # supplementary — full detail
```

No special YAML field needed — co-location makes the relationship clear. Supplementary files are ephemeral and deleted during archival.

## Updating the Index

After creating or updating a log, update `.claude/memory/index.md`.

### Active Sessions table

Add or update a row for your session. Most recent at the top. Use the session stem (no `.md`):

```markdown
| Session | Date | Summary |
|---------|------|---------|
| session-2026-03-04-002 | 2026-03-04 | One-sentence summary of current work |
```

### Creating index.md from scratch

If the file doesn't exist, create it:

```markdown
# Session Memory Index

## Active Sessions

| Session | Date | Summary |
|---------|------|---------|

## Archives

| Archive | Period | Summary |
|---------|--------|---------|

## Appendices
```

### What belongs in the index

The index is the **historical record and process knowledge store**. Beyond session tables, appendices capture durable observations:

- User preferences and working patterns
- Process knowledge and effective workflows
- Recurring themes and cross-session trends
- Project milestones and their significance

These accumulate and persist. They are **not** working technical notes about current codebase state — those belong in `MEMORY.md`.

**Ownership:** Claude updates Active Sessions only. The memory-archiver agent manages Archives and Appendices.
