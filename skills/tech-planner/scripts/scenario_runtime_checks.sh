#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scenario_runtime_checks.sh --scenario <scenario-id> --check <check-id> [--project-root <path>]

Purpose:
  Execute runtime-result checks for DAG scenario contracts.
  This script intentionally avoids string-only assertions and validates behavior through command execution outcomes.

Examples:
  scenario_runtime_checks.sh --scenario orchestration_state_lifecycle --check lifecycle_defaults
  scenario_runtime_checks.sh --scenario orchestration_observability --check dag_observability_artifacts
USAGE
}

SCENARIO_ID=""
CHECK_ID=""
PROJECT_ROOT=""
RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"

if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO_ID="${2:-}"
      shift 2
      ;;
    --check)
      CHECK_ID="${2:-}"
      shift 2
      ;;
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$SCENARIO_ID" || -z "$CHECK_ID" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE_SCRIPT="$SCRIPT_DIR/orchestration_queue.sh"
ARCHIVE_SCRIPT="$SCRIPT_DIR/orchestration_archive.sh"
QUEUE_REGRESSION_SCRIPT="$SCRIPT_DIR/orchestration_queue_regression.sh"
AUTOLOOP_REGRESSION_SCRIPT="$SCRIPT_DIR/orchestration_autoloop_regression.sh"
USER_FACING_GUARD_SCRIPT="$SCRIPT_DIR/user_facing_guard.sh"
DAG_BUILD_SCRIPT="$SCRIPT_DIR/../../tech-developer/scripts/dag_build.sh"
DAG_RUN_SCRIPT="$SCRIPT_DIR/../../tech-developer/scripts/dag_run.sh"
DAG_STRESS_SCRIPT="$SCRIPT_DIR/../../tech-developer/scripts/dag_stress.sh"
DAG_DUAL_LAYER_SCRIPT="$SCRIPT_DIR/../../tech-developer/scripts/dag_dual_layer_regression.sh"

for required in \
  "$QUEUE_SCRIPT" \
  "$ARCHIVE_SCRIPT" \
  "$USER_FACING_GUARD_SCRIPT" \
  "$DAG_BUILD_SCRIPT" \
  "$DAG_RUN_SCRIPT" \
  "$DAG_STRESS_SCRIPT" \
  "$DAG_DUAL_LAYER_SCRIPT"; do
  if [[ ! -x "$required" ]]; then
    echo "ERROR: required executable not found: $required" >&2
    exit 1
  fi
done
# shellcheck disable=SC1090
source "$USER_FACING_GUARD_SCRIPT"

resolve_project_root() {
  local candidate="${1:-$(pwd)}"
  if [[ ! -d "$candidate" ]]; then
    echo "ERROR: project root not found: $candidate" >&2
    exit 1
  fi
  if git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$candidate" rev-parse --show-toplevel
  else
    (cd "$candidate" && pwd)
  fi
}

PROJECT_ROOT="$(resolve_project_root "$PROJECT_ROOT")"

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

extract_json_string_field() {
  local file="$1"
  local key="$2"
  sed -nE "s/^[[:space:]]*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*$/\\1/p" "$file" | head -n1
}

extract_json_number_field() {
  local file="$1"
  local key="$2"
  sed -nE "s/^[[:space:]]*\"${key}\"[[:space:]]*:[[:space:]]*([0-9]+).*$/\\1/p" "$file" | head -n1
}

new_temp_project() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/project"
  printf "%s" "$tmp/project"
}

run_queue() {
  local project_root="$1"
  shift
  SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$QUEUE_SCRIPT" "$@" --project-root "$project_root"
}

create_pass_evidence() {
  local project_root="$1"
  local evidence_rel="$RUNTIME_ROOT/evidence/runtime-check/verification-results.tsv"
  local evidence_abs="$project_root/$evidence_rel"
  mkdir -p "$(dirname "$evidence_abs")"
  cat > "$evidence_abs" <<'TSV'
suite	case	stage	result
runtime	pass	verify	PASS
TSV
  printf "%s" "$evidence_rel"
}

add_review_ticket() {
  local project_root="$1"
  local id="$2"
  run_queue "$project_root" add \
    --queue planner-review \
    --id "$id" \
    --worker tech-developer \
    --title "runtime check $id" \
    --source "scenario-runtime-check" \
    --status review \
    --phase evidence_collected \
    --attempt-count 1 \
    --retry-budget 3 >/dev/null
}

