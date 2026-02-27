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

Debug examples (internal maintainers only):
  SIGEE_RUNTIME_ROOT=.sigee/.runtime orchestration_queue.sh init
  SIGEE_RUNTIME_ROOT=.sigee/.runtime orchestration_queue.sh add --queue planner-inbox --id FEAT-001 --title "결제 API 도입" --next-action "planner triage"
  SIGEE_RUNTIME_ROOT=.sigee/.runtime orchestration_queue.sh move --id FEAT-001 --from planner-inbox --to scientist-todo --status pending
  SIGEE_RUNTIME_ROOT=.sigee/.runtime orchestration_queue.sh claim --queue developer-todo --worker tech-developer
  SIGEE_RUNTIME_ROOT=.sigee/.runtime orchestration_queue.sh reconcile-exhausted --all --actor tech-planner
  SIGEE_RUNTIME_ROOT=.sigee/.runtime orchestration_queue.sh triage-blocked --limit 20
  SIGEE_RUNTIME_ROOT=.sigee/.runtime orchestration_queue.sh weekly-retry-summary --weeks 1
  SIGEE_RUNTIME_ROOT=.sigee/.runtime orchestration_queue.sh loop-status
  SIGEE_RUNTIME_ROOT=.sigee/.runtime orchestration_queue.sh next-prompt
  SIGEE_RUNTIME_ROOT=.sigee/.runtime SIGEE_QUEUE_ACTOR=tech-planner orchestration_queue.sh move --id FEAT-001 --from planner-review --to done --evidence ".sigee/.runtime/dag/state/last-run.json"
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

  local scenario_dir="$project_root/$RUNTIME_ROOT/dag/scenarios"
  if [[ -d "$scenario_dir" ]] && find "$scenario_dir" -maxdepth 1 -type f -name '*.scenario.yml' | grep -q .; then
    if [[ ! -x "$PRODUCT_TRUTH_VALIDATE_SCRIPT" ]]; then
      echo "ERROR: missing executable validator for done gate: $PRODUCT_TRUTH_VALIDATE_SCRIPT" >&2
      exit 1
    fi
    "$PRODUCT_TRUTH_VALIDATE_SCRIPT" \
      --project-root "$project_root" \
      --scenario-dir "$scenario_dir" \
      --require-scenarios >/dev/null
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
        echo "상태: 진행 가능 (CONTINUE)"
        echo "요약: 남은 제품 작업이 있어 자동 진행을 계속할 수 있습니다."
        echo "남은 제품 작업: $actionable_total"
        ;;
      STOP_DONE)
        echo "상태: 종료 (STOP_DONE)"
        echo "요약: 현재 처리 가능한 제품 작업이 없어 루프를 종료합니다."
        ;;
      STOP_USER_CONFIRMATION)
        echo "상태: 사용자 확인 필요로 중단 (STOP_USER_CONFIRMATION)"
        echo "요약: 사용자 확인이 필요한 의사결정이 있어 루프를 일시 중단합니다."
        echo "확인 필요 항목 수: $blocked_user_count"
        ;;
      *)
        echo "상태: $loop_status"
        echo "요약: $reason"
        ;;
    esac
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
      printf "%s" "planner-review 큐의 리뷰 대기 항목을 사용자 영향 기준으로 검토하고 done 승인 또는 재작업 라우팅을 결정해줘. 승인/반려 사유를 내용 중심으로 정리하고, 처리 후 다음 실행 프롬프트를 다시 제시해줘."
      ;;
    tech-planner:blocked)
      printf "%s" "blocked 큐를 우선순위와 에이징 기준으로 triage해줘. retry_budget 소진 항목은 재기획(우회/범위축소/예산 상향/중단) 중 하나를 결정하고 scientist-todo/developer-todo/planner-inbox로 재라우팅해줘."
      ;;
    tech-scientist:scientist-todo)
      printf "%s" "scientist-todo 큐의 최우선 항목부터 처리해줘. 문제 정식화, 근거 문헌, 적용 의사코드, 검증 계획을 포함한 evidence package를 만들고 planner-review로 넘겨줘."
      ;;
    tech-developer:developer-todo)
      printf "%s" "developer-todo 큐의 최우선 항목부터 strict 모드로 구현해줘. 테스트 근거를 남기고 planner-review로 handoff해줘."
      ;;
    tech-planner:planner-inbox)
      printf "%s" "planner-inbox 신규 요구를 분해해서 scientist/developer 라우팅 계획을 수립해줘. 모호성은 질문으로 해소하고, 실행 가능한 다음 프롬프트를 제시해줘."
      ;;
    tech-planner:blocked-user-confirmation)
      printf "%s" "루프를 종료하고 사용자 확정이 필요한 blocked 항목만 요약해줘. 각 항목에 대해 선택지(진행/중단/우회/범위축소)와 영향도를 함께 제시해줘."
      ;;
    tech-planner:completed)
      printf "%s" "현재 사이클은 완료되었어. 다음 기능 개발을 시작하기 위해 사용자 목표를 1개 선정하고, 실행 가능한 신규 계획을 수립해 planner-inbox부터 다시 루프를 시작해줘."
      ;;
    *)
      printf "%s" "현재 큐의 즉시 작업이 없으니 프로덕션 완성도를 높이는 다음 개선 파동을 기획해줘. 우선순위는 안정성, 관측성, 실패복구, 운영비용 최적화 순서로 잡아줘."
      ;;
  esac
}

