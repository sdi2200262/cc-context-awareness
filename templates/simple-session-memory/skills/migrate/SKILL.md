---
name: migrate-simple-session-memory
description: Migrate an existing simple-session-memory installation to match the current release format. Run this after upgrading the template to bring CLAUDE.md instructions, directory structure, and index.md up to date.
---

# Simple Session Memory Migration

You are migrating the user's simple-session-memory installation to the current release format. This is a **target-state migration** — check what the user has, compare it to what the current release expects, and fix any differences. If everything is already current, report that and stop.

## Target State Summary

The current release uses **directory-per-session** layout and a formal **content placement** model:

```
.claude/memory/
  session-YYYY-MM-DD-NNN/
    session-YYYY-MM-DD-NNN.md     # the session log
    <supplementary files>         # formerly "attachments"
  index.md
  archives/
    archive-NAME/
      archive-NAME.md             # the archive log
      <supplementary attachments> # optional — load-bearing reference content
```

Key changes from previous versions:
- Session logs live inside their own directory (not as flat files in `.claude/memory/`)
- Supplementary files (formerly "attachments") live alongside the log in the session directory (not in a separate `.claude/memory/attachments/` tree)
- Archives use a directory-per-archive layout (`archives/archive-NAME/archive-NAME.md`) mirroring sessions, replacing the old flat `archive/archive-NAME.md` files. Archive directories may contain supplementary attachments preserved verbatim from the archived sessions.
- The directory itself was renamed `archive/` → `archives/` (plural).
- Index references use session stems without `.md` (e.g. `session-2026-03-04-002`, not `session-2026-03-04-002.md`)
- The `continues:` field in YAML frontmatter also uses stems without `.md`
- The `attachments:` YAML field is no longer used (co-location replaces it)
- The `.session-count` global counter file is no longer used (per-day directory scanning replaces it)
- Bash permissions changed: `Bash(rm -r .claude/memory/session-*)` replaces the old `Bash(rm .claude/memory/session-*)` and `Bash(rm -r .claude/memory/attachments/*)`

## Process

Work through each audit in order. Read before writing. Report changes at the end.

### 1. Audit CLAUDE.md

The installer saves a reference copy of the current snippet at `.claude/simple-session-memory/CLAUDE.snippet.md`. This is the source of truth.

1. Read `.claude/simple-session-memory/CLAUDE.snippet.md` (the **reference**).
2. Read `CLAUDE.md` in the project root.
3. Find the Session Memory System section — it starts with `# Session Memory System` and is delimited from the rest of CLAUDE.md by `---` separators.
4. Compare the section content to the reference. If they differ (even partially), replace the entire section with the reference content. Preserve everything outside the section (before and after the `---` delimiters).
5. If no Session Memory System section exists in CLAUDE.md, append it with a `---` separator (same as a fresh install).

### 2. Migrate directory structure

This is the critical step. Convert flat session logs to directory-per-session layout.

**Check first:** If `.claude/memory/` already contains `session-*/` directories (not flat files), the structure may already be migrated. Verify by checking whether session logs exist as flat files (`session-*.md` directly in `.claude/memory/`) or inside directories.

**If flat session log files exist in `.claude/memory/`:**

For each `session-*.md` file directly in `.claude/memory/` (not inside a subdirectory, not in `archive/` or `archives/`):

1. Extract the stem (filename without `.md`, e.g. `session-2026-03-09-004`)
2. Create the directory: `mkdir -p .claude/memory/<stem>/`
3. Move the log: `mv .claude/memory/<stem>.md .claude/memory/<stem>/<stem>.md`
4. If `.claude/memory/attachments/<stem>/` exists, move its contents into the session directory:
   - `mv .claude/memory/attachments/<stem>/* .claude/memory/<stem>/`
   - `rmdir .claude/memory/attachments/<stem>/`

After processing all session logs:
- If `.claude/memory/attachments/` exists and is empty, remove it: `rmdir .claude/memory/attachments/`
- If `.claude/memory/.session-count` exists, remove it: `rm .claude/memory/.session-count`

**Do NOT touch (in this step):**
- `.claude/memory/archive/` or `.claude/memory/archives/` — archive layout is handled in step 3
- `.claude/memory/index.md` — handled in step 4

### 3. Migrate archive layout

Archives moved from flat files in `archive/` to directory-per-archive in `archives/`. Two orthogonal changes: the parent directory was renamed (`archive` → `archives`), and each flat archive file became its own directory with the log inside.

**Determine current state:**

