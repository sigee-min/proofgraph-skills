#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  orchestration_queue_regression.sh

What it validates:
  1) done-gate evidence_links delimiter compatibility (comma/semicolon/pipe mixed input)
  2) automatic escalation of retry-budget exhausted tickets on claim
  3) explicit reconcile-exhausted cleanup flow
  4) blocked triage view ordering (priority + aging)
  5) weekly retry summary auto-aggregation output
  6) next-prompt recommendation command output contract
  7) developer profile hint extraction contract on claim
  8) pending-plan auto-seed prevents false STOP_DONE
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE_SCRIPT="$SCRIPT_DIR/orchestration_queue.sh"
USER_FACING_GUARD_SCRIPT="$SCRIPT_DIR/user_facing_guard.sh"

if [[ ! -x "$QUEUE_SCRIPT" ]]; then
  echo "ERROR: missing executable queue helper: $QUEUE_SCRIPT" >&2
  exit 1
fi
if [[ ! -f "$USER_FACING_GUARD_SCRIPT" ]]; then
  echo "ERROR: missing shared user-facing guard: $USER_FACING_GUARD_SCRIPT" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$USER_FACING_GUARD_SCRIPT"

WORK_DIR="$(mktemp -d)"
PROJECT_ROOT="$WORK_DIR/project"
RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$PROJECT_ROOT"
EXPECTED_RETRY_NEXT_ACTION="planner triage required: retry budget exhausted; decide scope_down, reroute, budget_increase, or close"

run_queue() {
  bash "$QUEUE_SCRIPT" "$@" --project-root "$PROJECT_ROOT"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "$needle" <<<"$haystack"; then
    echo "ERROR: assertion failed ($label): missing '$needle'" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "$needle" <<<"$haystack"; then
    echo "ERROR: assertion failed ($label): unexpected '$needle'" >&2
    exit 1
  fi
}

assert_match_count() {
  local haystack="$1"
  local pattern="$2"
  local expected="$3"
  local label="$4"
  local count
  count="$(printf "%s\n" "$haystack" | grep -Ec "$pattern" || true)"
  if [[ "$count" -ne "$expected" ]]; then
    echo "ERROR: assertion failed ($label): expected $expected matches for /$pattern/, got $count" >&2
    exit 1
  fi
}

assert_no_internal_leak() {
  local haystack="$1"
  local label="$2"
  if ! sigee_assert_no_internal_leak "$haystack" "$label"; then
    exit 1
  fi
}

run_queue init >/dev/null

RESULTS_DIR="$PROJECT_ROOT/$RUNTIME_ROOT/evidence/regression"
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/verification-results.tsv"
cat > "$RESULTS_FILE" <<'TSV'
suite	case	stage	result
queue	done_gate_mixed	verify	PASS
TSV

# 1) mixed delimiter acceptance in done-gate evidence parser
run_queue add \
  --queue planner-review \
  --id DONE-DELIM-001 \
  --worker developer \
  --title "done gate mixed delimiter regression" \
  --source "regression" \
  --phase evidence_collected \
  --attempt-count 1 \
  --retry-budget 3 >/dev/null

MIXED_EVIDENCE="garbage,.sigee/.runtime/evidence/does-not-exist.tsv|.sigee/.runtime/evidence/regression/verification-results.tsv;ignored"
DONE_OUT="$(run_queue move \
  --id DONE-DELIM-001 \
  --from planner-review \
  --to done \
  --status done \
  --worker tech-planner \
  --actor tech-planner \
  --evidence "$MIXED_EVIDENCE" \
  --next-action "none" 2>&1)"
assert_contains "$DONE_OUT" "다음 실행 프롬프트" "done transition next prompt block"
assert_match_count "$DONE_OUT" '^다음 실행 프롬프트$' 1 "done transition next prompt title count"
assert_match_count "$DONE_OUT" '^```md$' 1 "done transition markdown fence open count"
assert_match_count "$DONE_OUT" '^```$' 1 "done transition markdown fence close count"
assert_not_contains "$DONE_OUT" '$tech-planner' "done transition user-facing hides internal target"

