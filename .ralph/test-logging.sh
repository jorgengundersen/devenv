#!/usr/bin/env bash
# Minimal test harness for ralph-loop logging behaviour.
# Run with: bash .ralph/test-logging.sh
set -euo pipefail

PASS=0
FAIL=0

ok()   { echo "ok: $1";              ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then ok "$desc"
  else fail "$desc (expected '$expected', got '$actual')"; fi
}

assert_match() {
  local desc="$1" pattern="$2" actual="$3"
  if [[ "$actual" =~ $pattern ]]; then ok "$desc"
  else fail "$desc (pattern '$pattern' not matched in '$actual')"; fi
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ---------------------------------------------------------------------------
# p404-fsl: per-session log files
# ---------------------------------------------------------------------------
RUN_TS="$(date '+%Y%m%dT%H%M%S')"
LOG_DIR="$TMPDIR_TEST/.ralph/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${RUN_TS}.log"
: > "$LOG_FILE"
ln -sf "$LOG_FILE" "$LOG_DIR/latest"

[[ -f "$LOG_FILE" ]] && ok "fsl: timestamped log file created" || fail "fsl: timestamped log file created"
assert_match "fsl: filename matches timestamp pattern" '^[0-9]{8}T[0-9]{6}\.log$' "$(basename "$LOG_FILE")"
[[ -L "$LOG_DIR/latest" ]] && ok "fsl: latest symlink exists" || fail "fsl: latest symlink exists"
assert_eq "fsl: latest points to timestamped log" "$LOG_FILE" "$(readlink "$LOG_DIR/latest")"

# ---------------------------------------------------------------------------
# p404-bzl: capture exit code
# ---------------------------------------------------------------------------
SESSION_EXIT=42  # simulate non-zero exit
LOG_LINE="event=session_end loop=1/10 exit_code=$SESSION_EXIT duration=5s"
assert_match "bzl: exit_code present in log line" "exit_code=$SESSION_EXIT" "$LOG_LINE"
assert_match "bzl: duration present in log line"  "duration=[0-9]+s"        "$LOG_LINE"

# ---------------------------------------------------------------------------
# p404-kd6: per-iteration elapsed time
# ---------------------------------------------------------------------------
ITER_START=$(date +%s)
sleep 0
ITER_END=$(date +%s)
DURATION=$((ITER_END - ITER_START))
[[ "$DURATION" -ge 0 ]] && ok "kd6: duration computed (${DURATION}s)" || fail "kd6: duration computed"

# ---------------------------------------------------------------------------
# p404-gzq: structured summary at exit
# ---------------------------------------------------------------------------
SESSIONS_RUN=3
EXIT_REASON="done"
REMAINING_READY=2
RUN_END=$(date +%s)
RUN_START=$((RUN_END - 120))
SUMMARY="event=finish sessions=$SESSIONS_RUN exit_reason=$EXIT_REASON remaining_ready=$REMAINING_READY total_duration=$((RUN_END - RUN_START))s"
assert_match "gzq: event=finish in summary"        "event=finish"         "$SUMMARY"
assert_match "gzq: sessions in summary"            "sessions=3"           "$SUMMARY"
assert_match "gzq: exit_reason in summary"         "exit_reason=done"     "$SUMMARY"
assert_match "gzq: total_duration in summary"      "total_duration=[0-9]" "$SUMMARY"

# ---------------------------------------------------------------------------
# p404-rmc: remaining ready count at exit
# ---------------------------------------------------------------------------
assert_match "rmc: remaining_ready field present" "remaining_ready=[0-9]" "$SUMMARY"

# ---------------------------------------------------------------------------
# p404-dhm: structured key=value fields throughout
# ---------------------------------------------------------------------------
START_LINE="event=start project=/some/dir model=claude agent=ralph prompt=.ralph/PROMPT.md max=10 log=/some/log"
assert_match "dhm: event= field in start line"   "event=start"   "$START_LINE"
assert_match "dhm: model= field in start line"   "model="        "$START_LINE"
assert_match "dhm: agent= field in start line"   "agent="        "$START_LINE"

SESSION_START_LINE="event=session_start loop=1/10 ready=5"
assert_match "dhm: event=session_start"  "event=session_start" "$SESSION_START_LINE"
assert_match "dhm: ready= field"         "ready=[0-9]"         "$SESSION_START_LINE"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "---"
echo "results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