assert_ticket_in_archive() {
  local project_root="$1"
  local id="$2"
  local archive_file="$project_root/$RUNTIME_ROOT/orchestration/archive/done-$(date -u '+%Y-%m').tsv"
  if [[ ! -f "$archive_file" ]]; then
    echo "ERROR: archive file missing: $archive_file" >&2
    exit 1
  fi
  if ! awk -F'\t' -v id="$id" 'NR>1 && $1==id{found=1} END{exit(found?0:1)}' "$archive_file"; then
    echo "ERROR: archive missing expected id '$id'" >&2
    exit 1
  fi
}

check_lifecycle_defaults() {
  local project
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null
  run_queue "$project" add \
    --queue planner-inbox \
    --id LIF-001 \
    --title "lifecycle defaults" \
    --worker tech-planner \
    --source "scenario-runtime-check" >/dev/null

  local inbox_file="$project/$RUNTIME_ROOT/orchestration/queues/planner-inbox.tsv"
  awk -F'\t' 'NR>1 && $1=="LIF-001" {
    if ($2!="pending") exit 1
    if ($11!="planned") exit 1
    if ($12!="none") exit 1
    if ($13!="0") exit 1
    if ($14!="3") exit 1
    found=1
  }
  END { exit(found?0:1) }
  ' "$inbox_file"
}

check_lifecycle_claim_transition() {
  local project
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null
  run_queue "$project" add \
    --queue developer-todo \
    --id LIF-002 \
    --title "claim transition" \
    --worker tech-developer \
    --source "scenario-runtime-check" \
    --status pending \
    --phase ready >/dev/null

  local claim_out
  claim_out="$(run_queue "$project" claim --queue developer-todo --worker tech-developer --actor tech-developer 2>&1)"
  assert_contains "$claim_out" "LIF-002" "claim output contains id"

  local dev_file="$project/$RUNTIME_ROOT/orchestration/queues/developer-todo.tsv"
  awk -F'\t' 'NR>1 && $1=="LIF-002" {
    if ($2!="in_progress") exit 1
    if ($11!="running") exit 1
    if ($13!="1") exit 1
    if ($9 !~ /^held:/) exit 1
    found=1
  }
  END { exit(found?0:1) }
  ' "$dev_file"
}

check_done_gate_pass() {
  local project evidence_rel done_out
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null
  evidence_rel="$(create_pass_evidence "$project")"
  add_review_ticket "$project" "DONE-001"

  done_out="$(run_queue "$project" move \
    --id DONE-001 \
    --from planner-review \
    --to done \
    --status done \
    --worker tech-planner \
    --actor tech-planner \
    --evidence "$evidence_rel" 2>&1)"

  assert_contains "$done_out" "다음 실행 프롬프트" "done transition emits prompt"
  assert_ticket_in_archive "$project" "DONE-001"
}

check_done_gate_requires_evidence() {
  local project
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null
  add_review_ticket "$project" "DONE-002"

  if run_queue "$project" move \
      --id DONE-002 \
      --from planner-review \
      --to done \
      --status done \
      --worker tech-planner \
      --actor tech-planner \
      --evidence "none" >/dev/null 2>&1; then
    echo "ERROR: done transition unexpectedly succeeded without evidence" >&2
    exit 1
  fi
}

check_done_gate_planner_only() {
  local project evidence_rel
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null
  evidence_rel="$(create_pass_evidence "$project")"
  add_review_ticket "$project" "DONE-003"

  if run_queue "$project" move \
      --id DONE-003 \
      --from planner-review \
      --to done \
      --status done \
      --worker tech-developer \
      --actor tech-developer \
      --evidence "$evidence_rel" >/dev/null 2>&1; then
    echo "ERROR: done transition unexpectedly succeeded for non-planner actor" >&2
    exit 1
  fi
}

check_status_done_guard() {
  local project
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null
  run_queue "$project" add \
    --queue planner-inbox \
    --id GUARD-001 \
    --title "status guard" \
    --worker tech-planner \
    --source "scenario-runtime-check" >/dev/null

  if run_queue "$project" move \
      --id GUARD-001 \
      --from planner-inbox \
      --to developer-todo \
      --status done \
      --worker tech-developer >/dev/null 2>&1; then
    echo "ERROR: status guard failed; non-done queue accepted status=done" >&2
    exit 1
  fi
}

