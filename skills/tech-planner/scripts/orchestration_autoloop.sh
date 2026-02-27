#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  orchestration_autoloop.sh [--project-root <path>] [--max-cycles <n>] [--no-progress-limit <n>]

Purpose:
  Internal planner automation for long-running developer<->review loops.
  It repeatedly:
    1) promotes plan-backed planner-inbox items to developer-todo
    2) executes developer-todo items (strict plan_run)
    3) reviews planner-review items (done gate or requeue)
  until STOP_DONE / STOP_USER_CONFIRMATION / safety caps.

Notes:
  - Internal skill helper only. End-users should not call this directly.
  - Safe stop conditions are always enforced (max cycles + no-progress limit).
USAGE
}

RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"
if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE_SCRIPT="$SCRIPT_DIR/orchestration_queue.sh"
PLAN_RUN_SCRIPT="$SCRIPT_DIR/../../tech-developer/scripts/plan_run.sh"

if [[ ! -x "$QUEUE_SCRIPT" ]]; then
  echo "ERROR: missing executable queue helper: $QUEUE_SCRIPT" >&2
  exit 1
fi
if [[ ! -x "$PLAN_RUN_SCRIPT" ]]; then
  echo "ERROR: missing executable developer runner: $PLAN_RUN_SCRIPT" >&2
  exit 1
fi

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

queue_file_path() {
  local queue="$1"
  printf "%s/%s/orchestration/queues/%s.tsv" "$PROJECT_ROOT" "$RUNTIME_ROOT" "$queue"
}

run_queue() {
  bash "$QUEUE_SCRIPT" "$@" --project-root "$PROJECT_ROOT"
}

first_row_by_predicate() {
  local queue_file="$1"
  local predicate="$2"
  awk -F'\t' -v predicate="$predicate" '
    NR==1 { next }
    predicate=="review" && $2=="review" { print; exit }
    predicate=="pending" && $2=="pending" { print; exit }
    predicate=="pending_plan_source" && $2=="pending" && $5 ~ /^plan:/ { print; exit }
  ' "$queue_file"
}

field_of() {
  local row="$1"
  local idx="$2"
  printf "%s" "$row" | awk -F'\t' -v idx="$idx" '{print $idx}'
}

append_unique_csv_value() {
  local csv="${1:-}"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    printf "%s" "$csv"
    return 0
  fi
  if [[ -z "$csv" ]]; then
    printf "%s" "$value"
    return 0
  fi
  if printf ",%s," "$csv" | grep -Fq ",$value,"; then
    printf "%s" "$csv"
    return 0
  fi
  printf "%s,%s" "$csv" "$value"
}

loop_status_value() {
  local out
  out="$(run_queue loop-status 2>&1)"
  printf "%s\n" "$out" | sed -n 's/^LOOP_STATUS://p' | head -n1
}

has_non_plan_pending_inbox() {
  local inbox_file
  inbox_file="$(queue_file_path "planner-inbox")"
  awk -F'\t' '
    NR==1 { next }
    $2=="pending" && $5 !~ /^plan:/ { found=1; exit }
    END { exit(found?0:1) }
  ' "$inbox_file"
}

promote_one_plan_from_inbox() {
  local inbox_file row id
  inbox_file="$(queue_file_path "planner-inbox")"
  row="$(first_row_by_predicate "$inbox_file" "pending_plan_source")"
  if [[ -z "$row" ]]; then
    return 1
  fi
  id="$(field_of "$row" 1)"
  run_queue move \
    --id "$id" \
    --from planner-inbox \
    --to developer-todo \
    --status pending \
    --worker tech-developer \
    --error-class none \
    --note "autoloop route: plan-backed inbox item promoted to developer queue" \
    --next-action "execute plan in strict mode and return to planner-review" \
    --actor tech-planner >/dev/null
  echo "AUTOLOOP_ROUTE:planner-inbox->$id->developer-todo"
  return 0
}

