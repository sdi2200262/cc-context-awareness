#!/usr/bin/env bash
# Automated test suite for cc-context-awareness
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS="${ROOT_DIR}/plugins/context-awareness/scripts"
TEST_SESSION="test-session-$$"
TMP_DIR="/tmp"
export CC_CONTEXT_CONFIG="${SCRIPTS}/config.default.json"

cleanup() {
  rm -f "${TMP_DIR}/.cc-ctx-pct-${TEST_SESSION}"
  rm -f "${TMP_DIR}/.cc-ctx-fired-${TEST_SESSION}"
  rm -f "${TMP_DIR}/.cc-ctx-compacted-${TEST_SESSION}"
}
trap cleanup EXIT
cleanup

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; exit 1; }

echo "Running cc-context-awareness test suite..."

# 1. Manifest and config syntax
echo "1. Validating JSON manifests and configs..."
jq . "${ROOT_DIR}/.claude-plugin/marketplace.json" >/dev/null || fail "marketplace.json invalid"
jq . "${ROOT_DIR}/plugins/context-awareness/.claude-plugin/plugin.json" >/dev/null || fail "plugin.json invalid"
jq . "${ROOT_DIR}/plugins/context-awareness/hooks/hooks.json" >/dev/null || fail "hooks.json invalid"
jq . "${SCRIPTS}/config.default.json" >/dev/null || fail "config.default.json invalid"
pass "All JSON files are valid"

# 2. bridge.sh execution
echo "2. Testing bridge.sh..."
# Test standalone extraction
INPUT_JSON='{"session_id":"'"${TEST_SESSION}"'","context_window":{"used_percentage":82.7}}'
echo "${INPUT_JSON}" | "${SCRIPTS}/bridge.sh" >/dev/null
[[ -f "${TMP_DIR}/.cc-ctx-pct-${TEST_SESSION}" ]] || fail "bridge.sh failed to create pct file"
PCT_VAL="$(cat "${TMP_DIR}/.cc-ctx-pct-${TEST_SESSION}")"
[[ "${PCT_VAL}" == "82" ]] || fail "bridge.sh did not floor percentage correctly (got ${PCT_VAL}, expected 82)"
pass "bridge.sh extracts and floors percentage"

# Test pipe pass-through
PIPED_OUT="$(echo "${INPUT_JSON}" | "${SCRIPTS}/bridge.sh" | jq -r '.session_id')"
[[ "${PIPED_OUT}" == "${TEST_SESSION}" ]] || fail "bridge.sh failed to pass JSON downstream"
pass "bridge.sh passes through JSON when piped"

# 3. check-thresholds.sh evaluation
echo "3. Testing check-thresholds.sh..."
# Test below threshold (50%)
echo "50" > "${TMP_DIR}/.cc-ctx-pct-${TEST_SESSION}"
BELOW_OUT="$(echo '{"session_id":"'"${TEST_SESSION}"'"}' | "${SCRIPTS}/check-thresholds.sh")"
[[ -z "${BELOW_OUT}" ]] || fail "check-thresholds.sh fired below threshold"
pass "check-thresholds.sh does not fire below threshold"

# Test at threshold (80%)
echo "80" > "${TMP_DIR}/.cc-ctx-pct-${TEST_SESSION}"
AT_OUT="$(echo '{"session_id":"'"${TEST_SESSION}"'"}' | "${SCRIPTS}/check-thresholds.sh")"
[[ -n "${AT_OUT}" ]] || fail "check-thresholds.sh failed to fire at 80%"
echo "${AT_OUT}" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null || fail "invalid additionalContext structure"
pass "check-thresholds.sh fires at threshold with valid hookSpecificOutput"

# Test placeholder interpolation
MSG="$(echo "${AT_OUT}" | jq -r '.hookSpecificOutput.additionalContext')"
[[ "${MSG}" == *"80%"* && "${MSG}" == *"20%"* ]] || fail "placeholders not properly interpolated"
pass "check-thresholds.sh interpolates {percentage} and {remaining}"

# Test repeat prevention
REPEAT_OUT="$(echo '{"session_id":"'"${TEST_SESSION}"'"}' | "${SCRIPTS}/check-thresholds.sh")"
[[ -z "${REPEAT_OUT}" ]] || fail "check-thresholds.sh fired twice for same tier"
pass "check-thresholds.sh honors repeat_mode (fired tier remembered)"

# 4. reset.sh compaction handling
echo "4. Testing reset.sh..."
echo '{"session_id":"'"${TEST_SESSION}"'"}' | "${SCRIPTS}/reset.sh"
[[ ! -f "${TMP_DIR}/.cc-ctx-pct-${TEST_SESSION}" ]] || fail "reset.sh failed to remove pct file"
[[ ! -f "${TMP_DIR}/.cc-ctx-fired-${TEST_SESSION}" ]] || fail "reset.sh failed to remove fired file"
[[ -f "${TMP_DIR}/.cc-ctx-compacted-${TEST_SESSION}" ]] || fail "reset.sh failed to plant compaction marker"
pass "reset.sh cleans state and plants compaction marker"

# 5. Post-compaction re-fire
echo "5. Testing post-compaction re-evaluation..."
echo "85" > "${TMP_DIR}/.cc-ctx-pct-${TEST_SESSION}"
POST_OUT="$(echo '{"session_id":"'"${TEST_SESSION}"'"}' | "${SCRIPTS}/check-thresholds.sh")"
[[ -n "${POST_OUT}" ]] || fail "check-thresholds.sh did not re-fire after compaction reset"
[[ ! -f "${TMP_DIR}/.cc-ctx-compacted-${TEST_SESSION}" ]] || fail "compaction marker was not consumed"
pass "Compaction marker consumed and threshold cleanly re-fires"

echo ""
echo "All tests passed successfully!"