check_invalid_phase_guard() {
  local project
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null
  run_queue "$project" add \
    --queue planner-inbox \
    --id GUARD-002 \
    --title "phase guard" \
    --worker tech-planner \
    --source "scenario-runtime-check" >/dev/null

  if run_queue "$project" move \
      --id GUARD-002 \
      --from planner-inbox \
      --to developer-todo \
      --status pending \
      --phase verified \
      --worker tech-developer >/dev/null 2>&1; then
    echo "ERROR: phase transition guard failed; invalid transition accepted" >&2
    exit 1
  fi
}

check_retry_auto_escalation() {
  local project claim_out blocked_file
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null
  run_queue "$project" add \
    --queue developer-todo \
    --id RETRY-001 \
    --title "retry auto escalation" \
    --worker tech-developer \
    --source "scenario-runtime-check" \
    --status pending \
    --phase ready \
    --attempt-count 3 \
    --retry-budget 3 >/dev/null

  claim_out="$(run_queue "$project" claim --queue developer-todo --worker tech-developer --actor tech-developer 2>&1 || true)"
  assert_contains "$claim_out" "AUTO_ESCALATED_RETRY_EXHAUSTED:developer-todo:1" "auto escalation"
  assert_contains "$claim_out" "NO_PENDING:developer-todo" "claim after escalation"

  blocked_file="$project/$RUNTIME_ROOT/orchestration/queues/blocked.tsv"
  awk -F'\t' 'NR>1 && $1=="RETRY-001" {
    if ($2!="blocked") exit 1
    if ($12!="dependency_blocked") exit 1
    found=1
  }
  END { exit(found?0:1) }
  ' "$blocked_file"
}

check_reconcile_exhausted() {
  local project blocked_file
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null
  run_queue "$project" add \
    --queue scientist-todo \
    --id RETRY-002 \
    --title "reconcile exhausted" \
    --worker tech-scientist \
    --source "scenario-runtime-check" \
    --status pending \
    --phase ready \
    --attempt-count 2 \
    --retry-budget 2 >/dev/null

  run_queue "$project" reconcile-exhausted --all --actor tech-planner >/dev/null
  blocked_file="$project/$RUNTIME_ROOT/orchestration/queues/blocked.tsv"
  awk -F'\t' 'NR>1 && $1=="RETRY-002" {
    if ($2!="blocked") exit 1
    if ($12!="dependency_blocked") exit 1
    found=1
  }
  END { exit(found?0:1) }
  ' "$blocked_file"
}

check_triage_blocked_order() {
  local project triage_out line_p1 line_p2
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null

  run_queue "$project" add \
    --queue blocked \
    --id TRIAGE-P2 \
    --title "soft fail item" \
    --worker tech-developer \
    --source "scenario-runtime-check" \
    --status blocked \
    --phase ready \
    --error-class soft_fail \
    --attempt-count 1 \
    --retry-budget 3 >/dev/null

  run_queue "$project" add \
    --queue blocked \
    --id TRIAGE-P1 \
    --title "hard fail item" \
    --worker tech-developer \
    --source "scenario-runtime-check" \
    --status blocked \
    --phase ready \
    --error-class hard_fail \
    --attempt-count 1 \
    --retry-budget 3 >/dev/null

  triage_out="$(run_queue "$project" triage-blocked --limit 20 2>&1)"
  assert_contains "$triage_out" $'priority\tage_days\tid' "triage header"
  assert_contains "$triage_out" "TRIAGE-P1" "triage p1"
  assert_contains "$triage_out" "TRIAGE-P2" "triage p2"

  line_p1="$(printf "%s\n" "$triage_out" | nl -ba | awk '/TRIAGE-P1/{print $1; exit}')"
  line_p2="$(printf "%s\n" "$triage_out" | nl -ba | awk '/TRIAGE-P2/{print $1; exit}')"
  if [[ -z "$line_p1" || -z "$line_p2" || "$line_p1" -ge "$line_p2" ]]; then
    echo "ERROR: triage ordering did not prioritize hard-fail item" >&2
    exit 1
  fi
}