ARCHIVE_FILE="$PROJECT_ROOT/$RUNTIME_ROOT/orchestration/archive/done-$(date -u '+%Y-%m').tsv"
if ! awk -F'\t' '$1=="DONE-DELIM-001"{found=1} END{exit(found?0:1)}' "$ARCHIVE_FILE"; then
  echo "ERROR: done-gate mixed delimiter regression failed to archive DONE-DELIM-001" >&2
  exit 1
fi

# 2) automatic escalation when claim sees exhausted retry budget
run_queue add \
  --queue developer-todo \
  --id RETRY-AUTO-001 \
  --worker developer \
  --title "auto escalation candidate" \
  --source "regression" \
  --status pending \
  --phase ready \
  --attempt-count 3 \
  --retry-budget 3 >/dev/null

CLAIM_OUT="$(run_queue claim --queue developer-todo --worker tech-developer --actor tech-developer 2>&1 || true)"
assert_contains "$CLAIM_OUT" "NO_PENDING:developer-todo" "claim output after auto escalation"
assert_not_contains "$CLAIM_OUT" "NO_RETRY_BUDGET" "claim output should use escalation path"
assert_contains "$CLAIM_OUT" "AUTO_ESCALATED_RETRY_EXHAUSTED:developer-todo:1" "claim output auto escalation count"
assert_contains "$CLAIM_OUT" "AUTO_ESCALATED_NEXT_ACTION:$EXPECTED_RETRY_NEXT_ACTION" "claim output escalation next action"

BLOCKED_FILE="$PROJECT_ROOT/$RUNTIME_ROOT/orchestration/queues/blocked.tsv"
if ! awk -F'\t' '
  $1=="RETRY-AUTO-001" {
    if ($2!="blocked") exit 1
    if ($12!="dependency_blocked") exit 1
    if ($7 !~ /auto-detoured to blocked/) exit 1
    if ($8!="'"$EXPECTED_RETRY_NEXT_ACTION"'") exit 1
    if ($9 !~ /^released:/) exit 1
    found=1
  }
  END { exit(found?0:1) }
' "$BLOCKED_FILE"; then
  echo "ERROR: auto escalation regression failed for RETRY-AUTO-001" >&2
  exit 1
fi

# 3) explicit reconcile-exhausted cleanup flow
run_queue add \
  --queue scientist-todo \
  --id RETRY-RECON-001 \
  --worker scientist \
  --title "explicit reconcile candidate" \
  --source "regression" \
  --status pending \
  --phase ready \
  --attempt-count 2 \
  --retry-budget 2 >/dev/null

RECON_OUT="$(run_queue reconcile-exhausted --all --actor tech-planner 2>&1)"
assert_contains "$RECON_OUT" "RECONCILED_TOTAL:" "reconcile summary output"

if ! awk -F'\t' '$1=="RETRY-RECON-001"{found=1} END{exit(found?0:1)}' "$BLOCKED_FILE"; then
  echo "ERROR: explicit reconcile flow failed for RETRY-RECON-001" >&2
  exit 1
fi
if ! awk -F'\t' '
  $1=="RETRY-RECON-001" {
    if ($12!="dependency_blocked") exit 1
    if ($7 !~ /auto-detoured to blocked/) exit 1
    if ($8!="'"$EXPECTED_RETRY_NEXT_ACTION"'") exit 1
    found=1
  }
  END { exit(found?0:1) }
' "$BLOCKED_FILE"; then
  echo "ERROR: explicit reconcile message consistency failed for RETRY-RECON-001" >&2
  exit 1
fi

# 4) blocked triage view (priority + oldest-first aging)
run_queue add \
  --queue blocked \
  --id TRIAGE-AGE-OLD \
  --worker developer \
  --title "triage aging old" \
  --source "regression" \
  --status blocked \
  --phase ready \
  --error-class soft_fail \
  --attempt-count 1 \
  --retry-budget 3 >/dev/null
sleep 1
run_queue add \
  --queue blocked \
  --id TRIAGE-AGE-NEW \
  --worker developer \
  --title "triage aging new" \
  --source "regression" \
  --status blocked \
  --phase ready \
  --error-class soft_fail \
  --attempt-count 1 \
  --retry-budget 3 >/dev/null
run_queue add \
  --queue blocked \
  --id TRIAGE-P1-001 \
  --worker developer \
  --title "triage p1 hard fail" \
  --source "regression" \
  --status blocked \
  --phase ready \
  --error-class hard_fail \
  --attempt-count 1 \
  --retry-budget 3 >/dev/null