next_prompt_message_user_facing() {
  local target="$1"
  local queue="$2"
  case "$target:$queue" in
    tech-planner:planner-review)
      printf "%s" "최근 완료된 변경을 사용자 영향 기준으로 승인/반려해줘. 반려 시에는 왜 사용자가 영향을 받는지와 재작업 방향만 간단히 정리해줘."
      ;;
    tech-planner:blocked)
      printf "%s" "현재 진행을 막는 의사결정 항목을 우선순위순으로 정리해줘. 각 항목마다 진행/우회/범위축소/중단 중 권장안을 제시해줘."
      ;;
    tech-scientist:scientist-todo)
      printf "%s" "남아있는 과학/수학 검증 과제 중 우선순위 1건부터 처리해줘. 근거, 적용 의사코드, 검증 계획을 제품 적용 중심으로 정리해줘."
      ;;
    tech-developer:developer-todo)
      printf "%s" "남아있는 구현 과제 중 우선순위 1건부터 strict 모드로 구현해줘. 사용자에게 보이는 변화와 테스트 근거를 중심으로 보고해줘."
      ;;
    tech-planner:planner-inbox)
      printf "%s" "신규 요구를 제품 관점으로 분해해 우선순위를 정해줘. 바로 실행 가능한 다음 작업 1건만 제시해줘."
      ;;
    tech-planner:blocked-user-confirmation)
      printf "%s" "사용자 확인이 필요한 의사결정 항목을 정리해줘. 각 항목마다 권장 선택지와 영향을 함께 설명해줘."
      ;;
    tech-planner:completed)
      printf "%s" "현재 사이클이 완료되었어. 다음 기능 개발을 시작할 수 있도록 사용자 목표를 1개 선정하고 실행 가능한 첫 작업 1건을 제안해줘."
      ;;
    *)
      printf "%s" "남은 제품 가치가 가장 큰 다음 작업 1건을 선정해줘. 선정 이유와 기대 사용자 영향을 함께 설명해줘."
      ;;
  esac
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
  printf '$%s\n' "$target"
  printf '%s\n' 'runtime-root = ${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}'
  printf '\n'
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

auto_lease_for_transition() {
  local to_queue="$1"
  local status="$2"
  local worker="$3"
  local now="$4"
  if [[ "$to_queue" == "planner-review" || "$to_queue" == "done" || "$to_queue" == "blocked" ]]; then
    printf "released:%s" "$now"
    return 0
  fi
  if [[ "$status" == "in_progress" ]]; then
    if [[ -n "$worker" ]]; then
      printf "held:%s:%s" "$worker" "$now"
      return 0
    fi
    printf "held:unknown:%s" "$now"
    return 0
  fi
  printf "none"
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

default_retry_budget() {
  printf "3"
}

default_phase_for_queue() {
  local queue="$1"
  local status="$2"
  case "$status" in
    done) printf "done" ;;
    review) printf "evidence_collected" ;;
    in_progress) printf "running" ;;
    blocked) printf "running" ;;
    pending)
      case "$queue" in
        planner-inbox) printf "planned" ;;
        *) printf "ready" ;;
      esac
      ;;
    *)
      printf "ready"
      ;;
  esac
}

