#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  dag_stress.sh [--pipeline-dir <path>] [--class <50|200|500|all>] [--run] [--budget-regression-pct <n>] [--baseline <tsv>] [--project-root <path>]

Examples:
  SIGEE_RUNTIME_ROOT=.sigee/.runtime dag_stress.sh --class all --run
  SIGEE_RUNTIME_ROOT=.sigee/.runtime dag_stress.sh --class 200 --run --budget-regression-pct 35 --baseline .sigee/.runtime/evidence/dag/stress/stress-summary.tsv
USAGE
}

RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"
if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAG_BUILD_SCRIPT="$SCRIPT_DIR/dag_build.sh"
DAG_RUN_SCRIPT="$SCRIPT_DIR/dag_run.sh"

PIPELINE_DIR="${RUNTIME_ROOT}/dag/pipelines"
CLASS="all"
DO_FULL_RUN=0
BUDGET_REGRESSION_PCT=35
BASELINE_FILE=""
PROJECT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pipeline-dir)
      PIPELINE_DIR="${2:-}"
      shift 2
      ;;
    --class)
      CLASS="${2:-}"
      shift 2
      ;;
    --run)
      DO_FULL_RUN=1
      shift
      ;;
    --budget-regression-pct)
      BUDGET_REGRESSION_PCT="${2:-}"
      shift 2
      ;;
    --baseline)
      BASELINE_FILE="${2:-}"
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

if [[ ! "$BUDGET_REGRESSION_PCT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --budget-regression-pct must be a non-negative integer." >&2
  exit 1
fi

if [[ -n "$PROJECT_ROOT" ]]; then
  if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "ERROR: project root not found: $PROJECT_ROOT" >&2
    exit 1
  fi
  PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel)"
else
  PROJECT_ROOT="$(pwd)"
fi

if [[ ! -x "$DAG_BUILD_SCRIPT" || ! -x "$DAG_RUN_SCRIPT" ]]; then
  echo "ERROR: required scripts are not executable (dag_build.sh / dag_run.sh)." >&2
  exit 1
fi

PIPELINE_DIR_ABS="$PROJECT_ROOT/$PIPELINE_DIR"
STRESS_DIR="$PROJECT_ROOT/$RUNTIME_ROOT/evidence/dag/stress"
STATE_FILE="$PROJECT_ROOT/$RUNTIME_ROOT/dag/state/last-run.json"
SUMMARY_TSV="$STRESS_DIR/stress-summary.tsv"
BUDGET_REPORT="$STRESS_DIR/stress-budget-report.txt"
mkdir -p "$PIPELINE_DIR_ABS" "$STRESS_DIR"

declare -a CLASSES
case "$CLASS" in
  all) CLASSES=(50 200 500) ;;
  50|200|500) CLASSES=("$CLASS") ;;
  *)
    echo "ERROR: --class must be one of 50, 200, 500, all." >&2
    exit 1
    ;;
esac

extract_state_field() {
  local field="$1"
  local file="$2"
  sed -nE "s/^[[:space:]]*\"${field}\"[[:space:]]*:[[:space:]]*\"?([^\",}]*)\"?.*$/\\1/p" "$file" | head -n1
}

run_profile() {
  local pipeline_file="$1"
  local mode="$2"
  local log_file="$3"
  local rc=0

  if [[ "$mode" == "dry" ]]; then
    "$DAG_RUN_SCRIPT" "$pipeline_file" --dry-run >"$log_file" 2>&1 || rc=$?
  else
    "$DAG_RUN_SCRIPT" "$pipeline_file" >"$log_file" 2>&1 || rc=$?
  fi

  local status duration
  status="FAIL"
  duration="0"
  if [[ -f "$STATE_FILE" ]]; then
    status="$(extract_state_field "status" "$STATE_FILE")"
    duration="$(extract_state_field "duration_seconds" "$STATE_FILE")"
  fi
  if [[ -z "$status" ]]; then
    status="FAIL"
  fi
  if [[ ! "$duration" =~ ^[0-9]+$ ]]; then
    duration="0"
  fi
  if [[ "$rc" -ne 0 ]]; then
    status="FAIL"
  fi
  printf "%s|%s|%s\n" "$status" "$duration" "$log_file"
}