TRIAGE_OUT="$(run_queue triage-blocked --limit 20 2>&1)"
assert_contains "$TRIAGE_OUT" $'priority\tage_days\tid' "triage header"
assert_contains "$TRIAGE_OUT" "TRIAGE-P1-001" "triage includes p1 ticket"
assert_contains "$TRIAGE_OUT" "TRIAGE-AGE-OLD" "triage includes old ticket"
assert_contains "$TRIAGE_OUT" "TRIAGE-AGE-NEW" "triage includes new ticket"

line_p1="$(printf "%s\n" "$TRIAGE_OUT" | nl -ba | awk '/TRIAGE-P1-001/{print $1; exit}')"
line_old="$(printf "%s\n" "$TRIAGE_OUT" | nl -ba | awk '/TRIAGE-AGE-OLD/{print $1; exit}')"
line_new="$(printf "%s\n" "$TRIAGE_OUT" | nl -ba | awk '/TRIAGE-AGE-NEW/{print $1; exit}')"
if [[ -z "$line_p1" || -z "$line_old" || -z "$line_new" ]]; then
  echo "ERROR: triage ordering assertions missing line numbers" >&2
  exit 1
fi
if [[ "$line_p1" -ge "$line_old" ]]; then
  echo "ERROR: triage priority ordering failed (P1 should appear before P2)." >&2
  exit 1
fi
if [[ "$line_old" -ge "$line_new" ]]; then
  echo "ERROR: triage aging ordering failed (older ticket should appear first)." >&2
  exit 1
fi

# 5) weekly retry summary generation
SUMMARY_OUT="$(run_queue weekly-retry-summary --weeks 1 2>&1)"
assert_contains "$SUMMARY_OUT" "WEEKLY_SUMMARY_FILE:" "weekly summary output path"
SUMMARY_FILE="$(printf "%s\n" "$SUMMARY_OUT" | sed -n 's/^WEEKLY_SUMMARY_FILE://p' | head -n1)"
if [[ -z "$SUMMARY_FILE" || ! -f "$SUMMARY_FILE" ]]; then
  echo "ERROR: weekly summary file missing: $SUMMARY_FILE" >&2
  exit 1
fi
if ! rg -q "retry_budget_exhausted_events|open_blocked_exhausted_count" "$SUMMARY_FILE"; then
  echo "ERROR: weekly summary content missing required metrics" >&2
  exit 1
fi

# 6) next-prompt command output contract
NEXT_OUT="$(run_queue next-prompt 2>&1)"
assert_contains "$NEXT_OUT" "NEXT_PROMPT_TARGET:" "next-prompt target output"
assert_contains "$NEXT_OUT" "NEXT_PROMPT_QUEUE:" "next-prompt queue output"
assert_contains "$NEXT_OUT" "NEXT_PROMPT_REASON:" "next-prompt reason output"
assert_contains "$NEXT_OUT" "다음 실행 프롬프트" "next-prompt markdown block"
assert_match_count "$NEXT_OUT" '^다음 실행 프롬프트$' 1 "next-prompt machine title count"
assert_match_count "$NEXT_OUT" '^```md$' 1 "next-prompt machine markdown fence open count"
assert_match_count "$NEXT_OUT" '^```$' 1 "next-prompt machine markdown fence close count"

NEXT_USER_OUT="$(run_queue next-prompt --user-facing 2>&1)"
assert_match_count "$NEXT_USER_OUT" '^다음 실행 프롬프트$' 1 "next-prompt user title count"
assert_match_count "$NEXT_USER_OUT" '^```md$' 1 "next-prompt user markdown fence open count"
assert_match_count "$NEXT_USER_OUT" '^```$' 1 "next-prompt user markdown fence close count"
assert_match_count "$NEXT_USER_OUT" '^왜 지금 이 작업인가:' 1 "next-prompt user rationale line count"
assert_no_internal_leak "$NEXT_USER_OUT" "user-facing next-prompt leak check"

LOOP_USER_OUT="$(run_queue loop-status --user-facing 2>&1)"
assert_match_count "$LOOP_USER_OUT" '^요약:' 1 "loop-status user summary count"
assert_no_internal_leak "$LOOP_USER_OUT" "user-facing loop-status leak check"