default_error_class_for_queue() {
  local queue="$1"
  local status="$2"
  case "$queue:$status" in
    blocked:blocked) printf "soft_fail" ;;
    *) printf "none" ;;
  esac
}

validate_phase_transition() {
  local from_phase="$1"
  local to_phase="$2"
  local from_queue="$3"
  local to_queue="$4"
  local to_status="$5"

  if [[ "$from_phase" == "$to_phase" ]]; then
    return 0
  fi

  # Planner done-gate implicitly validates evidence_collected -> done.
  if [[ "$from_phase" == "evidence_collected" && "$to_phase" == "done" && "$to_queue" == "done" && "$to_status" == "done" ]]; then
    return 0
  fi

  case "$from_phase:$to_phase" in
    planned:ready|planned:running|ready:running|running:evidence_collected|running:ready|evidence_collected:verified|evidence_collected:ready|verified:done|verified:ready)
      return 0
      ;;
  esac

  if [[ "$to_queue" == "blocked" ]]; then
    case "$to_phase" in
      planned|ready|running|evidence_collected|verified)
        return 0
        ;;
    esac
  fi

  if [[ "$from_queue" == "blocked" && "$to_queue" != "done" ]]; then
    case "$to_phase" in
      ready|running)
        return 0
        ;;
    esac
  fi

  echo "ERROR: invalid lifecycle transition '${from_phase}' -> '${to_phase}' for move ${from_queue} -> ${to_queue} (status=${to_status})." >&2
  exit 1
}

default_status_for_queue() {
  local queue="$1"
  case "$queue" in
    planner-review) printf "review" ;;
    blocked) printf "blocked" ;;
    done) printf "done" ;;
    *) printf "pending" ;;
  esac
}

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
  local project_root="$1"
  local queue="$2"
  printf "%s/%s/orchestration/queues/%s.tsv" "$project_root" "$RUNTIME_ROOT" "$queue"
}

archive_dir_path() {
  local project_root="$1"
  printf "%s/%s/orchestration/archive" "$project_root" "$RUNTIME_ROOT"
}

archive_file_path() {
  local project_root="$1"
  local archive_dir
  archive_dir="$(archive_dir_path "$project_root")"
  printf "%s/done-%s.tsv" "$archive_dir" "$(date -u '+%Y-%m')"
}

history_dir_path() {
  local project_root="$1"
  printf "%s/%s/orchestration/history" "$project_root" "$RUNTIME_ROOT"
}

retry_history_file_path() {
  local project_root="$1"
  printf "%s/retry-events.tsv" "$(history_dir_path "$project_root")"
}

weekly_retry_summary_file_path() {
  local project_root="$1"
  local weeks="${2:-1}"
  local week_token
  week_token="$(date -u '+%G-W%V')"
  printf "%s/weekly-retry-summary-%s-last%sw.md" "$(history_dir_path "$project_root")" "$week_token" "$weeks"
}

normalize_queue_file_schema() {
  local queue_file="$1"
  local queue_name
  queue_name="$(basename "$queue_file" .tsv)"
  local tmp_file
  tmp_file="$(mktemp)"
  awk -F'\t' -v OFS='\t' -v queue_name="$queue_name" '
    BEGIN {
      print "id","status","worker","title","source","updated_at","note","next_action","lease","evidence_links","phase","error_class","attempt_count","retry_budget"
    }
    NR==1 { next }
    {
      for (i=1; i<=14; i++) {
        if (i > NF) $i=""
      }
      if ($11=="") {
        if ($2=="done") $11="done"
        else if ($2=="review") $11="evidence_collected"
        else if ($2=="in_progress") $11="running"
        else if ($2=="blocked") $11="running"
        else if ($2=="pending" && queue_name=="planner-inbox") $11="planned"
        else if ($2=="pending") $11="ready"
        else $11="ready"
      }
      if ($12=="") {
        if ($2=="blocked") $12="soft_fail"
        else $12="none"
      }
      if ($13=="" || $13 !~ /^[0-9]+$/) $13="0"
      if ($14=="" || $14 !~ /^[0-9]+$/ || $14 < 1) $14="3"
      print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14
    }
  ' "$queue_file" > "$tmp_file"
  mv "$tmp_file" "$queue_file"
}