baseline_duration() {
  local klass="$1"
  local baseline="$2"
  if [[ ! -f "$baseline" ]]; then
    printf "0"
    return 0
  fi
  awk -F'\t' -v c="$klass" 'NR==1{next} $1==c {print $5; exit} END {if (!found) print 0}' "$baseline"
}

regression_pct() {
  local base="$1"
  local current="$2"
  awk -v b="$base" -v c="$current" 'BEGIN {
    if (b <= 0) { print 0; exit }
    printf "%.2f", ((c - b) / b) * 100
  }'
}

printf "class\tnodes\tdry_status\tdry_duration_seconds\tfull_status\tfull_duration_seconds\tpipeline_file\tdry_log\tfull_log\n" > "$SUMMARY_TSV"
printf "budget_regression_pct=%s\n" "$BUDGET_REGRESSION_PCT" > "$BUDGET_REPORT"

BUDGET_FAIL=0

for klass in "${CLASSES[@]}"; do
  nodes="$klass"
  pipeline_file="$PIPELINE_DIR_ABS/synthetic-${klass}.pipeline.yml"
  dry_log="$STRESS_DIR/synthetic-${klass}-dry.log"
  full_log="$STRESS_DIR/synthetic-${klass}-full.log"

  "$DAG_BUILD_SCRIPT" --out "$pipeline_file" --synthetic-nodes "$nodes" >/dev/null

  dry_result="$(run_profile "$pipeline_file" "dry" "$dry_log")"
  dry_status="${dry_result%%|*}"
  dry_rest="${dry_result#*|}"
  dry_duration="${dry_rest%%|*}"
  _dry_log_path="${dry_rest#*|}"

  full_status="SKIPPED"
  full_duration="0"
  if [[ "$DO_FULL_RUN" -eq 1 ]]; then
    full_result="$(run_profile "$pipeline_file" "full" "$full_log")"
    full_status="${full_result%%|*}"
    full_rest="${full_result#*|}"
    full_duration="${full_rest%%|*}"
    _full_log_path="${full_rest#*|}"
  else
    _full_log_path="-"
  fi

  if [[ "$DO_FULL_RUN" -eq 1 && -n "$BASELINE_FILE" && "$full_status" == "PASS" ]]; then
    base_duration="$(baseline_duration "$klass" "$BASELINE_FILE")"
    if [[ ! "$base_duration" =~ ^[0-9]+$ ]]; then
      base_duration="0"
    fi
    if [[ "$base_duration" -gt 0 ]]; then
      regress="$(regression_pct "$base_duration" "$full_duration")"
      printf "class=%s base=%ss current=%ss regression_pct=%s\n" "$klass" "$base_duration" "$full_duration" "$regress" >> "$BUDGET_REPORT"
      if awk -v r="$regress" -v b="$BUDGET_REGRESSION_PCT" 'BEGIN {exit (r > b) ? 0 : 1}'; then
        BUDGET_FAIL=1
        printf "BUDGET_FAIL class=%s regression_pct=%s threshold=%s\n" "$klass" "$regress" "$BUDGET_REGRESSION_PCT" >> "$BUDGET_REPORT"
      fi
    fi
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$klass" \
    "$nodes" \
    "$dry_status" \
    "$dry_duration" \
    "$full_status" \
    "$full_duration" \
    "$pipeline_file" \
    "$_dry_log_path" \
    "$_full_log_path" >> "$SUMMARY_TSV"
done

echo "Stress summary: $SUMMARY_TSV"
echo "Budget report: $BUDGET_REPORT"

if [[ "$BUDGET_FAIL" -eq 1 ]]; then
  echo "ERROR: stress regression budget exceeded. See $BUDGET_REPORT" >&2
  exit 1
fi