claim_one_developer_ticket() {
  local claim_out row
  claim_out="$(run_queue claim --queue developer-todo --worker tech-developer --actor tech-developer 2>&1 || true)"
  if printf "%s\n" "$claim_out" | grep -Fq "NO_PENDING:developer-todo"; then
    return 1
  fi
  row="$(printf "%s\n" "$claim_out" | awk -F'\t' 'NF>=14 {print; exit}')"
  if [[ -z "$row" ]]; then
    return 1
  fi
  printf "%s" "$row"
  return 0
}

execute_one_developer_ticket() {
  local row id source plan_id plan_file
  local evidence_links evidence_base verify_tsv dag_state
  local run_log run_ok=0

  row="$(claim_one_developer_ticket)" || return 1
  id="$(field_of "$row" 1)"
  source="$(field_of "$row" 5)"

  if [[ "$source" != plan:* ]]; then
    run_queue move \
      --id "$id" \
      --from developer-todo \
      --to blocked \
      --status blocked \
      --worker tech-developer \
      --error-class dependency_blocked \
      --note "autoloop blocked: developer ticket is not plan-backed source" \
      --next-action "planner triage required: convert to plan-backed execution or reroute" \
      --actor tech-planner >/dev/null
    echo "AUTOLOOP_BLOCKED:$id:non-plan-source"
    return 0
  fi

  plan_id="${source#plan:}"
  plan_file="$PROJECT_ROOT/$RUNTIME_ROOT/plans/$plan_id.md"
  if [[ ! -f "$plan_file" ]]; then
    run_queue move \
      --id "$id" \
      --from developer-todo \
      --to blocked \
      --status blocked \
      --worker tech-developer \
      --error-class dependency_blocked \
      --note "autoloop blocked: plan file not found for source '$source'" \
      --next-action "planner triage required: restore plan file or reroute task" \
      --actor tech-planner >/dev/null
    echo "AUTOLOOP_BLOCKED:$id:missing-plan-file"
    return 0
  fi

  mkdir -p "$PROJECT_ROOT/$RUNTIME_ROOT/orchestration/history"
  run_log="$PROJECT_ROOT/$RUNTIME_ROOT/orchestration/history/autoloop-developer-${id}-$(date -u '+%Y%m%dT%H%M%SZ').log"
  if SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$PLAN_RUN_SCRIPT" "$plan_file" --mode strict >"$run_log" 2>&1; then
    run_ok=1
  fi

  evidence_base="$RUNTIME_ROOT/evidence/$plan_id"
  verify_tsv="$evidence_base/verification-results.tsv"
  dag_state="$RUNTIME_ROOT/dag/state/last-run.json"
  evidence_links=""
  evidence_links="$(append_unique_csv_value "$evidence_links" "$verify_tsv")"
  if [[ -f "$PROJECT_ROOT/$dag_state" ]]; then
    evidence_links="$(append_unique_csv_value "$evidence_links" "$dag_state")"
  fi
  evidence_links="$(append_unique_csv_value "$evidence_links" "$run_log")"

  if [[ "$run_ok" -eq 1 ]]; then
    run_queue move \
      --id "$id" \
      --from developer-todo \
      --to planner-review \
      --status review \
      --worker tech-developer \
      --phase evidence_collected \
      --error-class none \
      --note "autoloop execute pass: strict plan_run completed" \
      --next-action "planner review: approve done or request rework" \
      --evidence "$evidence_links" \
      --actor tech-developer >/dev/null
    echo "AUTOLOOP_EXECUTE_PASS:$id:$plan_id"
    return 0
  fi

  run_queue move \
    --id "$id" \
    --from developer-todo \
    --to blocked \
    --status blocked \
    --worker tech-developer \
    --error-class hard_fail \
    --note "autoloop execute fail: strict plan_run failed (see log)" \
    --next-action "planner triage required: fix failing plan commands/tests or scope down" \
    --evidence "$evidence_links" \
    --actor tech-planner >/dev/null
  echo "AUTOLOOP_EXECUTE_FAIL:$id:$plan_id"
  return 0
}