ensure_queue_file() {
  local queue_file="$1"
  mkdir -p "$(dirname "$queue_file")"
  if [[ ! -f "$queue_file" ]]; then
    printf "%s\n" "$QUEUE_HEADER" > "$queue_file"
    return 0
  fi
  local header
  header="$(head -n1 "$queue_file" || true)"
  if [[ "$header" != "$QUEUE_HEADER" ]]; then
    normalize_queue_file_schema "$queue_file"
  fi
}

ensure_archive_file() {
  local archive_file="$1"
  mkdir -p "$(dirname "$archive_file")"
  if [[ ! -f "$archive_file" ]]; then
    printf "%s\n" "$ARCHIVE_HEADER" > "$archive_file"
    return 0
  fi
  local header
  header="$(head -n1 "$archive_file" || true)"
  if [[ "$header" != "$ARCHIVE_HEADER" ]]; then
    local tmp_file
    tmp_file="$(mktemp)"
    awk -F'\t' -v OFS='\t' '
      BEGIN {
        print "id","status","worker","title","source","updated_at","note","next_action","lease","evidence_links","phase","error_class","attempt_count","retry_budget","archived_at","archived_by"
      }
      NR==1 { next }
      {
        for (i=1; i<=16; i++) {
          if (i > NF) $i=""
        }
        if ($11=="") {
          if ($2=="done") $11="done"
          else if ($2=="review") $11="evidence_collected"
          else if ($2=="in_progress") $11="running"
          else if ($2=="blocked") $11="running"
          else if ($2=="pending") $11="ready"
          else $11="ready"
        }
        if ($12=="") {
          if ($2=="blocked") $12="soft_fail"
          else $12="none"
        }
        if ($13=="" || $13 !~ /^[0-9]+$/) $13="0"
        if ($14=="" || $14 !~ /^[0-9]+$/ || $14 < 1) $14="3"
        print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16
      }
    ' "$archive_file" > "$tmp_file"
    mv "$tmp_file" "$archive_file"
  fi
}

ensure_retry_history_file() {
  local history_file="$1"
  mkdir -p "$(dirname "$history_file")"
  if [[ ! -f "$history_file" ]]; then
    printf "%s\n" "$RETRY_HISTORY_HEADER" > "$history_file"
    return 0
  fi
  local header
  header="$(head -n1 "$history_file" || true)"
  if [[ "$header" != "$RETRY_HISTORY_HEADER" ]]; then
    local tmp_file
    tmp_file="$(mktemp)"
    awk -F'\t' -v OFS='\t' '
      BEGIN {
        print "ts_utc","event_type","id","from_queue","to_queue","status","error_class","attempt_count","retry_budget","priority","actor","note"
      }
      NR==1 { next }
      {
        for (i=1; i<=12; i++) {
          if (i > NF) $i=""
        }
        if ($1=="") $1="1970-01-01T00:00:00Z"
        if ($2=="") $2="retry_event"
        if ($6=="") $6="blocked"
        if ($7=="") $7="dependency_blocked"
        if ($8=="" || $8 !~ /^[0-9]+$/) $8="0"
        if ($9=="" || $9 !~ /^[0-9]+$/ || $9 < 1) $9="3"
        if ($10=="") $10="P2"
        if ($11=="") $11="planner"
        print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12
      }
    ' "$history_file" > "$tmp_file"
    mv "$tmp_file" "$history_file"
  fi
}

append_retry_history_event() {
  local project_root="$1"
  local event_type="$2"
  local id="$3"
  local from_queue="$4"
  local to_queue="$5"
  local status="$6"
  local error_class="$7"
  local attempt_count="$8"
  local retry_budget="$9"
  local priority="${10}"
  local actor="${11}"
  local note="${12}"
  local history_file
  history_file="$(retry_history_file_path "$project_root")"
  ensure_retry_history_file "$history_file"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$(sanitize_field "$(timestamp_utc)")" \
    "$(sanitize_field "$event_type")" \
    "$(sanitize_field "$id")" \
    "$(sanitize_field "$from_queue")" \
    "$(sanitize_field "$to_queue")" \
    "$(sanitize_field "$status")" \
    "$(sanitize_field "$error_class")" \
    "$(sanitize_field "$attempt_count")" \
    "$(sanitize_field "$retry_budget")" \
    "$(sanitize_field "$priority")" \
    "$(sanitize_field "$actor")" \
    "$(sanitize_field "$note")" >> "$history_file"
}