- If `.claude/memory/archives/` exists and `.claude/memory/archive/` does not, the rename is done — proceed to per-archive layout check.
- If `.claude/memory/archive/` exists, rename it: `mv .claude/memory/archive .claude/memory/archives`.
- If neither exists, create the empty directory: `mkdir -p .claude/memory/archives`.

**Per-archive directory layout:**

For each `archive-*.md` file directly in `.claude/memory/archives/` (a flat file, not inside a subdirectory):

1. Extract the stem (filename without `.md`, e.g. `archive-2026-03-09`).
2. Create the directory: `mkdir -p .claude/memory/archives/<stem>/`.
3. Move the log: `mv .claude/memory/archives/<stem>.md .claude/memory/archives/<stem>/<stem>.md`.

There are no pre-existing supplementary attachments to migrate (the old layout did not support them); the new directory will hold only the log file until a future archival run adds attachments.

If every archive is already laid out as `archives/<stem>/<stem>.md`, skip this step.

### 4. Audit index.md

Read `.claude/memory/index.md`. If the file doesn't exist, skip this step.

The expected structure has three sections with specific column names:

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

1. **Session references** — if entries in the Active Sessions table use `.md` suffixes (e.g. `session-2026-03-09-004.md`), strip the `.md` to just the stem (`session-2026-03-09-004`).
2. **Active Sessions** — if there's a bare `| File | Date | Summary |` table without a `## Active Sessions` heading above it, add the heading and rename the `File` column to `Session`.
3. **Archives** — if the table uses `| Archive | Covers |` columns, reshape to `| Archive | Period | Summary |` — move the `Covers` value to `Period`, leave `Summary` empty.
4. **Archive links** — if any archive references in the Archives table or Appendices section point to the old flat layout (`archive/archive-NAME.md` or `archives/archive-NAME.md` without the directory wrapper), update them to `archives/archive-NAME/archive-NAME.md` to match the directory-per-archive layout. Stem-only references with no path are also acceptable; only rewrite path-bearing links.
5. **Appendices** — if there's no `## Appendices` section, add it at the end (empty — appendices are populated by future archival runs).
6. **Preserve all data rows** — only restructure, never delete session or archive entries.

If the index already has all three sections with the correct column names, stem-based session references, and directory-per-archive links, skip it.

### 5. Audit settings.local.json

Read `.claude/settings.local.json`. Check for these entries and fix as needed:

**Permissions** — ensure `permissions.allow` contains:
- `Write(.claude/memory/**)`
- `Edit(.claude/memory/**)`
- `Bash(rm -r .claude/memory/session-*)`

**Remove old permissions** if present:
- `Bash(rm .claude/memory/session-*)` (old flat-file permission — without `-r`)
- `Bash(rm -r .claude/memory/attachments/*)` (no longer needed)

**PreToolUse hook** — ensure a `PreToolUse` hook entry exists with matcher `Write|Edit` pointing to the approve-memory-write script at `.claude/simple-session-memory/hooks/approve-memory-write.sh`.

### 6. Audit approve-memory-write hook

Check that `.claude/simple-session-memory/hooks/approve-memory-write.sh` exists and is executable. If it's missing, warn the user to reinstall the template (`npx cc-context-awareness@latest install simple-session-memory`).

### 7. Audit logging skill

Check that `.claude/skills/log-session-memory/SKILL.md` exists. This skill contains the detailed session logging procedure referenced by threshold messages. If it's missing, warn the user to reinstall the template.

### 8. Report

After completing all audits, report to the user:

- Which files were updated and what changed (brief summary per file)
- How many session logs were migrated to directory-per-session
- How many attachment directories were merged into session directories
- Whether the archive directory was renamed (`archive/` → `archives/`) and how many flat archive files were wrapped into per-archive directories
- Which files were already current (skipped)
- If everything was current: "Installation is up to date — no migration needed."

## Important

- **Be idempotent**: if a file already matches the target state, skip it. If session directories already exist, don't re-migrate.
- **Preserve user data**: never delete session logs, archive files, or index rows. Only restructure and move.
- **Read before writing**: always read the full file before making edits.
- **Use Edit, not Write**: for existing files, use targeted edits to preserve surrounding content.
- **Use Bash for file operations**: `mkdir`, `mv`, `rm`, `rmdir` for the directory structure migration.
- **Session log content is backwards-compatible**: do NOT modify YAML frontmatter inside session logs. Old `continues: session-*.md` and `attachments:` fields are historical and harmless — leave them as-is.
- **The archiver agent does not need migration** — the installer already replaces it with the current version on reinstall.
