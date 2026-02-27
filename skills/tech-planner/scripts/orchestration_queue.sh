#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  orchestration_queue.sh <command> [options]

Note:
  This helper is intended for internal skill automation.
  Skills should run it automatically; end-users should not need to call it directly.

Commands:
  init [--project-root <path>]
  add --queue <name> --id <id> --title <title> [--worker <name>] [--status <status>] [--source <text>] [--note <text>] \
      [--next-action <text>] [--lease <text>] [--evidence <text>] [--phase <phase>] [--error-class <class>] \
      [--attempt-count <n>] [--retry-budget <n>] [--project-root <path>]
  claim --queue <name> --worker <name> [--actor <name>] [--project-root <path>]
  reconcile-exhausted [--queue <name>|--all] [--actor <name>] [--quiet] [--project-root <path>]
  triage-blocked [--limit <n>] [--project-root <path>]
  weekly-retry-summary [--weeks <n>] [--project-root <path>]
  loop-status [--project-root <path>] [--user-facing]
  next-prompt [--project-root <path>] [--user-facing]
  move --id <id> --from <queue> --to <queue> [--status <status>] [--worker <name>] [--note <text>] \
       [--next-action <text>] [--lease <text>] [--evidence <text>] [--phase <phase>] [--error-class <class>] \
       [--attempt-count <n>] [--retry-budget <n>] [--actor <name>] [--project-root <path>]
  list [--queue <name>] [--project-root <path>]
  stats [--project-root <path>]

Status rules:
  - allowed statuses: pending, in_progress, review, done, blocked
  - allowed phases: planned, ready, running, evidence_collected, verified, done
  - allowed error classes: none, soft_fail, hard_fail, dependency_blocked
  - `done` transition is allowed only from `planner-review` queue
  - `done` transition requires planner actor authority (`--actor` or `SIGEE_QUEUE_ACTOR`)
  - `done` transition requires evidence + passing verification gate
  - `evidence_links` supports comma/semicolon/pipe separators (`, ; |`)
  - queue `planner-review` uses status `review`
  - queue `blocked` uses status `blocked`
  - developer profile intent can be passed via metadata (`next_action`/`note`) with `profile=<slug>` or `profile:<slug>`
  - loop termination:
    - `STOP_DONE`: actionable queue가 모두 비어 종료
    - `STOP_USER_CONFIRMATION`: blocked에서 사용자 확정 필요 항목 발견 시 종료
    - `CONTINUE`: 그 외 상태

Debug examples are intentionally omitted from help output.
Use maintainers' internal docs for operational command walkthroughs.
USAGE
}

RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"
if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITIGNORE_GUARD_SCRIPT="$SCRIPT_DIR/sigee_gitignore_guard.sh"
PRODUCT_TRUTH_VALIDATE_SCRIPT="$SCRIPT_DIR/product_truth_validate.sh"
GOAL_GOV_VALIDATE_SCRIPT="$SCRIPT_DIR/goal_governance_validate.sh"
USER_FACING_GUARD_SCRIPT="$SCRIPT_DIR/user_facing_guard.sh"
USER_FACING_RENDERER_SCRIPT="$SCRIPT_DIR/user_facing_renderer.sh"
QUEUE_STATE_MODULE_SCRIPT="$SCRIPT_DIR/orchestration_queue_state.sh"
QUEUE_STORE_MODULE_SCRIPT="$SCRIPT_DIR/orchestration_queue_store.sh"

if [[ ! -f "$USER_FACING_GUARD_SCRIPT" ]]; then
  echo "ERROR: missing shared user-facing guard: $USER_FACING_GUARD_SCRIPT" >&2
  exit 1
fi
if [[ ! -f "$USER_FACING_RENDERER_SCRIPT" ]]; then
  echo "ERROR: missing shared user-facing renderer: $USER_FACING_RENDERER_SCRIPT" >&2
  exit 1
fi
if [[ ! -f "$QUEUE_STATE_MODULE_SCRIPT" ]]; then
  echo "ERROR: missing queue state module: $QUEUE_STATE_MODULE_SCRIPT" >&2
  exit 1
fi
if [[ ! -f "$QUEUE_STORE_MODULE_SCRIPT" ]]; then
  echo "ERROR: missing queue store module: $QUEUE_STORE_MODULE_SCRIPT" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$USER_FACING_GUARD_SCRIPT"
# shellcheck disable=SC1090
source "$USER_FACING_RENDERER_SCRIPT"
# shellcheck disable=SC1090
source "$QUEUE_STATE_MODULE_SCRIPT"
# shellcheck disable=SC1090
source "$QUEUE_STORE_MODULE_SCRIPT"

STANDARD_QUEUES=(
  "planner-inbox"
  "scientist-todo"
  "developer-todo"
  "planner-review"
  "blocked"
  "done"
)
VALID_STATUSES=(
  "pending"
  "in_progress"
  "review"
  "done"
  "blocked"
)
VALID_PHASES=(
  "planned"
  "ready"
  "running"
  "evidence_collected"
  "verified"
  "done"
)
VALID_ERROR_CLASSES=(
  "none"
  "soft_fail"
  "hard_fail"
  "dependency_blocked"
)
RECONCILE_EXHAUSTED_QUEUES=(
  "planner-inbox"
  "scientist-todo"
  "developer-todo"
)
SUPPORTED_DEVELOPER_PROFILES=(
  "generalist"
  "backend-api"
  "frontend-ui"
  "data-engineering"
  "infra-automation"
  "refactoring-specialist"
)
QUEUE_HEADER=$'id\tstatus\tworker\ttitle\tsource\tupdated_at\tnote\tnext_action\tlease\tevidence_links\tphase\terror_class\tattempt_count\tretry_budget'
ARCHIVE_HEADER=$'id\tstatus\tworker\ttitle\tsource\tupdated_at\tnote\tnext_action\tlease\tevidence_links\tphase\terror_class\tattempt_count\tretry_budget\tarchived_at\tarchived_by'
RETRY_HISTORY_HEADER=$'ts_utc\tevent_type\tid\tfrom_queue\tto_queue\tstatus\terror_class\tattempt_count\tretry_budget\tpriority\tactor\tnote'
RETRY_EXHAUSTED_NEXT_ACTION_TEXT="planner triage required: retry budget exhausted; decide scope_down, reroute, budget_increase, or close"

timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

sanitize_field() {
  printf "%s" "$1" | tr '\t\r\n' '   '
}

trim_field() {
  local value="$1"
  value="$(printf "%s" "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf "%s" "$value"
}

retry_exhausted_next_action() {
  printf "%s" "$RETRY_EXHAUSTED_NEXT_ACTION_TEXT"
}

retry_exhausted_note() {
  local from_queue="$1"
  printf "retry budget exhausted in %s; auto-detoured to blocked for planner triage" "$from_queue"
}

to_lower() {
  printf "%s" "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_profile_hint() {
  local raw lowered normalized
  raw="$(trim_field "${1:-}")"
  lowered="$(to_lower "$raw")"
  normalized="$(printf "%s" "$lowered" | tr '_' '-')"
  case "$normalized" in
    general|generalist|default) printf "generalist" ;;
    backend|api|backendapi|backend-api|server) printf "backend-api" ;;
    frontend|ui|web|frontend-ui) printf "frontend-ui" ;;
    data|data-eng|data-engineering|pipeline) printf "data-engineering" ;;
    infra|infra-automation|devops|platform) printf "infra-automation" ;;
    refactor|refactoring|cleanup|cleanup-specialist|refactoring-specialist) printf "refactoring-specialist" ;;
    *)
      local p
      for p in "${SUPPORTED_DEVELOPER_PROFILES[@]}"; do
        if [[ "$normalized" == "$p" ]]; then
          printf "%s" "$p"
          return 0
        fi
      done
      printf ""
      ;;
  esac
}

extract_profile_hint_from_text() {
  local text token normalized
  text="${1:-}"
  token="$(printf "%s" "$text" | sed -nE 's/.*profile[[:space:]]*[:=][[:space:]]*([A-Za-z0-9_.-]+).*/\1/p' | head -n1)"
  if [[ -z "$token" ]]; then
    token="$(printf "%s" "$text" | sed -nE 's/.*\[profile[[:space:]:=]+([A-Za-z0-9_.-]+)\].*/\1/p' | head -n1)"
  fi
  normalized="$(normalize_profile_hint "$token")"
  printf "%s" "$normalized"
}