priority_label_for_row() {
  local title="${1:-}"
  local note="${2:-}"
  local next_action="${3:-}"
  local error_class="${4:-none}"
  local attempt_count="${5:-0}"
  local retry_budget="${6:-3}"
  local merged lowered tag

  merged="$title $note $next_action"
  lowered="$(to_lower "$merged")"
  for tag in p0 p1 p2 p3; do
    if [[ "$lowered" == *"$tag"* ]]; then
      case "$tag" in
        p0) printf "P0" ;;
        p1) printf "P1" ;;
        p2) printf "P2" ;;
        p3) printf "P3" ;;
      esac
      return 0
    fi
  done

  if [[ ! "$attempt_count" =~ ^[0-9]+$ ]]; then
    attempt_count="0"
  fi
  if [[ ! "$retry_budget" =~ ^[0-9]+$ || "$retry_budget" -lt 1 ]]; then
    retry_budget="3"
  fi

  if [[ "$error_class" == "hard_fail" ]]; then
    printf "P1"
    return 0
  fi
  if [[ "$attempt_count" -ge "$retry_budget" ]]; then
    printf "P1"
    return 0
  fi
  if [[ "$error_class" == "dependency_blocked" || "$error_class" == "soft_fail" ]]; then
    printf "P2"
    return 0
  fi
  printf "P3"
}

refresh_weekly_retry_summary() {
  local project_root="$1"
  local weeks="${2:-1}"
  local history_file blocked_file output_file

  history_file="$(retry_history_file_path "$project_root")"
  blocked_file="$(queue_file_path "$project_root" "blocked")"
  output_file="$(weekly_retry_summary_file_path "$project_root" "$weeks")"
  ensure_retry_history_file "$history_file"
  ensure_queue_file "$blocked_file"

  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  python3 - "$history_file" "$blocked_file" "$output_file" "$weeks" <<'PY'
import csv
import datetime as dt
from pathlib import Path
import sys

history_path = Path(sys.argv[1])
blocked_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])
weeks = max(1, int(sys.argv[4]))
window_days = weeks * 7
now = dt.datetime.utcnow()
window_start = now - dt.timedelta(days=window_days)

def parse_ts(value: str):
    if not value:
        return None
    try:
        return dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return None

events = []
if history_path.exists():
    with history_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            ts = parse_ts((row.get("ts_utc") or "").strip())
            if ts is None or ts < window_start:
                continue
            events.append((ts, row))

open_exhausted = []
if blocked_path.exists():
    with blocked_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            try:
                attempts = int((row.get("attempt_count") or "0").strip())
                budget = int((row.get("retry_budget") or "3").strip())
            except Exception:
                attempts, budget = 0, 3
            if budget < 1:
                budget = 3
            if attempts >= budget:
                open_exhausted.append(row)

events_total = len(events)
affected_ids = sorted({(row.get("id") or "").strip() for _, row in events if (row.get("id") or "").strip()})

by_queue = {}
by_priority = {}
for _, row in events:
    q = (row.get("from_queue") or "unknown").strip() or "unknown"
    p = (row.get("priority") or "P2").strip() or "P2"
    by_queue[q] = by_queue.get(q, 0) + 1
    by_priority[p] = by_priority.get(p, 0) + 1

def row_updated_at(row):
    return parse_ts((row.get("updated_at") or "").strip()) or dt.datetime(1970, 1, 1)

open_exhausted.sort(key=row_updated_at)