check_weekly_retry_summary() {
  local project summary_out summary_file
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null

  run_queue "$project" add \
    --queue developer-todo \
    --id RETRY-003 \
    --title "summary seed" \
    --worker tech-developer \
    --source "scenario-runtime-check" \
    --status pending \
    --phase ready \
    --attempt-count 3 \
    --retry-budget 3 >/dev/null
  run_queue "$project" claim --queue developer-todo --worker tech-developer --actor tech-developer >/dev/null 2>&1 || true

  summary_out="$(run_queue "$project" weekly-retry-summary --weeks 1 2>&1)"
  assert_contains "$summary_out" "WEEKLY_SUMMARY_FILE:" "summary output"
  summary_file="$(printf "%s\n" "$summary_out" | sed -n 's/^WEEKLY_SUMMARY_FILE://p' | head -n1)"
  if [[ -z "$summary_file" || ! -f "$summary_file" ]]; then
    echo "ERROR: weekly summary file missing: $summary_file" >&2
    exit 1
  fi
  if ! rg -q "retry_budget_exhausted_events|open_blocked_exhausted_count" "$summary_file"; then
    echo "ERROR: weekly summary missing required metrics" >&2
    exit 1
  fi
}

check_next_prompt_blackbox() {
  local project out loop_out
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null

  out="$(run_queue "$project" next-prompt --user-facing 2>&1)"
  assert_contains "$out" "다음 실행 프롬프트" "next prompt block"
  assert_match_count "$out" '^다음 실행 프롬프트$' 1 "next prompt title count"
  assert_match_count "$out" '^```md$' 1 "next prompt markdown fence open count"
  assert_match_count "$out" '^```$' 1 "next prompt markdown fence close count"
  assert_match_count "$out" '^왜 지금 이 작업인가:' 1 "next prompt rationale line count"
  assert_contains "$out" "후보 3개" "next prompt intake candidate contract"
  assert_no_internal_leak "$out" "next-prompt user-facing leak check"

  loop_out="$(run_queue "$project" loop-status --user-facing 2>&1)"
  assert_match_count "$loop_out" '^요약:' 1 "loop-status user summary count"
  assert_no_internal_leak "$loop_out" "loop-status user-facing leak check"
}

check_pending_plan_seed() {
  local project plan_dir inbox_file
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null

  plan_dir="$project/$RUNTIME_ROOT/plans"
  mkdir -p "$plan_dir"
  cat > "$plan_dir/seed-plan.md" <<'MD'
# Seed Plan

## PlanSpec v2
id: seed-plan
owner: runtime-check
risk: low
mode: strict
verify_commands:
  - echo ok
done_definition:
  - seeded

## Delivery Waves
- [ ] 1. Pending task
  - Targets: test
  - Expected behavior: test
  - Execute: `echo execute`
  - Verification: `echo verify`
MD

  run_queue "$project" loop-status --user-facing >/dev/null
  inbox_file="$project/$RUNTIME_ROOT/orchestration/queues/planner-inbox.tsv"
  awk -F'\t' 'NR>1 && $5=="plan:seed-plan" {found=1} END {exit(found?0:1)}' "$inbox_file"
}

check_profile_hint() {
  local project claim_out
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null

  run_queue "$project" add \
    --queue developer-todo \
    --id PROF-001 \
    --title "profile hint" \
    --worker tech-developer \
    --source "scenario-runtime-check" \
    --status pending \
    --phase ready \
    --next-action "profile=refactoring-specialist" >/dev/null

  claim_out="$(run_queue "$project" claim --queue developer-todo --worker tech-developer --actor tech-developer 2>&1)"
  assert_contains "$claim_out" "CLAIM_PROFILE_HINT:refactoring-specialist" "profile hint"
}

check_archive_maintenance() {
  local project evidence_rel status_out
  project="$(new_temp_project)"
  run_queue "$project" init >/dev/null
  evidence_rel="$(create_pass_evidence "$project")"
  add_review_ticket "$project" "ARCH-001"
  run_queue "$project" move \
    --id ARCH-001 \
    --from planner-review \
    --to done \
    --status done \
    --worker tech-planner \
    --actor tech-planner \
    --evidence "$evidence_rel" >/dev/null

  status_out="$(SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$ARCHIVE_SCRIPT" status --project-root "$project")"
  assert_contains "$status_out" "archive_rows_total=" "archive status"

  SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$ARCHIVE_SCRIPT" clear --yes --project-root "$project" >/dev/null
  status_out="$(SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$ARCHIVE_SCRIPT" status --project-root "$project")"
  assert_contains "$status_out" "archive_rows_total=0" "archive clear"
}

