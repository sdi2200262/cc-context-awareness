---
name: migrate-simple-session-memory
description: Migrate an existing simple-session-memory installation to match the current release format. Run this after upgrading the template to bring CLAUDE.md instructions and index.md up to date.
---

# Simple Session Memory Migration

You are migrating the user's simple-session-memory installation to the current release format. This is a **target-state migration** — check what the user has, compare it to what the current release expects, and fix any differences. If everything is already current, report that and stop.

## Process

Work through each audit in order. Read before writing. Report changes at the end.

### 1. Audit CLAUDE.md

The installer saves a reference copy of the current snippet at `.claude/simple-session-memory/CLAUDE.snippet.md`. This is the source of truth.

1. Read `.claude/simple-session-memory/CLAUDE.snippet.md` (the **reference**).
2. Read `CLAUDE.md` in the project root.
3. Find the Session Memory System section — it starts with `# Session Memory System` and is delimited from the rest of CLAUDE.md by `---` separators.
4. Compare the section content to the reference. If they differ (even partially), replace the entire section with the reference content. Preserve everything outside the section (before and after the `---` delimiters).
5. If no Session Memory System section exists in CLAUDE.md, append it with a `---` separator (same as a fresh install).

### 2. Audit index.md

Read `.claude/memory/index.md`. If the file doesn't exist, skip this step (it gets created during normal usage).

The expected structure has three sections:

```
## Active Sessions
| Session | Date | Summary |

## Archives
| Archive | Period | Summary |

## Appendices
### Month YYYY
#### archive-file.md (date range)
Summary paragraph...
```

Check and fix:

1. **Active Sessions** — if there's a bare `| File | Date | Summary |` table without a `## Active Sessions` heading above it, add the heading and rename the `File` column to `Session`.
2. **Archives** — if the table uses `| Archive | Covers |` columns, reshape to `| Archive | Period | Summary |` — move the `Covers` value to `Period`, leave `Summary` empty.
3. **Appendices** — if there's no `## Appendices` section, add it at the end (empty — appendices are populated by future archival runs).
4. **Preserve all data rows** — only restructure, never delete session or archive entries.

If the index already has all three sections with the correct column names, skip it.

### 3. Audit settings.local.json

Read `.claude/settings.local.json`. Check for these entries and add any that are missing:

**Permissions** — ensure `permissions.allow` contains:
- `Write(.claude/memory/**)`
- `Edit(.claude/memory/**)`
- `Bash(rm .claude/memory/session-*)`
- `Bash(rm -r .claude/memory/attachments/*)`

**PreToolUse hook** — ensure a `PreToolUse` hook entry exists with matcher `Write|Edit` pointing to the approve-memory-write script at `.claude/simple-session-memory/hooks/approve-memory-write.sh`. Use the absolute path (based on project root).

Only add missing entries. Do not remove or reorder existing permissions or hooks.

### 4. Audit approve-memory-write hook

Check that `.claude/simple-session-memory/hooks/approve-memory-write.sh` exists and is executable. If it's missing, read the reference from `.claude/agents/memory-archiver.md` frontmatter to confirm the expected path, then warn the user to reinstall the template (`npx cc-context-awareness@latest install simple-session-memory`).

### 5. Report

After completing all audits, report to the user:

- Which files were updated and what changed (brief summary per file)
- Which files were already current (skipped)
- If everything was current: "Installation is up to date — no migration needed."

## Important

- **Be idempotent**: if a file already matches the target state, skip it.
- **Preserve user data**: never delete session logs, archive files, or index rows. Only restructure formatting.
- **Read before writing**: always read the full file before making edits.
- **Use Edit, not Write**: for existing files, use targeted edits to preserve surrounding content.
- **Session logs do not need migration** — the log format is backwards-compatible. Optional frontmatter fields (`continues:`, `attachments:`) are only added when applicable.
- **The archiver agent does not need migration** — the installer already replaces it with the current version on reinstall.