review_one_ticket() {
  local review_file row id evidence note done_out
  review_file="$(queue_file_path "planner-review")"
  row="$(first_row_by_predicate "$review_file" "review")"
  if [[ -z "$row" ]]; then
    return 1
  fi
  id="$(field_of "$row" 1)"
  evidence="$(field_of "$row" 10)"

  if done_out="$(run_queue move \
      --id "$id" \
      --from planner-review \
      --to done \
      --status done \
      --worker tech-planner \
      --actor tech-planner \
      --evidence "$evidence" 2>&1)"; then
    echo "AUTOLOOP_REVIEW_PASS:$id"
    return 0
  fi

  note="$(printf "%s" "$done_out" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | cut -c1-300)"
  run_queue move \
    --id "$id" \
    --from planner-review \
    --to developer-todo \
    --status pending \
    --worker tech-developer \
    --error-class soft_fail \
    --note "autoloop review reject: $note" \
    --next-action "rework implementation and return to planner-review with passing evidence" \
    --actor tech-planner >/dev/null
  echo "AUTOLOOP_REVIEW_REQUEUE:$id"
  return 0
}

PROJECT_ROOT=""
MAX_CYCLES=30
NO_PROGRESS_LIMIT=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --max-cycles)
      MAX_CYCLES="${2:-}"
      shift 2
      ;;
    --no-progress-limit)
      NO_PROGRESS_LIMIT="${2:-}"
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

if [[ ! "$MAX_CYCLES" =~ ^[0-9]+$ || "$MAX_CYCLES" -lt 1 ]]; then
  echo "ERROR: --max-cycles must be integer >= 1" >&2
  exit 1
fi
if [[ ! "$NO_PROGRESS_LIMIT" =~ ^[0-9]+$ || "$NO_PROGRESS_LIMIT" -lt 1 ]]; then
  echo "ERROR: --no-progress-limit must be integer >= 1" >&2
  exit 1
fi

PROJECT_ROOT="$(resolve_project_root "$PROJECT_ROOT")"
run_queue init >/dev/null

cycle=0
no_progress=0
terminal_status=""

while [[ "$cycle" -lt "$MAX_CYCLES" ]]; do
  cycle=$((cycle + 1))
  progress=0
  echo "AUTOLOOP_CYCLE:$cycle"

  while promote_one_plan_from_inbox >/dev/null 2>&1; do
    progress=1
  done

  while review_one_ticket >/dev/null 2>&1; do
    progress=1
  done

  if execute_one_developer_ticket >/dev/null 2>&1; then
    progress=1
    while review_one_ticket >/dev/null 2>&1; do
      progress=1
    done
  fi

  loop_status="$(loop_status_value)"
  if [[ "$loop_status" == "STOP_DONE" || "$loop_status" == "STOP_USER_CONFIRMATION" ]]; then
    terminal_status="$loop_status"
    break
  fi

  if has_non_plan_pending_inbox; then
    terminal_status="STOP_USER_CONFIRMATION"
    break
  fi

  if [[ "$progress" -eq 1 ]]; then
    no_progress=0
  else
    no_progress=$((no_progress + 1))
  fi
  if [[ "$no_progress" -ge "$NO_PROGRESS_LIMIT" ]]; then
    terminal_status="STOP_NO_PROGRESS"
    break
  fi
done

if [[ -z "$terminal_status" ]]; then
  if [[ "$cycle" -ge "$MAX_CYCLES" ]]; then
    terminal_status="STOP_MAX_CYCLES"
  else
    terminal_status="$(loop_status_value)"
  fi
fi

echo "AUTOLOOP_TERMINAL_STATUS:$terminal_status"
echo "AUTOLOOP_TOTAL_CYCLES:$cycle"
echo "AUTOLOOP_NO_PROGRESS_COUNT:$no_progress"
run_queue next-prompt --user-facing