# 7) developer profile hint extraction on claim
run_queue add \
  --queue developer-todo \
  --id PROFILE-HINT-001 \
  --worker developer \
  --title "profile hint next_action precedence" \
  --source "regression" \
  --status pending \
  --phase ready \
  --note "profile=backend-api" \
  --next-action "profile=refactoring-specialist cleanup residue" \
  --attempt-count 0 \
  --retry-budget 3 >/dev/null
PROFILE_OUT_1="$(run_queue claim --queue developer-todo --worker tech-developer --actor tech-developer 2>&1 || true)"
assert_contains "$PROFILE_OUT_1" "CLAIM_PROFILE_HINT:refactoring-specialist" "profile hint from next_action"
assert_contains "$PROFILE_OUT_1" "CLAIM_PROFILE_SOURCE:next_action" "profile source next_action"

run_queue add \
  --queue developer-todo \
  --id PROFILE-HINT-002 \
  --worker developer \
  --title "profile hint default fallback" \
  --source "regression" \
  --status pending \
  --phase ready \
  --attempt-count 0 \
  --retry-budget 3 >/dev/null
PROFILE_OUT_2="$(run_queue claim --queue developer-todo --worker tech-developer --actor tech-developer 2>&1 || true)"
assert_contains "$PROFILE_OUT_2" "CLAIM_PROFILE_HINT:generalist" "profile fallback default"
assert_contains "$PROFILE_OUT_2" "CLAIM_PROFILE_SOURCE:default" "profile source default"

# 8) pending plan backlog auto-seeds planner-inbox (prevents false STOP_DONE)
PLAN_SYNC_ROOT="$WORK_DIR/project-plan-sync"
mkdir -p "$PLAN_SYNC_ROOT/$RUNTIME_ROOT/plans"
cat > "$PLAN_SYNC_ROOT/$RUNTIME_ROOT/plans/plan-sync-test.md" <<'MD'
id: PLAN-SYNC-001

## Delivery Waves
- [ ] Implement intent-first web MVP
MD

PLAN_LOOP_OUT="$(bash "$QUEUE_SCRIPT" loop-status --project-root "$PLAN_SYNC_ROOT" 2>&1)"
assert_contains "$PLAN_LOOP_OUT" "LOOP_STATUS:CONTINUE" "plan auto-seed should keep loop running"

PLAN_INBOX_FILE="$PLAN_SYNC_ROOT/$RUNTIME_ROOT/orchestration/queues/planner-inbox.tsv"
if ! awk -F'\t' '$5=="plan:PLAN-SYNC-001"{found=1} END{exit(found?0:1)}' "$PLAN_INBOX_FILE"; then
  echo "ERROR: pending plan auto-seed did not create planner-inbox entry for PLAN-SYNC-001" >&2
  exit 1
fi

PLAN_NEXT_OUT="$(bash "$QUEUE_SCRIPT" next-prompt --project-root "$PLAN_SYNC_ROOT" 2>&1)"
assert_contains "$PLAN_NEXT_OUT" "NEXT_PROMPT_TARGET:tech-planner" "plan auto-seed next target"
assert_contains "$PLAN_NEXT_OUT" "NEXT_PROMPT_QUEUE:planner-inbox" "plan auto-seed next queue"

PLAN_NEXT_USER_OUT="$(bash "$QUEUE_SCRIPT" next-prompt --user-facing --project-root "$PLAN_SYNC_ROOT" 2>&1)"
assert_match_count "$PLAN_NEXT_USER_OUT" '^왜 지금 이 작업인가:' 1 "plan auto-seed user rationale line count"
assert_no_internal_leak "$PLAN_NEXT_USER_OUT" "plan auto-seed user-facing next-prompt leak check"

PLAN_LOOP_USER_OUT="$(bash "$QUEUE_SCRIPT" loop-status --user-facing --project-root "$PLAN_SYNC_ROOT" 2>&1)"
assert_match_count "$PLAN_LOOP_USER_OUT" '^요약:' 1 "plan auto-seed user loop-status summary count"
assert_no_internal_leak "$PLAN_LOOP_USER_OUT" "plan auto-seed user-facing loop-status leak check"

echo "orchestration_queue_regression passed: delimiter-compat + auto-escalation + reconcile-cleanup + triage + weekly-summary + next-prompt + profile-hint-claim + pending-plan-auto-seed"
