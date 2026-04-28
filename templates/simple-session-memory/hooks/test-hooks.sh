#!/usr/bin/env bash
# Test harness for simple-session-memory hooks
# Creates temp directories with mock session data and runs each hook against them.
# Exit code 0 = all pass, 1 = failures.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
ERRORS=""

# ── Helpers ──────────────────────────────────────────────────────────────────

setup_tmpdir() {
  TMPDIR="$(mktemp -d)"
  cd "$TMPDIR"
  mkdir -p .claude/memory/archives
}

teardown_tmpdir() {
  cd /
  rm -rf "$TMPDIR"
}

assert_contains() {
  local label="$1" output="$2" expected="$3"
  if echo "$output" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected to contain: ${expected}\n    got: $(echo "$output" | head -5)"
  fi
}

assert_not_contains() {
  local label="$1" output="$2" unexpected="$3"
  if echo "$output" | grep -qF "$unexpected"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected NOT to contain: ${unexpected}"
  else
    PASS=$((PASS + 1))
  fi
}

assert_json_valid() {
  local label="$1" output="$2"
  if echo "$output" | jq . >/dev/null 2>&1; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label} — invalid JSON\n    got: $(echo "$output" | head -3)"
  fi
}

assert_empty() {
  local label="$1" output="$2"
  if [[ -z "$output" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected empty output\n    got: $(echo "$output" | head -3)"
  fi
}

assert_exit_code() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected exit code ${expected}, got ${actual}"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -e "$path" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    file does not exist: ${path}"
  fi
}

assert_dir_exists() {
  local label="$1" path="$2"
  if [[ -d "$path" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    directory does not exist: ${path}"
  fi
}

# ── Create mock session directories ──────────────────────────────────────────

create_session_dir() {
  local stem="$1" content="$2"
  mkdir -p ".claude/memory/${stem}"
  echo "$content" > ".claude/memory/${stem}/${stem}.md"
}

create_session_with_supplement() {
  local stem="$1" log_content="$2" supp_name="$3" supp_content="$4"
  mkdir -p ".claude/memory/${stem}"
  echo "$log_content" > ".claude/memory/${stem}/${stem}.md"
  echo "$supp_content" > ".claude/memory/${stem}/${supp_name}"
}

# ════════════════════════════════════════════════════════════════════════════
echo "=== approve-memory-write.sh ==="
# ════════════════════════════════════════════════════════════════════════════

# Test: allows .claude/memory/ paths
setup_tmpdir
OUTPUT=$(echo '{"tool_input":{"file_path":".claude/memory/session-2026-03-09-001/session-2026-03-09-001.md"}}' \
  | bash "$SCRIPT_DIR/approve-memory-write.sh" 2>&1) || true
assert_json_valid "approve: valid JSON for memory path" "$OUTPUT"
assert_contains "approve: allows memory path" "$OUTPUT" '"allow"'
teardown_tmpdir

# Test: allows nested .claude/memory/ paths
setup_tmpdir
OUTPUT=$(echo '{"tool_input":{"file_path":".claude/memory/archives/archive-2026-03-09/archive-2026-03-09.md"}}' \
  | bash "$SCRIPT_DIR/approve-memory-write.sh" 2>&1) || true
assert_json_valid "approve: valid JSON for archive path" "$OUTPUT"
assert_contains "approve: allows archive path" "$OUTPUT" '"allow"'
teardown_tmpdir

# Test: passes through non-memory paths (empty output)
setup_tmpdir
OUTPUT=$(echo '{"tool_input":{"file_path":"src/index.ts"}}' \
  | bash "$SCRIPT_DIR/approve-memory-write.sh" 2>&1) || true
assert_empty "approve: empty for non-memory path" "$OUTPUT"
teardown_tmpdir

# Test: passes through when file_path is missing
setup_tmpdir
OUTPUT=$(echo '{"tool_input":{}}' \
  | bash "$SCRIPT_DIR/approve-memory-write.sh" 2>&1) || true
assert_empty "approve: empty for missing file_path" "$OUTPUT"
teardown_tmpdir

# ════════════════════════════════════════════════════════════════════════════
echo "=== session-start.sh ==="
# ════════════════════════════════════════════════════════════════════════════

# Test: finds most recent session directory (lexicographic order)
setup_tmpdir
create_session_dir "session-2026-03-09-001" "---
date: 2026-03-09
session_id: aaa-111
context_at_log: 50%
---
## Current Work
First session work"

create_session_dir "session-2026-03-09-002" "---
date: 2026-03-09
session_id: bbb-222
context_at_log: 50%
---
## Current Work
Second session work"

OUTPUT=$(echo '{"session_id":"ccc-333"}' \
  | bash "$SCRIPT_DIR/session-start.sh" 2>&1)
assert_json_valid "session-start: valid JSON" "$OUTPUT"
assert_contains "session-start: finds session-002 (newest)" "$OUTPUT" "session-2026-03-09-002"
assert_contains "session-start: includes log content" "$OUTPUT" "Second session work"
assert_contains "session-start: includes continues instruction" "$OUTPUT" "continues:"
assert_not_contains "session-start: does NOT load session-001" "$OUTPUT" "First session work"
teardown_tmpdir

# Test: falls back to archive when no session dirs exist
setup_tmpdir
mkdir -p .claude/memory/archives/archive-2026-02-28
echo "Archive content from Feb" > .claude/memory/archives/archive-2026-02-28/archive-2026-02-28.md
OUTPUT=$(echo '{"session_id":"ccc-333"}' \
  | bash "$SCRIPT_DIR/session-start.sh" 2>&1)
assert_json_valid "session-start: valid JSON (archive fallback)" "$OUTPUT"
assert_contains "session-start: falls back to archive" "$OUTPUT" "archive-2026-02-28"
assert_contains "session-start: archive content" "$OUTPUT" "Archive content from Feb"
teardown_tmpdir

# Test: returns "start fresh" when nothing exists
setup_tmpdir
OUTPUT=$(echo '{"session_id":"ccc-333"}' \
  | bash "$SCRIPT_DIR/session-start.sh" 2>&1)
assert_json_valid "session-start: valid JSON (nothing found)" "$OUTPUT"
assert_contains "session-start: start fresh message" "$OUTPUT" "Start fresh"
teardown_tmpdir

# Test: exits silently with no session_id
setup_tmpdir
create_session_dir "session-2026-03-09-001" "some content"
OUTPUT=$(echo '{}' \
  | bash "$SCRIPT_DIR/session-start.sh" 2>&1)
assert_empty "session-start: empty when no session_id" "$OUTPUT"
teardown_tmpdir

# Test: exits silently when memory dir doesn't exist
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"
OUTPUT=$(echo '{"session_id":"ccc-333"}' \
  | bash "$SCRIPT_DIR/session-start.sh" 2>&1)
assert_empty "session-start: empty when no memory dir" "$OUTPUT"
cd /; rm -rf "$TMPDIR"

# Test: handles cross-day ordering (picks latest date, not latest counter)
setup_tmpdir
create_session_dir "session-2026-03-08-003" "---
date: 2026-03-08
---
## Current Work
Yesterday's work"

create_session_dir "session-2026-03-09-001" "---
date: 2026-03-09
---
## Current Work
Today's work"

OUTPUT=$(echo '{"session_id":"ccc-333"}' \
  | bash "$SCRIPT_DIR/session-start.sh" 2>&1)
assert_contains "session-start: picks 03-09-001 over 03-08-003" "$OUTPUT" "Today's work"
assert_not_contains "session-start: does not pick 03-08-003" "$OUTPUT" "Yesterday's work"
teardown_tmpdir

# ════════════════════════════════════════════════════════════════════════════
echo "=== archival.sh ==="
# ════════════════════════════════════════════════════════════════════════════

# Test: no output when < 5 session directories
setup_tmpdir
create_session_dir "session-2026-03-09-001" "log1"
create_session_dir "session-2026-03-09-002" "log2"
create_session_dir "session-2026-03-09-003" "log3"
create_session_dir "session-2026-03-09-004" "log4"
OUTPUT=$(echo '{}' | bash "$SCRIPT_DIR/archival.sh" 2>&1)
assert_empty "archival: no output for 4 dirs" "$OUTPUT"
teardown_tmpdir

# Test: triggers when exactly 5 session directories
setup_tmpdir
create_session_dir "session-2026-03-08-001" "log1"
create_session_dir "session-2026-03-09-001" "log2"
create_session_dir "session-2026-03-09-002" "log3"
create_session_dir "session-2026-03-09-003" "log4"
create_session_dir "session-2026-03-09-004" "log5"
OUTPUT=$(echo '{}' | bash "$SCRIPT_DIR/archival.sh" 2>&1)
assert_json_valid "archival: valid JSON for 5 dirs" "$OUTPUT"
assert_contains "archival: mentions archival needed" "$OUTPUT" "ARCHIVAL NEEDED"
# Should list 4 files to archive (all except newest)
assert_contains "archival: lists session-2026-03-08-001 log" "$OUTPUT" "session-2026-03-08-001/session-2026-03-08-001.md"
assert_contains "archival: lists session-2026-03-09-001 log" "$OUTPUT" "session-2026-03-09-001/session-2026-03-09-001.md"
assert_contains "archival: lists session-2026-03-09-002 log" "$OUTPUT" "session-2026-03-09-002/session-2026-03-09-002.md"
assert_contains "archival: lists session-2026-03-09-003 log" "$OUTPUT" "session-2026-03-09-003/session-2026-03-09-003.md"
# Newest should NOT be listed
assert_not_contains "archival: does NOT list newest (session-2026-03-09-004)" "$OUTPUT" "session-2026-03-09-004/session-2026-03-09-004.md"
# Should include archive target
assert_contains "archival: includes archive name" "$OUTPUT" "Archive name: archive-"
assert_contains "archival: includes archives directory path" "$OUTPUT" ".claude/memory/archives/archive-"
# Should mention directory deletion
assert_contains "archival: mentions rm -r" "$OUTPUT" "rm -r"
teardown_tmpdir

# Test: no output when memory dir doesn't exist
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"
OUTPUT=$(echo '{}' | bash "$SCRIPT_DIR/archival.sh" 2>&1)
assert_empty "archival: empty when no memory dir" "$OUTPUT"
cd /; rm -rf "$TMPDIR"

# Test: counts correctly with 6 directories
setup_tmpdir
create_session_dir "session-2026-03-07-001" "log1"
create_session_dir "session-2026-03-08-001" "log2"
create_session_dir "session-2026-03-09-001" "log3"
create_session_dir "session-2026-03-09-002" "log4"
create_session_dir "session-2026-03-09-003" "log5"
create_session_dir "session-2026-03-09-004" "log6"
OUTPUT=$(echo '{}' | bash "$SCRIPT_DIR/archival.sh" 2>&1)
assert_contains "archival: reports 5 to archive (6 total, newest preserved)" "$OUTPUT" "5 session directories"
teardown_tmpdir

# ════════════════════════════════════════════════════════════════════════════
echo "=== stop-check.sh ==="
# ════════════════════════════════════════════════════════════════════════════

# Test: allows stop when log exists for this session
setup_tmpdir
create_session_dir "session-2026-03-09-001" "---
date: 2026-03-09
session_id: test-session-123
context_at_log: 50%
---
## Current Work
Test work"

OUTPUT=$(echo '{"session_id":"test-session-123"}' \
  | bash "$SCRIPT_DIR/stop-check.sh" 2>&1)
EC=$?
assert_exit_code "stop-check: exit 0 when log exists" "$EC" 0
assert_empty "stop-check: no output when log exists" "$OUTPUT"
teardown_tmpdir

# Test: blocks when no log exists, creates directory
setup_tmpdir
OUTPUT=$(echo '{"session_id":"new-session-456"}' \
  | bash "$SCRIPT_DIR/stop-check.sh" 2>&1)
assert_json_valid "stop-check: valid JSON when blocking" "$OUTPUT"
assert_contains "stop-check: blocks with decision" "$OUTPUT" '"block"'
assert_contains "stop-check: includes session_id" "$OUTPUT" "new-session-456"
# Should create the session directory
assert_dir_exists "stop-check: creates session dir" ".claude/memory/session-$(date +%Y-%m-%d)-001"
teardown_tmpdir

# Test: increments counter correctly
setup_tmpdir
TODAY="$(date +%Y-%m-%d)"
create_session_dir "session-${TODAY}-001" "existing"
create_session_dir "session-${TODAY}-002" "existing"
OUTPUT=$(echo '{"session_id":"new-session-789"}' \
  | bash "$SCRIPT_DIR/stop-check.sh" 2>&1)
assert_contains "stop-check: uses counter 003" "$OUTPUT" "session-${TODAY}-003"
assert_dir_exists "stop-check: creates dir with counter 003" ".claude/memory/session-${TODAY}-003"
teardown_tmpdir

# Test: allows stop when stop_hook_active is true
setup_tmpdir
OUTPUT=$(echo '{"session_id":"test-session-123","stop_hook_active":true}' \
  | bash "$SCRIPT_DIR/stop-check.sh" 2>&1)
EC=$?
assert_exit_code "stop-check: exit 0 when stop_hook_active" "$EC" 0
assert_empty "stop-check: no output when stop_hook_active" "$OUTPUT"
teardown_tmpdir

# Test: exits silently with no session_id
setup_tmpdir
OUTPUT=$(echo '{}' \
  | bash "$SCRIPT_DIR/stop-check.sh" 2>&1)
EC=$?
assert_exit_code "stop-check: exit 0 when no session_id" "$EC" 0
assert_empty "stop-check: no output when no session_id" "$OUTPUT"
teardown_tmpdir

# Test: starts at 001 on a new day (no existing dirs for today)
setup_tmpdir
create_session_dir "session-2026-03-08-005" "yesterday"
OUTPUT=$(echo '{"session_id":"new-day-session"}' \
  | bash "$SCRIPT_DIR/stop-check.sh" 2>&1)
TODAY="$(date +%Y-%m-%d)"
assert_contains "stop-check: starts at 001 for new day" "$OUTPUT" "session-${TODAY}-001"
teardown_tmpdir

# Test: sets archival flag when 5+ directories exist
setup_tmpdir
create_session_dir "session-2026-03-09-001" "---
session_id: existing-sess
---"
create_session_dir "session-2026-03-09-002" "log"
create_session_dir "session-2026-03-09-003" "log"
create_session_dir "session-2026-03-09-004" "log"
create_session_dir "session-2026-03-09-005" "log"
# This session has a log, so stop is allowed, but archival flag should be set
OUTPUT=$(echo '{"session_id":"existing-sess"}' \
  | bash "$SCRIPT_DIR/stop-check.sh" 2>&1)
assert_file_exists "stop-check: archival flag set at 5 dirs" ".claude/memory/.archive-needed"
teardown_tmpdir

# ════════════════════════════════════════════════════════════════════════════
echo "=== Edge cases ==="
# ════════════════════════════════════════════════════════════════════════════

# Test: stop-check counter handles double-digit counters
setup_tmpdir
TODAY="$(date +%Y-%m-%d)"
create_session_dir "session-${TODAY}-009" "existing"
OUTPUT=$(echo '{"session_id":"counter-test"}' \
  | bash "$SCRIPT_DIR/stop-check.sh" 2>&1)
assert_contains "edge: counter increments 009 → 010" "$OUTPUT" "session-${TODAY}-010"
teardown_tmpdir

# Test: stop-check finds session_id inside a session directory (not flat file)
setup_tmpdir
create_session_dir "session-2026-03-09-001" "---
date: 2026-03-09
session_id: deeply-nested-id
context_at_log: 60%
---
## Current Work
Deep work"
OUTPUT=$(echo '{"session_id":"deeply-nested-id"}' \
  | bash "$SCRIPT_DIR/stop-check.sh" 2>&1)
EC=$?
assert_exit_code "edge: finds session_id in dir/file" "$EC" 0
assert_empty "edge: no output when session found in dir" "$OUTPUT"
teardown_tmpdir

# Test: session-start picks lexicographically latest across months
setup_tmpdir
create_session_dir "session-2026-02-28-005" "February content"
create_session_dir "session-2026-03-01-001" "---
---
## Current Work
March content"
OUTPUT=$(echo '{"session_id":"test"}' \
  | bash "$SCRIPT_DIR/session-start.sh" 2>&1)
assert_contains "edge: picks March over February" "$OUTPUT" "March content"
teardown_tmpdir

# Test: archival lists directories not files in its instruction
setup_tmpdir
create_session_dir "session-2026-03-09-001" "log"
create_session_dir "session-2026-03-09-002" "log"
create_session_dir "session-2026-03-09-003" "log"
create_session_dir "session-2026-03-09-004" "log"
create_session_dir "session-2026-03-09-005" "log"
OUTPUT=$(echo '{}' | bash "$SCRIPT_DIR/archival.sh" 2>&1)
# Should mention rm -r for directories, not rm for files
assert_contains "edge: archival mentions directory deletion" "$OUTPUT" "rm -r .claude/memory/"
assert_not_contains "edge: archival does NOT use flat file rm" "$OUTPUT" "rm .claude/memory/session-"
teardown_tmpdir

# Test: session-start handles session dir with missing log file gracefully
setup_tmpdir
mkdir -p ".claude/memory/session-2026-03-09-001"
# Directory exists but no log file inside
mkdir -p .claude/memory/archives/archive-2026-03-01
echo "Archive fallback content" > .claude/memory/archives/archive-2026-03-01/archive-2026-03-01.md
OUTPUT=$(echo '{"session_id":"test"}' \
  | bash "$SCRIPT_DIR/session-start.sh" 2>&1)
assert_contains "edge: falls back to archive when log missing from dir" "$OUTPUT" "Archive fallback content"
teardown_tmpdir

# Test: stop-check blocks with correct YAML template in reason
setup_tmpdir
OUTPUT=$(echo '{"session_id":"yaml-test-id"}' \
  | bash "$SCRIPT_DIR/stop-check.sh" 2>&1)
assert_contains "edge: block reason includes YAML template" "$OUTPUT" "session_id: yaml-test-id"
assert_contains "edge: block reason includes section headers" "$OUTPUT" "## Current Work"
assert_contains "edge: block reason includes Next Steps" "$OUTPUT" "## Next Steps"
teardown_tmpdir

# ════════════════════════════════════════════════════════════════════════════
# Results
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "════════════════════════════════════════"

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "\nFailures:${ERRORS}"
  echo ""
  exit 1
else
  echo "  All tests passed."
  exit 0
fi