check_dag_build_runtime_compile() {
  local pipeline_file
  pipeline_file="$PROJECT_ROOT/$RUNTIME_ROOT/dag/pipelines/runtime-check.pipeline.yml"

  (
    cd "$PROJECT_ROOT"
    SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$DAG_BUILD_SCRIPT" --out "$RUNTIME_ROOT/dag/pipelines/runtime-check.pipeline.yml" >/dev/null
  )

  if [[ ! -f "$pipeline_file" ]]; then
    echo "ERROR: expected pipeline file missing: $pipeline_file" >&2
    exit 1
  fi

  if [[ ! -f "$PROJECT_ROOT/$RUNTIME_ROOT/dag/scenarios/.compiled-manifest.tsv" ]]; then
    echo "ERROR: expected compiled manifest missing" >&2
    exit 1
  fi
}

check_dag_changed_only_execution() {
  local pipeline_rel="$RUNTIME_ROOT/dag/pipelines/synthetic-runtime-check.pipeline.yml"
  (
    cd "$PROJECT_ROOT"
    SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$DAG_BUILD_SCRIPT" \
      --out "$pipeline_rel" \
      --synthetic-nodes 20 >/dev/null
  )

  (
    cd "$PROJECT_ROOT"
    SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$DAG_RUN_SCRIPT" "$pipeline_rel" \
      --changed-only \
      --changed-file synthetic/input.txt >/dev/null
  )

  local state_file="$PROJECT_ROOT/$RUNTIME_ROOT/dag/state/last-run.json"
  if [[ ! -f "$state_file" ]]; then
    echo "ERROR: state file missing after changed-only execution" >&2
    exit 1
  fi
  local status
  status="$(extract_json_string_field "$state_file" "status")"
  if [[ "$status" != "PASS" ]]; then
    echo "ERROR: changed-only execution did not end with PASS (status=$status)" >&2
    exit 1
  fi
  local selected_count
  selected_count="$(extract_json_number_field "$state_file" "selected_node_count")"
  if [[ ! "$selected_count" =~ ^[0-9]+$ || "$selected_count" -lt 1 ]]; then
    echo "ERROR: changed-only execution selected_node_count is invalid ($selected_count)" >&2
    exit 1
  fi
}

check_dag_observability_artifacts() {
  local pipeline_rel="$RUNTIME_ROOT/dag/pipelines/synthetic-observability-check.pipeline.yml"
  (
    cd "$PROJECT_ROOT"
    SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$DAG_BUILD_SCRIPT" \
      --out "$pipeline_rel" \
      --synthetic-nodes 20 >/dev/null
    SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$DAG_RUN_SCRIPT" "$pipeline_rel" >/dev/null
  )
  local state_file evidence_dir
  state_file="$PROJECT_ROOT/$RUNTIME_ROOT/dag/state/last-run.json"
  evidence_dir="$(extract_json_string_field "$state_file" "evidence_dir")"
  if [[ -z "$evidence_dir" || ! -d "$evidence_dir" ]]; then
    echo "ERROR: evidence_dir missing in state output" >&2
    exit 1
  fi
  for artifact in run-summary.json trace.jsonl dag.mmd; do
    if [[ ! -f "$evidence_dir/$artifact" ]]; then
      echo "ERROR: observability artifact missing: $evidence_dir/$artifact" >&2
      exit 1
    fi
  done
  if ! rg -q '"status"[[:space:]]*:[[:space:]]*"PASS"' "$evidence_dir/run-summary.json"; then
    echo "ERROR: run-summary missing PASS status" >&2
    exit 1
  fi
}

check_dag_dual_layer_regression() {
  (
    cd "$PROJECT_ROOT"
    SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$DAG_DUAL_LAYER_SCRIPT" >/dev/null
  )
}