output_path.parent.mkdir(parents=True, exist_ok=True)
with output_path.open("w", encoding="utf-8") as out:
    out.write("# Retry Budget Weekly Summary\n\n")
    out.write(f"- window_days: {window_days}\n")
    out.write(f"- window_start_utc: {window_start.strftime('%Y-%m-%dT%H:%M:%SZ')}\n")
    out.write(f"- generated_at_utc: {now.strftime('%Y-%m-%dT%H:%M:%SZ')}\n")
    out.write(f"- retry_budget_exhausted_events: {events_total}\n")
    out.write(f"- affected_ticket_count: {len(affected_ids)}\n")
    out.write(f"- open_blocked_exhausted_count: {len(open_exhausted)}\n\n")

    out.write("## Source Queue Distribution\n\n")
    out.write("| queue | events |\n")
    out.write("|---|---:|\n")
    if by_queue:
        for q in sorted(by_queue):
            out.write(f"| {q} | {by_queue[q]} |\n")
    else:
        out.write("| (none) | 0 |\n")
    out.write("\n")

    out.write("## Priority Distribution\n\n")
    out.write("| priority | events |\n")
    out.write("|---|---:|\n")
    if by_priority:
        for p in sorted(by_priority):
            out.write(f"| {p} | {by_priority[p]} |\n")
    else:
        out.write("| (none) | 0 |\n")
    out.write("\n")

    out.write("## Oldest Open Exhausted Blocked Tickets\n\n")
    out.write("| id | updated_at | attempt_count | retry_budget | next_action |\n")
    out.write("|---|---|---:|---:|---|\n")
    if open_exhausted:
        for row in open_exhausted[:20]:
            out.write(
                f"| {(row.get('id') or '').strip()} | {(row.get('updated_at') or '').strip()} | "
                f"{(row.get('attempt_count') or '').strip()} | {(row.get('retry_budget') or '').strip()} | "
                f"{(row.get('next_action') or '').strip()} |\n"
            )
    else:
        out.write("| (none) | - | 0 | 0 | - |\n")
PY
}

ensure_standard_queues() {
  local project_root="$1"
  local queue
  for queue in "${STANDARD_QUEUES[@]}"; do
    ensure_queue_file "$(queue_file_path "$project_root" "$queue")"
  done
}

ensure_template_file() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  if [[ ! -f "$path" ]]; then
    printf "%s\n" "$content" > "$path"
  fi
}

ensure_default_templates() {
  local project_root="$1"
  local templates_root="$project_root/.sigee/templates"

  ensure_template_file "$templates_root/ops-rules.md" "# 운영규약

## 목적
- 프로젝트 협업 규칙과 상태 전이 규칙을 명시한다.

## 티켓 관리
- 필수 필드: \`Status\`, \`Next Action\`, \`Lease\`, \`Evidence Links\`
- 라이프사이클 단계: \`planned -> ready -> running -> evidence_collected -> verified -> done\`
- 실패 분류: \`none|soft_fail|hard_fail|dependency_blocked\`
- 기본 전이: \`planner-inbox -> scientist-todo|developer-todo -> planner-review -> done\`
- 예외 전이: \`* -> blocked\`, \`blocked -> planner-inbox|scientist-todo|developer-todo\`
- 큐 운영(루프 모드): \`planner-inbox -> scientist/developer -> planner-review -> done|requeue\`
- \`done\` 전이는 planner 리뷰에서만 허용

## 글로벌 정책
- 삭제 금지: 문서는 삭제하지 않고 \`DEPRECATED\` 표기 후 아카이브한다.
- \`done\` 전이는 planner 전용이다.

## 운영 로그
- 변경 사유
- 결정 사항
- 후속 액션"

  ensure_template_file "$templates_root/agent-ticket.md" "# 에이전트 티켓

## 메타
- Ticket ID:
- Summary:
- Queue:
- Status:
- Next Action:
- Lease:

## 요구사항
- ReqIDs:
- Acceptance Criteria:

## 작업 기록
- Progress Log:
- Evidence Links:

## 핸드오프
- Decision Required:
- Blocker:
- Next Step:"

  ensure_template_file "$templates_root/handoff-note.md" "# 핸드오프 노트

## 컨텍스트
- 작업 요약:
- 현재 상태:

## 완료/미완료
- Completed:
- Remaining:

## 리스크
- Risk:
- Mitigation:

## 다음 액션
- Next Action:
- Evidence Links:"

  ensure_template_file "$templates_root/weekly-board.md" "# 업무 보드(주간)

## planner-inbox
-

## scientist-todo
-

## developer-todo
-

## planner-review
-

## done
-

## blocked
-

## 주간 보고
- Highlights:
- Risks:
- Next Week:"

  ensure_template_file "$templates_root/queue-ticket.md" "# Queue Ticket Template

- ID:
- Queue:
- Status:
- Worker:
- Title:
- Source:
- Updated At:
- Note:
- Next Action:
- Lease:
- Evidence Links:
- Phase:
- Error Class:
- Attempt Count:
- Retry Budget:

## Evidence

- Links:
- Verification:

## Next Routing

- Next Queue:
- Reason:"
}

bootstrap_runtime() {
  local project_root="$1"
  mkdir -p \
    "$project_root/$RUNTIME_ROOT/plans" \
    "$project_root/$RUNTIME_ROOT/dag/scenarios" \
    "$project_root/$RUNTIME_ROOT/dag/pipelines" \
    "$project_root/$RUNTIME_ROOT/dag/state" \
    "$project_root/$RUNTIME_ROOT/evidence" \
    "$project_root/$RUNTIME_ROOT/reports" \
    "$project_root/$RUNTIME_ROOT/orchestration/archive" \
    "$project_root/$RUNTIME_ROOT/orchestration/history" \
    "$project_root/$RUNTIME_ROOT/locks"

  ensure_standard_queues "$project_root"
  ensure_archive_file "$(archive_file_path "$project_root")"
  ensure_retry_history_file "$(retry_history_file_path "$project_root")"
  ensure_default_templates "$project_root"

  if [[ -x "$GITIGNORE_GUARD_SCRIPT" ]]; then
    "$GITIGNORE_GUARD_SCRIPT" "$project_root"
  fi
}

append_row() {
  local queue_file="$1"
  local id="$2"
  local status="$3"
  local worker="$4"
  local title="$5"
  local source="$6"
  local updated_at="$7"
  local note="$8"
  local next_action="$9"
  local lease="${10}"
  local evidence_links="${11}"
  local phase="${12:-ready}"
  local error_class="${13:-none}"
  local attempt_count="${14:-0}"
  local retry_budget="${15:-$(default_retry_budget)}"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$(sanitize_field "$id")" \
    "$(sanitize_field "$status")" \
    "$(sanitize_field "$worker")" \
    "$(sanitize_field "$title")" \
    "$(sanitize_field "$source")" \
    "$(sanitize_field "$updated_at")" \
    "$(sanitize_field "$note")" \
    "$(sanitize_field "$next_action")" \
    "$(sanitize_field "$lease")" \
    "$(sanitize_field "$evidence_links")" \
    "$(sanitize_field "$phase")" \
    "$(sanitize_field "$error_class")" \
    "$(sanitize_field "$attempt_count")" \
    "$(sanitize_field "$retry_budget")" >> "$queue_file"
}

append_archive_row() {
  local archive_file="$1"
  local id="$2"
  local status="$3"
  local worker="$4"
  local title="$5"
  local source="$6"
  local updated_at="$7"
  local note="$8"
  local next_action="$9"
  local lease="${10}"
  local evidence_links="${11}"
  local phase="${12:-done}"
  local error_class="${13:-none}"
  local attempt_count="${14:-0}"
  local retry_budget="${15:-$(default_retry_budget)}"
  local archived_at="${16}"
  local archived_by="${17}"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$(sanitize_field "$id")" \
    "$(sanitize_field "$status")" \
    "$(sanitize_field "$worker")" \
    "$(sanitize_field "$title")" \
    "$(sanitize_field "$source")" \
    "$(sanitize_field "$updated_at")" \
    "$(sanitize_field "$note")" \
    "$(sanitize_field "$next_action")" \
    "$(sanitize_field "$lease")" \
    "$(sanitize_field "$evidence_links")" \
    "$(sanitize_field "$phase")" \
    "$(sanitize_field "$error_class")" \
    "$(sanitize_field "$attempt_count")" \
    "$(sanitize_field "$retry_budget")" \
    "$(sanitize_field "$archived_at")" \
    "$(sanitize_field "$archived_by")" >> "$archive_file"
}

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
