#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  orchestration_autoloop_regression.sh

What it validates:
  1) planner-inbox plan-backed item is promoted to developer-todo
  2) developer strict execution runs and returns planner-review evidence
  3) planner review auto-done closes ticket and archives record
  4) loop terminates at STOP_DONE with no actionable leftovers
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE_SCRIPT="$SCRIPT_DIR/orchestration_queue.sh"
AUTOLOOP_SCRIPT="$SCRIPT_DIR/orchestration_autoloop.sh"

if [[ ! -x "$QUEUE_SCRIPT" ]]; then
  echo "ERROR: missing executable queue helper: $QUEUE_SCRIPT" >&2
  exit 1
fi
if [[ ! -x "$AUTOLOOP_SCRIPT" ]]; then
  echo "ERROR: missing executable autoloop helper: $AUTOLOOP_SCRIPT" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
PROJECT_ROOT="$WORK_DIR/project"
RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$PROJECT_ROOT/$RUNTIME_ROOT/plans"

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

PLAN_FILE="$PROJECT_ROOT/$RUNTIME_ROOT/plans/autoloop-test.md"
cat > "$PLAN_FILE" <<'MD'
# Autoloop Test Plan

## PlanSpec v2
id: autoloop-test
owner: qa
risk: low
mode: strict
verify_commands:
  - test -f .sigee/.runtime/evidence/autoloop-marker/marker.txt
done_definition:
  - marker file exists

## TL;DR
> Autoloop regression validates strict execute+review cycle.

## Objective
- Business goal: validate queue orchestration loop reliability.
- Technical goal: ensure plan-backed ticket reaches done.

## Scope
### In Scope
- single plan-backed ticket lifecycle

### Out of Scope
- scientist path

## Constraints
- local shell only

## Assumptions
- strict runner is available

## Delivery Waves
### Wave 1 - Unblockers
- [ ] 1. Create marker
  - Targets: .sigee/.runtime/evidence/autoloop-marker/marker.txt
  - Expected behavior: marker file is created.
  - Execute: `mkdir -p .sigee/.runtime/evidence/autoloop-marker && printf "ok\n" > .sigee/.runtime/evidence/autoloop-marker/marker.txt`
  - Verification: `test -f .sigee/.runtime/evidence/autoloop-marker/marker.txt`

## Integration
- [ ] Integration check
  - Targets: .sigee/.runtime/evidence/autoloop-marker/marker.txt
  - Expected behavior: marker remains available.
  - Execute: `test -f .sigee/.runtime/evidence/autoloop-marker/marker.txt`
  - Verification: `test -f .sigee/.runtime/evidence/autoloop-marker/marker.txt`

## Final Verification
- Functional checks: marker path exists.
- Non-functional checks: none.
- Regression checks: queue lifecycle closure.
- DAG mandatory checks:
  - unit_normal_tests: 2 per scenario
  - unit_boundary_tests: 2 per scenario
  - unit_failure_tests: 2 per scenario
  - boundary_smoke_tests: 5 per scenario

## Rollout and Rollback
- Rollout: no-op
- Rollback: remove marker file
MD

run_queue init >/dev/null
run_queue add \
  --queue planner-inbox \
  --id LOOP-001 \
  --title "autoloop regression ticket" \
  --worker tech-planner \
  --source "plan:autoloop-test" \
  --status pending \
  --phase planned \
  --next-action "planner triage to developer execution" \
  --retry-budget 3 >/dev/null

AUTO_OUT="$(bash "$AUTOLOOP_SCRIPT" --project-root "$PROJECT_ROOT" --max-cycles 12 --no-progress-limit 2 2>&1)"
assert_contains "$AUTO_OUT" "AUTOLOOP_TERMINAL_STATUS:STOP_DONE" "autoloop terminal status"

MARKER_FILE="$PROJECT_ROOT/$RUNTIME_ROOT/evidence/autoloop-marker/marker.txt"
if [[ ! -f "$MARKER_FILE" ]]; then
  echo "ERROR: marker file missing after autoloop run: $MARKER_FILE" >&2
  exit 1
fi

ARCHIVE_FILE="$PROJECT_ROOT/$RUNTIME_ROOT/orchestration/archive/done-$(date -u '+%Y-%m').tsv"
if ! awk -F'\t' '$1=="LOOP-001"{found=1} END{exit(found?0:1)}' "$ARCHIVE_FILE"; then
  echo "ERROR: LOOP-001 not found in done archive after autoloop run" >&2
  exit 1
fi

for q in planner-inbox developer-todo planner-review scientist-todo blocked; do
  QF="$PROJECT_ROOT/$RUNTIME_ROOT/orchestration/queues/$q.tsv"
  if awk -F'\t' 'NR>1 && $2!="done"{exit 0} END{exit 1}' "$QF"; then
    echo "ERROR: queue not drained after autoloop run: $q" >&2
    exit 1
  fi
done

echo "orchestration_autoloop_regression passed: planner<->developer continuous loop to STOP_DONE"