check_dag_stress_50_dry() {
  (
    cd "$PROJECT_ROOT"
    SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$DAG_STRESS_SCRIPT" --class 50 >/dev/null
  )
  local summary="$PROJECT_ROOT/$RUNTIME_ROOT/evidence/dag/stress/stress-summary.tsv"
  if [[ ! -f "$summary" ]]; then
    echo "ERROR: stress summary missing: $summary" >&2
    exit 1
  fi
  awk -F'\t' 'NR>1 && $1=="50" {
    if ($3!="PASS") exit 1
    found=1
  }
  END { exit(found?0:1) }
  ' "$summary"
}

check_dag_stress_50_full() {
  (
    cd "$PROJECT_ROOT"
    SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$DAG_STRESS_SCRIPT" --class 50 --run >/dev/null
  )
  local summary="$PROJECT_ROOT/$RUNTIME_ROOT/evidence/dag/stress/stress-summary.tsv"
  if [[ ! -f "$summary" ]]; then
    echo "ERROR: stress summary missing: $summary" >&2
    exit 1
  fi
  awk -F'\t' 'NR>1 && $1=="50" {
    if ($5!="PASS") exit 1
    found=1
  }
  END { exit(found?0:1) }
  ' "$summary"
}

check_lifecycle_bundle() {
  check_lifecycle_defaults
  check_lifecycle_claim_transition
  check_done_gate_pass
}

check_error_recovery_bundle() {
  check_retry_auto_escalation
  check_reconcile_exhausted
  check_weekly_retry_summary
}

check_observability_bundle() {
  check_dag_build_runtime_compile
  check_dag_changed_only_execution
  check_dag_observability_artifacts
}

check_scale_bundle() {
  check_dag_stress_50_dry
  check_dag_stress_50_full
}

check_refactoring_profile_bundle() {
  if [[ ! -x "$QUEUE_REGRESSION_SCRIPT" ]]; then
    echo "ERROR: required executable not found: $QUEUE_REGRESSION_SCRIPT" >&2
    exit 1
  fi
  (
    cd "$PROJECT_ROOT"
    SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$QUEUE_REGRESSION_SCRIPT" >/dev/null
  )
}

case "$CHECK_ID" in
  lifecycle_defaults) check_lifecycle_defaults ;;
  lifecycle_claim_transition) check_lifecycle_claim_transition ;;
  done_gate_pass) check_done_gate_pass ;;
  done_gate_requires_evidence) check_done_gate_requires_evidence ;;
  done_gate_planner_only) check_done_gate_planner_only ;;
  status_done_guard) check_status_done_guard ;;
  invalid_phase_guard) check_invalid_phase_guard ;;
  retry_auto_escalation) check_retry_auto_escalation ;;
  reconcile_exhausted) check_reconcile_exhausted ;;
  triage_blocked_order) check_triage_blocked_order ;;
  weekly_retry_summary) check_weekly_retry_summary ;;
  next_prompt_blackbox) check_next_prompt_blackbox ;;
  pending_plan_seed) check_pending_plan_seed ;;
  profile_hint) check_profile_hint ;;
  archive_maintenance) check_archive_maintenance ;;
  dag_build_runtime_compile) check_dag_build_runtime_compile ;;
  dag_changed_only_execution) check_dag_changed_only_execution ;;
  dag_observability_artifacts) check_dag_observability_artifacts ;;
  dag_dual_layer_regression) check_dag_dual_layer_regression ;;
  dag_stress_50_dry) check_dag_stress_50_dry ;;
  dag_stress_50_full) check_dag_stress_50_full ;;
  lifecycle_bundle) check_lifecycle_bundle ;;
  error_recovery_bundle) check_error_recovery_bundle ;;
  observability_bundle) check_observability_bundle ;;
  scale_bundle) check_scale_bundle ;;
  refactoring_profile_bundle) check_refactoring_profile_bundle ;;
  autoloop_regression)
    if [[ ! -x "$AUTOLOOP_REGRESSION_SCRIPT" ]]; then
      echo "ERROR: required executable not found: $AUTOLOOP_REGRESSION_SCRIPT" >&2
      exit 1
    fi
    (
      cd "$PROJECT_ROOT"
      SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$AUTOLOOP_REGRESSION_SCRIPT" >/dev/null
    )
    ;;
  *)
    echo "ERROR: unsupported check-id '$CHECK_ID' for scenario '$SCENARIO_ID'" >&2
    exit 1
    ;;
esac

echo "scenario_runtime_checks PASS: scenario=$SCENARIO_ID check=$CHECK_ID"