detect_claim_profile_for_row() {
  local row note next_action profile
  row="${1:-}"
  note="$(printf "%s" "$row" | awk -F'\t' '{print $7}')"
  next_action="$(printf "%s" "$row" | awk -F'\t' '{print $8}')"

  profile="$(extract_profile_hint_from_text "$next_action")"
  if [[ -n "$profile" ]]; then
    printf "%s\t%s\n" "$profile" "next_action"
    return 0
  fi
  profile="$(extract_profile_hint_from_text "$note")"
  if [[ -n "$profile" ]]; then
    printf "%s\t%s\n" "$profile" "note"
    return 0
  fi
  printf "%s\t%s\n" "generalist" "default"
}

is_meaningful_value() {
  local raw trimmed lower
  raw="${1:-}"
  trimmed="$(trim_field "$raw")"
  lower="$(to_lower "$trimmed")"
  case "$lower" in
    ""|"none"|"n/a"|"na"|"-"|"tbd"|"todo")
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

resolve_actor_name() {
  local explicit="${1:-}"
  local fallback="${2:-}"
  if [[ -n "$explicit" ]]; then
    printf "%s" "$explicit"
    return 0
  fi
  if [[ -n "${SIGEE_QUEUE_ACTOR:-}" ]]; then
    printf "%s" "${SIGEE_QUEUE_ACTOR}"
    return 0
  fi
  if [[ -n "$fallback" ]]; then
    printf "%s" "$fallback"
    return 0
  fi
  printf ""
}

is_planner_actor() {
  local actor
  actor="$(to_lower "$(trim_field "${1:-}")")"
  case "$actor" in
    planner|tech-planner|planner-agent|tech-planner-agent|planner-reviewer)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_evidence_path() {
  local project_root="$1"
  local token="$2"
  token="$(trim_field "$token")"
  if [[ -z "$token" ]]; then
    return 1
  fi
  if [[ "$token" == http://* || "$token" == https://* ]]; then
    return 1
  fi
  if [[ "$token" == /* ]]; then
    printf "%s" "$token"
    return 0
  fi
  printf "%s/%s" "$project_root" "$token"
}

verify_results_file_pass() {
  local results_file="$1"
  if [[ ! -f "$results_file" ]]; then
    return 1
  fi
  awk -F'\t' '
    NR==1 { next }
    {
      rows++
      if ($4=="PASS") pass++
      if ($4=="FAIL") fail++
    }
    END {
      if (rows>0 && pass>0 && fail==0) exit 0
      exit 1
    }
  ' "$results_file"
}

verify_dag_state_pass() {
  local state_file="$1"
  if [[ ! -f "$state_file" ]]; then
    return 1
  fi
  if ! grep -Eq '"status"[[:space:]]*:[[:space:]]*"PASS"' "$state_file"; then
    return 1
  fi
  local evidence_dir
  evidence_dir="$(sed -nE 's/^[[:space:]]*"evidence_dir"[[:space:]]*:[[:space:]]*"([^"]+)".*$/\1/p' "$state_file" | head -n1)"
  if [[ -n "$evidence_dir" && -d "$evidence_dir" ]]; then
    return 0
  fi
  return 1
}

validate_done_gate() {
  local project_root="$1"
  local ticket_id="$2"
  local evidence_links="$3"
  local has_gate_pass=0

  if ! is_meaningful_value "$evidence_links"; then
    echo "ERROR: move to 'done' requires non-empty evidence links for ticket '$ticket_id'." >&2
    exit 1
  fi

  local token resolved
  while IFS= read -r token; do
    token="$(trim_field "$token")"
    [[ -z "$token" ]] && continue
    resolved="$(resolve_evidence_path "$project_root" "$token" || true)"
    [[ -z "$resolved" ]] && continue
    if [[ "$resolved" == *.tsv ]] && verify_results_file_pass "$resolved"; then
      has_gate_pass=1
    fi
    if [[ "$resolved" == *"/dag/state/"*.json ]] && verify_dag_state_pass "$resolved"; then
      has_gate_pass=1
    fi
  done < <(printf "%s\n" "$evidence_links" | tr ',;|' '\n')

  if [[ "$has_gate_pass" -eq 0 ]]; then
    local default_dag_state="$project_root/$RUNTIME_ROOT/dag/state/last-run.json"
    if verify_dag_state_pass "$default_dag_state"; then
      has_gate_pass=1
    fi
  fi

  if [[ "$has_gate_pass" -eq 0 ]]; then
    echo "ERROR: move to 'done' requires passing verification evidence (PASS-only verification-results.tsv or PASS dag/state/last-run.json)." >&2
    exit 1
  fi

  local scenario_dir="$project_root/.sigee/dag/scenarios"
  if [[ ! -d "$scenario_dir" ]]; then
    scenario_dir="$project_root/$RUNTIME_ROOT/dag/scenarios"
  fi
  if [[ -d "$scenario_dir" ]] && find "$scenario_dir" -maxdepth 1 -type f -name '*.scenario.yml' | grep -q .; then
    if [[ ! -x "$PRODUCT_TRUTH_VALIDATE_SCRIPT" ]]; then
      echo "ERROR: missing executable validator for done gate: $PRODUCT_TRUTH_VALIDATE_SCRIPT" >&2
      exit 1
    fi
    "$PRODUCT_TRUTH_VALIDATE_SCRIPT" \
      --project-root "$project_root" \
      --scenario-dir "$scenario_dir" \
      --require-scenarios >/dev/null

    if [[ ! -x "$GOAL_GOV_VALIDATE_SCRIPT" ]]; then
      echo "ERROR: missing executable goal-governance validator for done gate: $GOAL_GOV_VALIDATE_SCRIPT" >&2
      exit 1
    fi
    "$GOAL_GOV_VALIDATE_SCRIPT" \
      --project-root "$project_root" \
      --scenario-dir "$scenario_dir" \
      --require-scenarios \
      --strict >/dev/null
  fi
}

list_retry_exhausted_ids() {
  local queue_file="$1"
  awk -F'\t' '
    NR==1 { next }
    {
      attempts = ($13 ~ /^[0-9]+$/) ? $13+0 : 0
      budget = ($14 ~ /^[0-9]+$/ && $14+0>0) ? $14+0 : 3
      if ((($2 == "pending") || ($2 == "in_progress")) && attempts >= budget) {
        print $1
      }
    }
  ' "$queue_file"
}

reconcile_exhausted_in_queue() {
  local project_root="$1"
  local queue="$2"
  local actor="$3"
  local quiet="${4:-0}"
  local event_type="${5:-retry_budget_exhausted_reconcile}"
  local queue_file
  local moved=0
  local id
  local row
  local rtitle rnote rnext_action rerror_class rattempt_count rretry_budget rpriority
  local detour_next_action detour_note

  if [[ "$queue" == "blocked" || "$queue" == "done" || "$queue" == "planner-review" ]]; then
    printf "0"
    return 0
  fi

  queue_file="$(queue_file_path "$project_root" "$queue")"
  ensure_queue_file "$queue_file"

  while IFS= read -r id; do
    id="$(trim_field "$id")"
    [[ -z "$id" ]] && continue
    row="$(awk -F'\t' -v id="$id" 'NR>1 && $1==id {print; exit}' "$queue_file")"
    rtitle="$(printf "%s" "$row" | awk -F'\t' '{print $4}')"
    rnote="$(printf "%s" "$row" | awk -F'\t' '{print $7}')"
    rnext_action="$(printf "%s" "$row" | awk -F'\t' '{print $8}')"
    rerror_class="$(printf "%s" "$row" | awk -F'\t' '{print $12}')"
    rattempt_count="$(printf "%s" "$row" | awk -F'\t' '{print $13}')"
    rretry_budget="$(printf "%s" "$row" | awk -F'\t' '{print $14}')"
    rpriority="$(priority_label_for_row "$rtitle" "$rnote" "$rnext_action" "$rerror_class" "$rattempt_count" "$rretry_budget")"
    detour_next_action="$(retry_exhausted_next_action)"
    detour_note="$(retry_exhausted_note "$queue")"
    cmd_move \
      --id "$id" \
      --from "$queue" \
      --to blocked \
      --status blocked \
      --error-class dependency_blocked \
      --next-action "$detour_next_action" \
      --note "$detour_note" \
      --actor "$actor" \
      --project-root "$project_root" >/dev/null
    append_retry_history_event \
      "$project_root" \
      "$event_type" \
      "$id" \
      "$queue" \
      "blocked" \
      "blocked" \
      "dependency_blocked" \
      "${rattempt_count:-0}" \
      "${rretry_budget:-3}" \
      "$rpriority" \
      "$actor" \
      "$detour_note"
    moved=$((moved + 1))
  done < <(list_retry_exhausted_ids "$queue_file")

  if [[ "$moved" -gt 0 ]]; then
    refresh_weekly_retry_summary "$project_root" "1"
  fi

  printf "%s" "$moved"
}

cmd_reconcile_exhausted() {
  local queue=""
  local actor="${SIGEE_QUEUE_ACTOR:-planner}"
  local project_root=""
  local quiet=0
  local use_all=1
  local moved_total=0
  local moved=0
  local target
  local targets=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --queue)
        queue="${2:-}"
        use_all=0
        shift 2
        ;;
      --all)
        queue=""
        use_all=1
        shift
        ;;
      --actor)
        actor="${2:-}"
        shift 2
        ;;
      --quiet)
        quiet=1
        shift
        ;;
      --project-root)
        project_root="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown option for reconcile-exhausted: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  actor="$(resolve_actor_name "$actor" "planner")"
  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"

  if [[ "$use_all" -eq 1 ]]; then
    targets=("${RECONCILE_EXHAUSTED_QUEUES[@]}")
  else
    validate_queue_name "$queue" "reconcile-exhausted"
    targets=("$queue")
  fi

  for target in "${targets[@]}"; do
    moved="$(reconcile_exhausted_in_queue "$project_root" "$target" "$actor" "$quiet" "retry_budget_exhausted_manual_reconcile")"
    moved_total=$((moved_total + moved))
    if [[ "$quiet" -eq 0 ]]; then
      echo "RECONCILED_QUEUE:$target:$moved"
    fi
  done

  if [[ "$quiet" -eq 0 ]]; then
    echo "RECONCILED_TOTAL:$moved_total"
  fi
  refresh_weekly_retry_summary "$project_root" "1"
}

cmd_triage_blocked() {
  local limit="20"
  local project_root=""
  local blocked_file

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit)
        limit="${2:-}"
        shift 2
        ;;
      --project-root)
        project_root="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown option for triage-blocked: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  validate_positive_int "$limit" "limit" "triage-blocked"
  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"
  blocked_file="$(queue_file_path "$project_root" "blocked")"
  ensure_queue_file "$blocked_file"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: triage-blocked requires python3 for aging/priority sorting." >&2
    exit 1
  fi

  python3 - "$blocked_file" "$limit" <<'PY'
import csv
import datetime as dt
import re
import sys

blocked_file = sys.argv[1]
limit = max(1, int(sys.argv[2]))
now = dt.datetime.utcnow()

def parse_ts(value):
    try:
        return dt.datetime.strptime((value or "").strip(), "%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return dt.datetime(1970, 1, 1)

def priority_rank(row):
    merged = " ".join([
        (row.get("title") or ""),
        (row.get("note") or ""),
        (row.get("next_action") or ""),
    ]).lower()
    tagged = re.search(r"\bp([0-3])\b", merged)
    if tagged:
        return int(tagged.group(1))
    err = (row.get("error_class") or "").strip()
    try:
        attempts = int((row.get("attempt_count") or "0").strip())
    except Exception:
        attempts = 0
    try:
        budget = int((row.get("retry_budget") or "3").strip())
    except Exception:
        budget = 3
    if budget < 1:
        budget = 3
    if err == "hard_fail":
        return 1
    if attempts >= budget:
        return 1
    if err in ("dependency_blocked", "soft_fail"):
        return 2
    return 3

rows = []
with open(blocked_file, "r", encoding="utf-8") as f:
    reader = csv.DictReader(f, delimiter="\t")
    for row in reader:
        if (row.get("status") or "").strip() != "blocked":
            continue
        updated = parse_ts(row.get("updated_at"))
        age_days = int((now - updated).total_seconds() // 86400)
        pr = priority_rank(row)
        rows.append((pr, updated, age_days, row))

if not rows:
    print("NO_BLOCKED_TICKETS")
    raise SystemExit(0)

rows.sort(key=lambda x: (x[0], x[1]))  # priority first, then oldest first
print("priority\tage_days\tid\terror_class\tattempt_count\tretry_budget\tupdated_at\ttitle\tnext_action")
for pr, updated, age_days, row in rows[:limit]:
    print(
        f"P{pr}\t{age_days}\t{(row.get('id') or '').strip()}\t{(row.get('error_class') or '').strip()}\t"
        f"{(row.get('attempt_count') or '').strip()}\t{(row.get('retry_budget') or '').strip()}\t"
        f"{(row.get('updated_at') or '').strip()}\t{(row.get('title') or '').strip()}\t"
        f"{(row.get('next_action') or '').strip()}"
    )
PY
}

cmd_weekly_retry_summary() {
  local weeks="1"
  local project_root=""
  local output_file

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --weeks)
        weeks="${2:-}"
        shift 2
        ;;
      --project-root)
        project_root="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown option for weekly-retry-summary: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  validate_positive_int "$weeks" "weeks" "weekly-retry-summary"
  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"
  refresh_weekly_retry_summary "$project_root" "$weeks"
  output_file="$(weekly_retry_summary_file_path "$project_root" "$weeks")"
  echo "WEEKLY_SUMMARY_FILE:$output_file"
}

queue_count_by_statuses() {
  local queue_file="$1"
  local statuses_csv="$2"
  awk -F'\t' -v statuses="$statuses_csv" '
    BEGIN {
      split(statuses, arr, ",")
      for (i in arr) {
        allow[arr[i]] = 1
      }
    }
    NR==1 { next }
    {
      if ($2 in allow) c++
    }
    END { print c+0 }
  ' "$queue_file"
}

blocked_user_confirmation_count() {
  local queue_file="$1"
  awk -F'\t' '
    NR==1 { next }
    $2=="blocked" {
      text = tolower($7 " " $8)
      if (text ~ /(needs_user_confirmation|external_decision_required|user_decision_required|requires user confirmation|user confirmation required)/) {
        c++
      }
    }
    END { print c+0 }
  ' "$queue_file"
}

blocked_user_confirmation_ids() {
  local queue_file="$1"
  awk -F'\t' '
    NR==1 { next }
    $2=="blocked" {
      text = tolower($7 " " $8)
      if (text ~ /(needs_user_confirmation|external_decision_required|user_decision_required|requires user confirmation|user confirmation required)/) {
        if (out == "") out = $1
        else out = out "," $1
      }
    }
    END { print out }
  ' "$queue_file"
}

plan_file_has_unchecked_tasks() {
  local plan_file="$1"
  if [[ ! -f "$plan_file" ]]; then
    return 1
  fi
  grep -Eq '^- \[ \]' "$plan_file"
}

plan_id_from_file() {
  local plan_file="$1"
  local plan_id
  plan_id="$(sed -nE 's/^id:[[:space:]]*([A-Za-z0-9._-]+)[[:space:]]*$/\1/p' "$plan_file" | head -n1)"
  if [[ -z "$plan_id" ]]; then
    plan_id="$(basename "$plan_file" .md)"
  fi
  printf "%s" "$plan_id"
}

sanitize_plan_id_for_ticket() {
  local raw="$1"
  raw="$(printf "%s" "$raw" | tr -cs 'A-Za-z0-9._-' '-')"
  raw="$(printf "%s" "$raw" | sed -E 's/^-+//; s/-+$//')"
  printf "%s" "$raw"
}

plan_source_exists_in_file() {
  local queue_file="$1"
  local source="$2"
  if [[ ! -f "$queue_file" ]]; then
    return 1
  fi
  awk -F'\t' -v source="$source" '
    NR==1 { next }
    $5==source { found=1; exit }
    END { exit(found?0:1) }
  ' "$queue_file"
}

plan_source_exists_in_active_queues() {
  local project_root="$1"
  local source="$2"
  local queue queue_file
  for queue in planner-inbox scientist-todo developer-todo planner-review blocked done; do
    queue_file="$(queue_file_path "$project_root" "$queue")"
    ensure_queue_file "$queue_file"
    if plan_source_exists_in_file "$queue_file" "$source"; then
      return 0
    fi
  done
  return 1
}

seed_pending_plans_to_planner_inbox() {
  local project_root="$1"
  local plans_dir planner_inbox_file
  local plan_file plan_id source ticket_suffix ticket_id
  local title note next_action
  local seeded=0

  plans_dir="$project_root/$RUNTIME_ROOT/plans"
  planner_inbox_file="$(queue_file_path "$project_root" "planner-inbox")"
  ensure_queue_file "$planner_inbox_file"

  if [[ ! -d "$plans_dir" ]]; then
    printf "0"
    return 0
  fi

  while IFS= read -r plan_file; do
    [[ -f "$plan_file" ]] || continue
    if ! plan_file_has_unchecked_tasks "$plan_file"; then
      continue
    fi
    plan_id="$(trim_field "$(plan_id_from_file "$plan_file")")"
    [[ -z "$plan_id" ]] && continue
    source="plan:$plan_id"
    if plan_source_exists_in_active_queues "$project_root" "$source"; then
      continue
    fi
    ticket_suffix="$(sanitize_plan_id_for_ticket "$plan_id")"
    if [[ -z "$ticket_suffix" ]]; then
      ticket_suffix="$(date -u '+%Y%m%d%H%M%S')"
    fi
    ticket_id="PLAN-$ticket_suffix"
    title="Execute approved plan: $plan_id"
    note="auto-seeded from pending plan with unchecked tasks"
    next_action="planner triage: route this plan to scientist/developer execution"
    append_row \
      "$planner_inbox_file" \
      "$ticket_id" \
      "pending" \
      "tech-planner" \
      "$title" \
      "$source" \
      "$(timestamp_utc)" \
      "$note" \
      "$next_action" \
      "none" \
      "none" \
      "planned" \
      "none" \
      "0" \
      "$(default_retry_budget)"
    seeded=$((seeded + 1))
  done < <(find "$plans_dir" -maxdepth 1 -type f -name '*.md' | sort)

  printf "%s" "$seeded"
}

count_pending_plan_files() {
  local project_root="$1"
  local plans_dir
  local count=0
  plans_dir="$project_root/$RUNTIME_ROOT/plans"
  if [[ ! -d "$plans_dir" ]]; then
    printf "0"
    return 0
  fi
  while IFS= read -r plan_file; do
    [[ -f "$plan_file" ]] || continue
    if plan_file_has_unchecked_tasks "$plan_file"; then
      count=$((count + 1))
    fi
  done < <(find "$plans_dir" -maxdepth 1 -type f -name '*.md' | sort)
  printf "%s" "$count"
}

evaluate_loop_status() {
  local project_root="$1"
  local planner_review_file blocked_file scientist_file developer_file planner_inbox_file
  local planner_review_count blocked_count blocked_user_count blocked_non_user_count
  local scientist_count developer_count planner_inbox_count actionable_total
  local loop_status reason user_ids pending_plan_count

  # Keep queue and plan state synchronized so approved-but-unexecuted plans
  # cannot be treated as fully completed orchestration state.
  seed_pending_plans_to_planner_inbox "$project_root" >/dev/null

  planner_review_file="$(queue_file_path "$project_root" "planner-review")"
  blocked_file="$(queue_file_path "$project_root" "blocked")"
  scientist_file="$(queue_file_path "$project_root" "scientist-todo")"
  developer_file="$(queue_file_path "$project_root" "developer-todo")"
  planner_inbox_file="$(queue_file_path "$project_root" "planner-inbox")"

  planner_review_count="$(queue_count_by_statuses "$planner_review_file" "review")"
  blocked_count="$(queue_count_by_statuses "$blocked_file" "blocked")"
  blocked_user_count="$(blocked_user_confirmation_count "$blocked_file")"
  scientist_count="$(queue_count_by_statuses "$scientist_file" "pending,in_progress")"
  developer_count="$(queue_count_by_statuses "$developer_file" "pending,in_progress")"
  planner_inbox_count="$(queue_count_by_statuses "$planner_inbox_file" "pending,in_progress")"

  if [[ "$blocked_count" -lt "$blocked_user_count" ]]; then
    blocked_user_count="$blocked_count"
  fi
  blocked_non_user_count=$((blocked_count - blocked_user_count))

  actionable_total=$((planner_review_count + blocked_non_user_count + scientist_count + developer_count + planner_inbox_count))
  user_ids="$(blocked_user_confirmation_ids "$blocked_file")"
  pending_plan_count="$(count_pending_plan_files "$project_root")"

  if [[ "$blocked_user_count" -gt 0 ]]; then
    loop_status="STOP_USER_CONFIRMATION"
    reason="blocked queue has user confirmation required items"
  elif [[ "$actionable_total" -eq 0 && "$pending_plan_count" -gt 0 ]]; then
    loop_status="CONTINUE"
    reason="pending plan backlog exists with unchecked tasks"
  elif [[ "$actionable_total" -eq 0 ]]; then
    loop_status="STOP_DONE"
    reason="all actionable queues are empty"
  else
    loop_status="CONTINUE"
    reason="actionable work remains"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$loop_status" \
    "$reason" \
    "$planner_inbox_count" \
    "$scientist_count" \
    "$developer_count" \
    "$planner_review_count" \
    "$blocked_count" \
    "$blocked_user_count" \
    "$actionable_total" \
    "$user_ids"
}

emit_loop_status_snapshot() {
  local snapshot="$1"
  local output_mode="${2:-machine}"
  local loop_status reason planner_inbox_count scientist_count developer_count planner_review_count
  local blocked_count blocked_user_count actionable_total user_ids
  local summary_line

  loop_status="$(printf "%s" "$snapshot" | awk -F'\t' '{print $1}')"
  reason="$(printf "%s" "$snapshot" | awk -F'\t' '{print $2}')"
  planner_inbox_count="$(printf "%s" "$snapshot" | awk -F'\t' '{print $3}')"
  scientist_count="$(printf "%s" "$snapshot" | awk -F'\t' '{print $4}')"
  developer_count="$(printf "%s" "$snapshot" | awk -F'\t' '{print $5}')"
  planner_review_count="$(printf "%s" "$snapshot" | awk -F'\t' '{print $6}')"
  blocked_count="$(printf "%s" "$snapshot" | awk -F'\t' '{print $7}')"
  blocked_user_count="$(printf "%s" "$snapshot" | awk -F'\t' '{print $8}')"
  actionable_total="$(printf "%s" "$snapshot" | awk -F'\t' '{print $9}')"
  user_ids="$(printf "%s" "$snapshot" | awk -F'\t' '{print $10}')"

  if [[ "$output_mode" == "user" ]]; then
    case "$loop_status" in
      CONTINUE)
        summary_line="요약: 다음 제품 작업으로 바로 진행할 수 있습니다."
        ;;
      STOP_DONE)
        summary_line="요약: 현재 사이클 목표가 완료되었습니다."
        ;;
      STOP_USER_CONFIRMATION)
        summary_line="요약: 다음 단계로 가기 전에 사용자 결정이 필요합니다."
        ;;
      *)
        summary_line="요약: $reason"
        ;;
    esac
    sanitize_user_facing_summary_line "$summary_line"
    return 0
  fi

  echo "LOOP_STATUS:$loop_status"
  echo "LOOP_REASON:$reason"
  echo "LOOP_COUNTS:planner-inbox=$planner_inbox_count scientist-todo=$scientist_count developer-todo=$developer_count planner-review=$planner_review_count blocked=$blocked_count blocked-user-confirmation=$blocked_user_count actionable-total=$actionable_total"
  if [[ -n "$user_ids" ]]; then
    echo "LOOP_USER_CONFIRMATION_IDS:$user_ids"
  fi
}

recommend_next_target() {
  local project_root="$1"
  local planner_review_file blocked_file scientist_file developer_file planner_inbox_file
  local planner_review_count blocked_count blocked_user_count scientist_count developer_count planner_inbox_count
  local loop_snapshot loop_status
  local target queue reason

  loop_snapshot="$(evaluate_loop_status "$project_root")"
  loop_status="$(printf "%s" "$loop_snapshot" | awk -F'\t' '{print $1}')"
  if [[ "$loop_status" == "STOP_USER_CONFIRMATION" ]]; then
    target="tech-planner"
    queue="blocked-user-confirmation"
    reason="user confirmation required"
    printf "%s\t%s\t%s\n" "$target" "$queue" "$reason"
    return 0
  fi
  if [[ "$loop_status" == "STOP_DONE" ]]; then
    target="tech-planner"
    queue="completed"
    reason="all actionable queues are empty"
    printf "%s\t%s\t%s\n" "$target" "$queue" "$reason"
    return 0
  fi

  planner_review_file="$(queue_file_path "$project_root" "planner-review")"
  blocked_file="$(queue_file_path "$project_root" "blocked")"
  scientist_file="$(queue_file_path "$project_root" "scientist-todo")"
  developer_file="$(queue_file_path "$project_root" "developer-todo")"
  planner_inbox_file="$(queue_file_path "$project_root" "planner-inbox")"

  planner_review_count="$(queue_count_by_statuses "$planner_review_file" "review")"
  blocked_count="$(queue_count_by_statuses "$blocked_file" "blocked")"
  blocked_user_count="$(blocked_user_confirmation_count "$blocked_file")"
  scientist_count="$(queue_count_by_statuses "$scientist_file" "pending,in_progress")"
  developer_count="$(queue_count_by_statuses "$developer_file" "pending,in_progress")"
  planner_inbox_count="$(queue_count_by_statuses "$planner_inbox_file" "pending,in_progress")"

  if [[ "$planner_review_count" -gt 0 ]]; then
    target="tech-planner"
    queue="planner-review"
    reason="review backlog exists"
  elif [[ "$blocked_count" -gt "$blocked_user_count" ]]; then
    target="tech-planner"
    queue="blocked"
    reason="blocked triage required"
  elif [[ "$scientist_count" -gt 0 ]]; then
    target="tech-scientist"
    queue="scientist-todo"
    reason="scientific evidence tasks pending"
  elif [[ "$developer_count" -gt 0 ]]; then
    target="tech-developer"
    queue="developer-todo"
    reason="implementation tasks pending"
  elif [[ "$planner_inbox_count" -gt 0 ]]; then
    target="tech-planner"
    queue="planner-inbox"
    reason="new requirements need decomposition"
  else
    target="tech-planner"
    queue="completed"
    reason="all actionable queues are empty"
  fi

  printf "%s\t%s\t%s\n" "$target" "$queue" "$reason"
}

next_prompt_message() {
  local target="$1"
  local queue="$2"
  case "$target:$queue" in
    tech-planner:planner-review)
      printf "%s" "방금 반영된 변경이 제품 목표와 일치하는지 검토해줘. 승인 여부를 결정하고 보완이 필요하면 사용자 영향이 큰 개선 1건만 제시해줘."
      ;;
    tech-planner:blocked)
      printf "%s" "진행을 막는 의사결정 항목을 우선순위로 정리해줘. 각 항목마다 권장 선택과 사용자 영향을 함께 제시하고 다음 실행 방향을 결정해줘."
      ;;
    tech-scientist:scientist-todo)
      printf "%s" "제품 리스크를 줄일 수 있는 과학/수학 검증 과제 1건을 우선 처리해줘. 근거, 적용 방향, 검증 계획을 정리해줘."
      ;;
    tech-developer:developer-todo)
      printf "%s" "사용자 가치가 가장 큰 구현 과제 1건을 strict로 완료해줘. 검증 근거와 함께 결과를 보고해줘."
      ;;
    tech-planner:planner-inbox)
      printf "%s" "신규 요구를 제품 기능으로 분해하고 우선순위를 정해줘. 바로 실행할 다음 작업 1건을 제시해줘."
      ;;
    tech-planner:blocked-user-confirmation)
      printf "%s" "지금 사용자 결정이 필요한 항목만 요약해줘. 각 항목마다 권장 선택과 영향을 짧게 정리해줘."
      ;;
    tech-planner:completed)
      printf "%s" "현재 사이클은 완료되었어. 다음 제품 목표 1개를 정하고 바로 시작할 첫 작업 1건을 제안해줘."
      ;;
    *)
      printf "%s" "다음으로 사용자 가치가 큰 작업 1건을 선정해줘. 선정 이유와 기대 변화를 함께 설명해줘."
      ;;
  esac
}

next_prompt_message_user_facing() {
  local target="$1"
  local queue="$2"
  case "$target:$queue" in
    tech-planner:planner-review)
      printf "%s" "방금 반영된 변화가 제품 목표에 맞는지 확인해줘. 보완이 필요하면 사용자 영향이 큰 개선 1건만 제안해줘."
      ;;
    tech-planner:blocked)
      printf "%s" "진행을 막는 의사결정을 사용자 관점으로 정리해줘. 각 항목마다 권장 선택과 영향을 간단히 제시해줘."
      ;;
    tech-scientist:scientist-todo)
      printf "%s" "제품 적용 리스크를 줄일 수 있는 검증 과제 1건을 우선 처리해줘. 결과는 근거와 적용 방향 중심으로 설명해줘."
      ;;
    tech-developer:developer-todo)
      printf "%s" "사용자 가치가 큰 기능 1건을 우선 구현해줘. 사용자 변화와 안전성 확인 결과 중심으로 설명해줘."
      ;;
    tech-planner:planner-inbox)
      printf "%s" "신규 요구를 제품 기능으로 정리해 우선순위를 정해줘. 바로 시작할 다음 작업 1건만 제시해줘."
      ;;
    tech-planner:blocked-user-confirmation)
      printf "%s" "지금 필요한 사용자 결정을 정리해줘. 각 항목마다 권장 선택과 영향만 짧게 설명해줘."
      ;;
    tech-planner:completed)
      printf "%s" "현재 사이클이 완료되었어. 다음 제품 목표 1개를 정하고 바로 시작할 첫 작업 1건을 제안해줘."
      ;;
    *)
      printf "%s" "다음으로 사용자 가치가 큰 작업 1건을 선정해줘. 선정 이유와 기대 변화를 함께 설명해줘."
      ;;
  esac
}

user_facing_internal_leak_detected() {
  sigee_user_facing_internal_leak_detected "${1:-}"
}

sanitize_user_facing_summary_line() {
  sigee_render_sanitize_summary_line "${1:-}"
}

sanitize_user_facing_prompt_message() {
  sigee_render_sanitize_prompt_message "${1:-}"
}

sanitize_user_facing_context_text() {
  sigee_render_sanitize_context_text "${1:-}"
}

product_goal_summary_text() {
  sigee_render_product_goal_summary_text "${1:-}"
}

recent_change_summary_text() {
  sigee_render_recent_change_summary_text "${1:-}" "$RUNTIME_ROOT"
}

build_user_facing_why_now_line() {
  sigee_render_build_why_now_line "${1:-}" "$RUNTIME_ROOT"
}

append_user_facing_context_line() {
  sigee_render_append_context_line "${1:-}" "${2:-}" "$RUNTIME_ROOT"
}

emit_next_prompt_recommendation() {
  local project_root="$1"
  local output_mode="${2:-machine}"
  local rec target queue reason message loop_snapshot loop_status
  loop_snapshot="$(evaluate_loop_status "$project_root")"
  loop_status="$(printf "%s" "$loop_snapshot" | awk -F'\t' '{print $1}')"
  emit_loop_status_snapshot "$loop_snapshot" "$output_mode"
  rec="$(recommend_next_target "$project_root")"
  target="$(printf "%s" "$rec" | awk -F'\t' '{print $1}')"
  queue="$(printf "%s" "$rec" | awk -F'\t' '{print $2}')"
  reason="$(printf "%s" "$rec" | awk -F'\t' '{print $3}')"
  if [[ "$output_mode" == "user" ]]; then
    message="$(next_prompt_message_user_facing "$target" "$queue")"
    message="$(append_user_facing_context_line "$project_root" "$message")"
    message="$(sanitize_user_facing_prompt_message "$message")"
  else
    message="$(next_prompt_message "$target" "$queue")"
  fi

  if [[ "$output_mode" != "user" ]]; then
    printf "NEXT_PROMPT_TARGET:%s\n" "$target"
    printf "NEXT_PROMPT_QUEUE:%s\n" "$queue"
    printf "NEXT_PROMPT_REASON:%s\n" "$reason"
  fi
  printf '%s\n' '```md'
  printf '%s\n' '다음 실행 프롬프트'
  printf '\n'
  if [[ "$output_mode" != "user" ]]; then
    printf '$%s\n' "$target"
    printf '\n'
  fi
  printf '%s\n' "$message"
  printf '%s\n' '```'
}

cmd_loop_status() {
  local project_root=""
  local output_mode="machine"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root)
        project_root="${2:-}"
        shift 2
        ;;
      --user-facing)
        output_mode="user"
        shift
        ;;
      *)
        echo "Unknown option for loop-status: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"
  emit_loop_status_snapshot "$(evaluate_loop_status "$project_root")" "$output_mode"
}

cmd_next_prompt() {
  local project_root=""
  local output_mode="machine"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root)
        project_root="${2:-}"
        shift 2
        ;;
      --user-facing)
        output_mode="user"
        shift
        ;;
      *)
        echo "Unknown option for next-prompt: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"
  emit_next_prompt_recommendation "$project_root" "$output_mode"
}

is_standard_queue() {
  local candidate="$1"
  local q
  for q in "${STANDARD_QUEUES[@]}"; do
    if [[ "$q" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

validate_queue_name() {
  local queue="$1"
  local context="$2"
  if ! is_standard_queue "$queue"; then
    echo "ERROR: invalid queue for $context: '$queue' (allowed: ${STANDARD_QUEUES[*]})" >&2
    exit 1
  fi
}

is_valid_status() {
  local candidate="$1"
  local s
  for s in "${VALID_STATUSES[@]}"; do
    if [[ "$s" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

validate_status_name() {
  local status="$1"
  local context="$2"
  if ! is_valid_status "$status"; then
    echo "ERROR: invalid status for $context: '$status' (allowed: ${VALID_STATUSES[*]})" >&2
    exit 1
  fi
}

is_valid_phase() {
  local candidate="$1"
  local phase
  for phase in "${VALID_PHASES[@]}"; do
    if [[ "$phase" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

validate_phase_name() {
  local phase="$1"
  local context="$2"
  if ! is_valid_phase "$phase"; then
    echo "ERROR: invalid phase for $context: '$phase' (allowed: ${VALID_PHASES[*]})" >&2
    exit 1
  fi
}

is_valid_error_class() {
  local candidate="$1"
  local klass
  for klass in "${VALID_ERROR_CLASSES[@]}"; do
    if [[ "$klass" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

validate_error_class() {
  local error_class="$1"
  local context="$2"
  if ! is_valid_error_class "$error_class"; then
    echo "ERROR: invalid error class for $context: '$error_class' (allowed: ${VALID_ERROR_CLASSES[*]})" >&2
    exit 1
  fi
}

validate_non_negative_int() {
  local value="$1"
  local field="$2"
  local context="$3"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "ERROR: ${field} for ${context} must be a non-negative integer (got: '$value')." >&2
    exit 1
  fi
}

validate_positive_int() {
  local value="$1"
  local field="$2"
  local context="$3"
  if [[ ! "$value" =~ ^[0-9]+$ || "$value" -lt 1 ]]; then
    echo "ERROR: ${field} for ${context} must be an integer >= 1 (got: '$value')." >&2
    exit 1
  fi
}

# queue state + queue I/O functions are sourced from dedicated modules:
# - orchestration_queue_state.sh
# - orchestration_queue_store.sh

cmd_init() {
  local project_root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root)
        project_root="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown option for init: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"

  echo "Initialized orchestration runtime: $project_root/$RUNTIME_ROOT"
}

cmd_add() {
  local queue=""
  local id=""
  local title=""
  local worker="planner"
  local status=""
  local status_set=0
  local source="manual"
  local note=""
  local next_action="TBD"
  local lease="none"
  local evidence_links="none"
  local phase=""
  local phase_set=0
  local error_class=""
  local error_class_set=0
  local attempt_count="0"
  local attempt_count_set=0
  local retry_budget=""
  local retry_budget_set=0
  local project_root=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --queue) queue="${2:-}"; shift 2 ;;
      --id) id="${2:-}"; shift 2 ;;
      --title) title="${2:-}"; shift 2 ;;
      --worker) worker="${2:-}"; shift 2 ;;
      --status) status="${2:-}"; status_set=1; shift 2 ;;
      --source) source="${2:-}"; shift 2 ;;
      --note) note="${2:-}"; shift 2 ;;
      --next-action) next_action="${2:-}"; shift 2 ;;
      --lease) lease="${2:-}"; shift 2 ;;
      --evidence) evidence_links="${2:-}"; shift 2 ;;
      --phase) phase="${2:-}"; phase_set=1; shift 2 ;;
      --error-class) error_class="${2:-}"; error_class_set=1; shift 2 ;;
      --attempt-count) attempt_count="${2:-}"; attempt_count_set=1; shift 2 ;;
      --retry-budget) retry_budget="${2:-}"; retry_budget_set=1; shift 2 ;;
      --project-root) project_root="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for add: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$queue" || -z "$id" || -z "$title" ]]; then
    echo "ERROR: add requires --queue, --id, and --title." >&2
    exit 1
  fi
  validate_queue_name "$queue" "add"
  if [[ "$queue" == "done" ]]; then
    echo "ERROR: direct add to queue 'done' is not allowed. Use move from planner-review." >&2
    exit 1
  fi
  if [[ "$status_set" -eq 0 ]]; then
    status="$(default_status_for_queue "$queue")"
  fi
  validate_status_name "$status" "add"
  if [[ "$queue" == "planner-review" && "$status" != "review" ]]; then
    echo "ERROR: queue 'planner-review' requires status 'review'." >&2
    exit 1
  fi
  if [[ "$queue" == "blocked" && "$status" != "blocked" ]]; then
    echo "ERROR: queue 'blocked' requires status 'blocked'." >&2
    exit 1
  fi
  if [[ "$status" == "done" ]]; then
    echo "ERROR: status 'done' is only valid for queue 'done'." >&2
    exit 1
  fi
  if [[ "$phase_set" -eq 0 ]]; then
    phase="$(default_phase_for_queue "$queue" "$status")"
  fi
  validate_phase_name "$phase" "add"
  if [[ "$error_class_set" -eq 0 ]]; then
    error_class="$(default_error_class_for_queue "$queue" "$status")"
  fi
  validate_error_class "$error_class" "add"
  validate_non_negative_int "$attempt_count" "attempt_count" "add"
  if [[ "$retry_budget_set" -eq 0 ]]; then
    retry_budget="$(default_retry_budget)"
  fi
  validate_positive_int "$retry_budget" "retry_budget" "add"
  if [[ "$attempt_count" -gt "$retry_budget" ]]; then
    echo "ERROR: attempt_count ($attempt_count) must be <= retry_budget ($retry_budget) for add." >&2
    exit 1
  fi

  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"
  local queue_file
  queue_file="$(queue_file_path "$project_root" "$queue")"
  ensure_queue_file "$queue_file"
  append_row "$queue_file" "$id" "$status" "$worker" "$title" "$source" "$(timestamp_utc)" "$note" "$next_action" "$lease" "$evidence_links" "$phase" "$error_class" "$attempt_count" "$retry_budget"
  echo "Added: $id -> $queue"
}

cmd_claim() {
  local queue=""
  local worker=""
  local actor=""
  local project_root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --queue) queue="${2:-}"; shift 2 ;;
      --worker) worker="${2:-}"; shift 2 ;;
      --actor) actor="${2:-}"; shift 2 ;;
      --project-root) project_root="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for claim: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$queue" || -z "$worker" ]]; then
    echo "ERROR: claim requires --queue and --worker." >&2
    exit 1
  fi
  validate_queue_name "$queue" "claim"
  if [[ "$queue" == "done" ]]; then
    echo "ERROR: queue 'done' does not support claim." >&2
    exit 1
  fi

  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"
  actor="$(resolve_actor_name "$actor" "$worker")"

  local auto_escalated
  auto_escalated="$(reconcile_exhausted_in_queue "$project_root" "$queue" "$actor" 1 "retry_budget_exhausted_auto_claim")"
  if [[ "$auto_escalated" -gt 0 ]]; then
    echo "AUTO_ESCALATED_RETRY_EXHAUSTED:$queue:$auto_escalated"
    echo "AUTO_ESCALATED_NEXT_ACTION:$(retry_exhausted_next_action)"
  fi

  local queue_file
  queue_file="$(queue_file_path "$project_root" "$queue")"
  ensure_queue_file "$queue_file"

  local tmp_file claim_file status now
  tmp_file="$(mktemp)"
  claim_file="$(mktemp)"
  now="$(timestamp_utc)"
  status=0
  awk -F'\t' -v OFS='\t' -v worker="$worker" -v now="$now" -v claim_file="$claim_file" -v q="$queue" '
    NR==1 { print; next }
    !claimed && $2=="pending" {
      phase=$11
      error_class=$12
      attempts=$13
      budget=$14
      if (phase=="") {
        if (q=="planner-inbox") phase="planned"
        else phase="ready"
      }
      if (error_class=="") error_class="none"
      if (attempts=="" || attempts !~ /^[0-9]+$/) attempts=0
      if (budget=="" || budget !~ /^[0-9]+$/ || budget < 1) budget=3
      if (attempts >= budget) {
        exhausted=1
        print
        next
      }
      $2="in_progress"
      $3=worker
      $6=now
      $9="held:" worker ":" now
      $11="running"
      if ($12=="soft_fail" || $12=="dependency_blocked") $12="none"
      $13=attempts + 1
      $14=budget
      claimed=1
      print $0 > claim_file
    }
    { print }
    END {
      if (!claimed) {
        if (exhausted) exit 4
        exit 2
      }
    }
  ' "$queue_file" > "$tmp_file" || status=$?

  if [[ "$status" -eq 2 ]]; then
    rm -f "$tmp_file" "$claim_file"
    echo "NO_PENDING:$queue"
    return 0
  fi
  if [[ "$status" -eq 4 ]]; then
    rm -f "$tmp_file" "$claim_file"
    echo "NO_RETRY_BUDGET:$queue"
    return 0
  fi
  if [[ "$status" -ne 0 ]]; then
    rm -f "$tmp_file" "$claim_file"
    echo "ERROR: failed to claim from queue: $queue" >&2
    exit "$status"
  fi

  mv "$tmp_file" "$queue_file"
  if [[ "$queue" == "developer-todo" ]]; then
    local claim_row profile_info profile_hint profile_source
    claim_row="$(cat "$claim_file")"
    profile_info="$(detect_claim_profile_for_row "$claim_row")"
    profile_hint="$(printf "%s" "$profile_info" | awk -F'\t' '{print $1}')"
    profile_source="$(printf "%s" "$profile_info" | awk -F'\t' '{print $2}')"
    echo "CLAIM_PROFILE_HINT:$profile_hint"
    echo "CLAIM_PROFILE_SOURCE:$profile_source"
  fi
  cat "$claim_file"
  rm -f "$claim_file"
}

cmd_move() {
  local id=""
  local from_queue=""
  local to_queue=""
  local status=""
  local status_set=0
  local worker=""
  local worker_set=0
  local note=""
  local note_set=0
  local next_action=""
  local next_action_set=0
  local lease=""
  local lease_set=0
  local evidence_links=""
  local evidence_set=0
  local phase=""
  local phase_set=0
  local error_class=""
  local error_class_set=0
  local attempt_count=""
  local attempt_count_set=0
  local retry_budget=""
  local retry_budget_set=0
  local actor=""
  local project_root=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="${2:-}"; shift 2 ;;
      --from) from_queue="${2:-}"; shift 2 ;;
      --to) to_queue="${2:-}"; shift 2 ;;
      --status) status="${2:-}"; status_set=1; shift 2 ;;
      --worker) worker="${2:-}"; worker_set=1; shift 2 ;;
      --note) note="${2:-}"; note_set=1; shift 2 ;;
      --next-action) next_action="${2:-}"; next_action_set=1; shift 2 ;;
      --lease) lease="${2:-}"; lease_set=1; shift 2 ;;
      --evidence) evidence_links="${2:-}"; evidence_set=1; shift 2 ;;
      --phase) phase="${2:-}"; phase_set=1; shift 2 ;;
      --error-class) error_class="${2:-}"; error_class_set=1; shift 2 ;;
      --attempt-count) attempt_count="${2:-}"; attempt_count_set=1; shift 2 ;;
      --retry-budget) retry_budget="${2:-}"; retry_budget_set=1; shift 2 ;;
      --actor) actor="${2:-}"; shift 2 ;;
      --project-root) project_root="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for move: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$id" || -z "$from_queue" || -z "$to_queue" ]]; then
    echo "ERROR: move requires --id, --from, and --to." >&2
    exit 1
  fi
  validate_queue_name "$from_queue" "move --from"
  validate_queue_name "$to_queue" "move --to"
  if [[ "$from_queue" == "done" && "$to_queue" != "done" ]]; then
    echo "ERROR: queue 'done' is terminal and cannot be moved out." >&2
    exit 1
  fi
  if [[ "$status_set" -eq 0 ]]; then
    status="$(default_status_for_queue "$to_queue")"
  fi
  validate_status_name "$status" "move"
  if [[ "$to_queue" == "done" ]]; then
    if [[ "$from_queue" != "planner-review" ]]; then
      echo "ERROR: only planner-review -> done transition is allowed." >&2
      exit 1
    fi
    if [[ "$status_set" -eq 1 && "$status" != "done" ]]; then
      echo "ERROR: move to queue 'done' requires status 'done'." >&2
      exit 1
    fi
    status="done"
  elif [[ "$status" == "done" ]]; then
    echo "ERROR: status 'done' is only valid when moving to queue 'done'." >&2
    exit 1
  fi
  if [[ "$to_queue" == "planner-review" && "$status_set" -eq 1 && "$status" != "review" ]]; then
    echo "ERROR: queue 'planner-review' requires status 'review'." >&2
    exit 1
  fi
  if [[ "$to_queue" == "blocked" && "$status_set" -eq 1 && "$status" != "blocked" ]]; then
    echo "ERROR: queue 'blocked' requires status 'blocked'." >&2
    exit 1
  fi
  if [[ "$to_queue" == "done" && "$phase_set" -eq 1 && "$phase" != "done" ]]; then
    echo "ERROR: move to queue 'done' requires phase 'done'." >&2
    exit 1
  fi

  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"
  local from_file to_file
  from_file="$(queue_file_path "$project_root" "$from_queue")"
  to_file="$(queue_file_path "$project_root" "$to_queue")"
  ensure_queue_file "$from_file"
  ensure_queue_file "$to_file"

  local tmp_file row_file rc
  tmp_file="$(mktemp)"
  row_file="$(mktemp)"
  rc=0
  awk -F'\t' -v OFS='\t' -v id="$id" -v row_file="$row_file" '
    NR==1 { print; next }
    $1==id && !found {
      found=1
      print $0 > row_file
      next
    }
    { print }
    END { if (!found) exit 3 }
  ' "$from_file" > "$tmp_file" || rc=$?

  if [[ "$rc" -eq 3 ]]; then
    rm -f "$tmp_file" "$row_file"
    echo "ERROR: id not found in queue '$from_queue': $id" >&2
    exit 1
  fi
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$tmp_file" "$row_file"
    echo "ERROR: failed to move id '$id' from '$from_queue'" >&2
    exit "$rc"
  fi

  local rid rstatus rworker rtitle rsource rnote rnext_action rlease revidence_links
  local rphase rerror_class rattempt_count rretry_budget
  rid="$(awk -F'\t' 'NR==1{print $1}' "$row_file")"
  rstatus="$(awk -F'\t' 'NR==1{print $2}' "$row_file")"
  rworker="$(awk -F'\t' 'NR==1{print $3}' "$row_file")"
  rtitle="$(awk -F'\t' 'NR==1{print $4}' "$row_file")"
  rsource="$(awk -F'\t' 'NR==1{print $5}' "$row_file")"
  rnote="$(awk -F'\t' 'NR==1{print $7}' "$row_file")"
  rnext_action="$(awk -F'\t' 'NR==1{print $8}' "$row_file")"
  rlease="$(awk -F'\t' 'NR==1{print $9}' "$row_file")"
  revidence_links="$(awk -F'\t' 'NR==1{print $10}' "$row_file")"
  rphase="$(awk -F'\t' 'NR==1{print $11}' "$row_file")"
  rerror_class="$(awk -F'\t' 'NR==1{print $12}' "$row_file")"
  rattempt_count="$(awk -F'\t' 'NR==1{print $13}' "$row_file")"
  rretry_budget="$(awk -F'\t' 'NR==1{print $14}' "$row_file")"
  rm -f "$row_file"

  if [[ "$worker_set" -eq 0 ]]; then
    worker="$rworker"
  fi
  if [[ "$to_queue" == "done" && "$worker_set" -eq 0 ]]; then
    worker="planner"
  fi
  if [[ "$note_set" -eq 0 ]]; then
    note="$rnote"
  fi
  if [[ "$next_action_set" -eq 0 ]]; then
    next_action="$rnext_action"
  fi
  if [[ "$lease_set" -eq 0 ]]; then
    lease="$(auto_lease_for_transition "$to_queue" "$status" "$worker" "$(timestamp_utc)")"
  fi
  if [[ "$evidence_set" -eq 0 ]]; then
    evidence_links="$revidence_links"
  fi
  if [[ "$phase_set" -eq 0 ]]; then
    if [[ "$to_queue" == "blocked" && -n "$rphase" ]]; then
      phase="$rphase"
    else
      phase="$(default_phase_for_queue "$to_queue" "$status")"
    fi
  fi
  validate_phase_name "$phase" "move"
  local from_phase
  from_phase="${rphase:-$(default_phase_for_queue "$from_queue" "$rstatus")}"
  validate_phase_name "$from_phase" "move-from"
  validate_phase_transition "$from_phase" "$phase" "$from_queue" "$to_queue" "$status"

  if [[ "$error_class_set" -eq 0 ]]; then
    if [[ "$to_queue" == "blocked" ]]; then
      if [[ -n "$rerror_class" && "$rerror_class" != "none" ]]; then
        error_class="$rerror_class"
      else
        error_class="soft_fail"
      fi
    elif [[ "$to_queue" == "planner-review" && -n "$rerror_class" ]]; then
      error_class="$rerror_class"
    else
      error_class="$(default_error_class_for_queue "$to_queue" "$status")"
    fi
  fi
  validate_error_class "$error_class" "move"

  if [[ "$attempt_count_set" -eq 0 ]]; then
    attempt_count="${rattempt_count:-0}"
  fi
  validate_non_negative_int "$attempt_count" "attempt_count" "move"
  if [[ "$retry_budget_set" -eq 0 ]]; then
    retry_budget="${rretry_budget:-$(default_retry_budget)}"
  fi
  validate_positive_int "$retry_budget" "retry_budget" "move"
  if [[ "$attempt_count" -gt "$retry_budget" ]]; then
    echo "ERROR: attempt_count ($attempt_count) must be <= retry_budget ($retry_budget) for move." >&2
    exit 1
  fi

  actor="$(resolve_actor_name "$actor" "")"
  if [[ "$to_queue" == "done" ]]; then
    if [[ -z "$actor" ]]; then
      echo "ERROR: move to queue 'done' requires planner actor (--actor or SIGEE_QUEUE_ACTOR)." >&2
      exit 1
    fi
    if ! is_planner_actor "$actor"; then
      echo "ERROR: actor '$actor' is not authorized for done transition (planner only)." >&2
      exit 1
    fi
    if ! is_planner_actor "$worker"; then
      echo "ERROR: queue 'done' requires planner worker identity (got '$worker')." >&2
      exit 1
    fi
    validate_done_gate "$project_root" "$rid" "$evidence_links"
    local archive_file
    archive_file="$(archive_file_path "$project_root")"
    ensure_archive_file "$archive_file"
    append_archive_row \
      "$archive_file" \
      "$rid" \
      "$status" \
      "$worker" \
      "$rtitle" \
      "$rsource" \
      "$(timestamp_utc)" \
      "$note" \
      "$next_action" \
      "$lease" \
      "$evidence_links" \
      "$phase" \
      "$error_class" \
      "$attempt_count" \
      "$retry_budget" \
      "$(timestamp_utc)" \
      "$actor"
    mv "$tmp_file" "$from_file"
    echo "Moved: $id $from_queue -> $to_queue ($status) by $actor [archived]"
    emit_next_prompt_recommendation "$project_root" "user"
    return 0
  fi

  append_row "$to_file" "$rid" "$status" "$worker" "$rtitle" "$rsource" "$(timestamp_utc)" "$note" "$next_action" "$lease" "$evidence_links" "$phase" "$error_class" "$attempt_count" "$retry_budget"
  mv "$tmp_file" "$from_file"
  if [[ -n "$actor" ]]; then
    echo "Moved: $id $from_queue -> $to_queue ($status) by $actor"
  else
    echo "Moved: $id $from_queue -> $to_queue ($status)"
  fi
}

cmd_list() {
  local queue=""
  local project_root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --queue) queue="${2:-}"; shift 2 ;;
      --project-root) project_root="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for list: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"

  if [[ -n "$queue" ]]; then
    validate_queue_name "$queue" "list"
    cat "$(queue_file_path "$project_root" "$queue")"
    return 0
  fi

  local q
  for q in "${STANDARD_QUEUES[@]}"; do
    echo "== $q =="
    cat "$(queue_file_path "$project_root" "$q")"
    echo
  done
}

cmd_stats() {
  local project_root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for stats: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  project_root="$(resolve_project_root "$project_root")"
  bootstrap_runtime "$project_root"

  local q file
  for q in "${STANDARD_QUEUES[@]}"; do
    file="$(queue_file_path "$project_root" "$q")"
    awk -F'\t' -v q="$q" '
      NR==1 { next }
      {
        c[$2]++
        p[$11]++
        e[$12]++
        attempts = ($13 ~ /^[0-9]+$/) ? $13+0 : 0
        budget = ($14 ~ /^[0-9]+$/ && $14+0>0) ? $14+0 : 3
        if (attempts >= budget) exhausted++
        if ($2!="pending" && $2!="in_progress" && $2!="review" && $2!="done" && $2!="blocked") {
          c["unknown"]++
        }
      }
      END {
        printf "%s\tpending=%d\tin_progress=%d\treview=%d\tdone=%d\tblocked=%d\tunknown=%d\tphase_ready=%d\tphase_running=%d\tphase_verified=%d\terror_soft=%d\terror_hard=%d\terror_dep=%d\tretry_exhausted=%d\n",
          q, c["pending"]+0, c["in_progress"]+0, c["review"]+0, c["done"]+0, c["blocked"]+0, c["unknown"]+0,
          p["ready"]+0, p["running"]+0, p["verified"]+0,
          e["soft_fail"]+0, e["hard_fail"]+0, e["dependency_blocked"]+0, exhausted+0
      }
    ' "$file"
  done
  local archive_dir archive_total
  archive_dir="$(archive_dir_path "$project_root")"
  archive_total="$(awk 'FNR>1{c++} END{print c+0}' "$archive_dir"/done-*.tsv 2>/dev/null || printf "0")"
  printf "archive\tdone_rows_total=%s\n" "$archive_total"
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  init) cmd_init "$@" ;;
  add) cmd_add "$@" ;;
  claim) cmd_claim "$@" ;;
  reconcile-exhausted) cmd_reconcile_exhausted "$@" ;;
  triage-blocked) cmd_triage_blocked "$@" ;;
  weekly-retry-summary) cmd_weekly_retry_summary "$@" ;;
  loop-status) cmd_loop_status "$@" ;;
  next-prompt) cmd_next_prompt "$@" ;;
  move) cmd_move "$@" ;;
  list) cmd_list "$@" ;;
  stats) cmd_stats "$@" ;;
  --help|-h|help) usage ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac
