#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  plan_run.sh <plan-file> [--mode strict] [--resume] [--write-report]

Examples:
  SIGEE_RUNTIME_ROOT=.codex plan_run.sh .codex/plans/auth-refactor.md
  SIGEE_RUNTIME_ROOT=.runtime plan_run.sh .runtime/plans/auth-refactor.md --mode strict
  SIGEE_RUNTIME_ROOT=.runtime plan_run.sh .runtime/plans/auth-refactor.md --resume
  SIGEE_RUNTIME_ROOT=.runtime plan_run.sh .runtime/plans/auth-refactor.md --write-report
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

PLAN_FILE="$1"
shift
MODE="strict"
GENERATE_REPORT=0
RESUME=0
RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.codex}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITIGNORE_GUARD_SCRIPT="$SCRIPT_DIR/../../tech-planner/scripts/sigee_gitignore_guard.sh"

if [[ "$RUNTIME_ROOT" == */* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a single directory name (e.g. .codex or .runtime)" >&2
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-report)
      # Backward-compatible alias: report generation is already off by default.
      GENERATE_REPORT=0
      shift
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --write-report)
      GENERATE_REPORT=1
      shift
      ;;
    --resume)
      RESUME=1
      shift
      ;;
    --help)
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

if [[ "$MODE" != "strict" ]]; then
  echo "ERROR: --mode must be 'strict' (hard TDD enforcement)" >&2
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: Plan file not found: $PLAN_FILE" >&2
  exit 1
fi

ABS_PLAN="$(cd "$(dirname "$PLAN_FILE")" && pwd)/$(basename "$PLAN_FILE")"
NORM_PLAN="${ABS_PLAN//\\//}"
if [[ "$NORM_PLAN" != *"/${RUNTIME_ROOT}/plans/"* ]] || [[ "$NORM_PLAN" != *.md ]]; then
  echo "ERROR: Plan path must be under ${RUNTIME_ROOT}/plans and end with .md" >&2
  exit 1
fi

PLAN_ID="$(sed -nE 's/^id:[[:space:]]*([a-zA-Z0-9._-]+)[[:space:]]*$/\1/p' "$PLAN_FILE" | head -n1)"
if [[ -z "$PLAN_ID" ]]; then
  PLAN_ID="$(basename "$PLAN_FILE" .md)"
fi

PROJECT_ROOT="${NORM_PLAN%%/${RUNTIME_ROOT}/plans/*}"
if [[ -z "$PROJECT_ROOT" || "$PROJECT_ROOT" == "$NORM_PLAN" ]]; then
  PROJECT_ROOT="$(cd "$(dirname "$PLAN_FILE")/../.." && pwd)"
fi
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)"
else
  REPO_ROOT="$PROJECT_ROOT"
fi

EVIDENCE_DIR="$PROJECT_ROOT/${RUNTIME_ROOT}/evidence/$PLAN_ID"
REPORT_SCRIPT="$SCRIPT_DIR/report_generate.sh"
RESULTS_FILE="$EVIDENCE_DIR/verification-results.tsv"
START_TASK_INDEX=0
TOTAL_TASKS=0

if [[ ! -x "$GITIGNORE_GUARD_SCRIPT" ]]; then
  echo "ERROR: Missing executable gitignore guard: $GITIGNORE_GUARD_SCRIPT" >&2
  exit 1
fi
"$GITIGNORE_GUARD_SCRIPT" "$PROJECT_ROOT"

mkdir -p "$EVIDENCE_DIR"
if [[ "$RESUME" -eq 1 && -f "$RESULTS_FILE" ]]; then
  LAST_FAIL_ROW="$(awk -F'\t' 'NR>1 && $4=="FAIL"{row=$0} END{print row}' "$RESULTS_FILE")"
  if [[ -n "$LAST_FAIL_ROW" ]]; then
    IFS=$'\t' read -r PREV_TASK_NO PREV_TITLE PREV_KIND PREV_STATUS PREV_LOG PREV_CMD <<<"$LAST_FAIL_ROW"
    echo "Resume context detected from previous run:"
    echo "- task: ${PREV_TITLE}"
    echo "- kind: ${PREV_KIND}"
    echo "- log: ${PREV_LOG}"
    echo "- command: ${PREV_CMD}"
  else
    echo "Resume requested, but no previous FAIL record was found."
  fi
  ARCHIVE_RESULTS="$EVIDENCE_DIR/verification-results-$(date +%Y%m%d-%H%M%S).tsv"
  cp "$RESULTS_FILE" "$ARCHIVE_RESULTS"
  echo "Archived previous verification results: $ARCHIVE_RESULTS"
fi

{
  echo -e "task_no\ttitle\tkind\tstatus\tlog_path\tcommand"
} > "$RESULTS_FILE"

run_command() {
  local command="$1"
  local log_path="$2"
  local status=0
  (
    cd "$REPO_ROOT"
    echo "+ $command"
    bash -lc "$command"
  ) >"$log_path" 2>&1 || status=$?
  return $status
}

extract_field_command() {
  local block="$1"
  local field="$2"
  local cmd

  cmd="$(printf "%s\n" "$block" | sed -nE "s/^[[:space:]]*- ${field}[[:space:]]*\`(.*)\`[[:space:]]*$/\1/p" | head -n1)"
  printf "%s" "$cmd"
}

mark_task_done() {
  local line_no="$1"
  local tmp_file
  tmp_file="$(mktemp)"
  awk -v target="$line_no" '
    NR == target { sub(/^- \[ \]/, "- [x]") }
    { print }
  ' "$PLAN_FILE" > "$tmp_file"
  mv "$tmp_file" "$PLAN_FILE"
}

TASK_LINES=()
while IFS= read -r line; do
  TASK_LINES+=("$line")
done < <(grep -nE '^- \[ \]' "$PLAN_FILE" || true)
if [[ ${#TASK_LINES[@]} -eq 0 ]]; then
  echo "No unchecked tasks found: $PLAN_FILE"
  exit 0
fi

TOTAL_LINES="$(wc -l < "$PLAN_FILE" | tr -d ' ')"
TOTAL_TASKS="${#TASK_LINES[@]}"
TASK_INDEX=0

if [[ "$RESUME" -eq 1 && -n "${PREV_TITLE:-}" ]]; then
  for i in "${!TASK_LINES[@]}"; do
    CAND_TEXT="${TASK_LINES[$i]#*:}"
    CAND_TITLE="$(printf "%s" "$CAND_TEXT" | sed -E 's/^- \[ \][[:space:]]*//')"
    if [[ "$CAND_TITLE" == "$PREV_TITLE" ]]; then
      START_TASK_INDEX="$i"
      break
    fi
  done
  if [[ "$START_TASK_INDEX" -gt 0 ]]; then
    echo "Resuming from task index $((START_TASK_INDEX + 1))/${TOTAL_TASKS}: $PREV_TITLE"
  fi
fi

for ((i=START_TASK_INDEX; i<TOTAL_TASKS; i++)); do
  TASK_INDEX=$((TASK_INDEX + 1))
  TASK_LINE="${TASK_LINES[$i]%%:*}"
  TASK_TEXT="${TASK_LINES[$i]#*:}"
  TASK_TITLE="$(printf "%s" "$TASK_TEXT" | sed -E 's/^- \[ \][[:space:]]*//')"
  TASK_SLUG="$(printf "%s" "$TASK_TITLE" | tr -cs '[:alnum:]' '_' | sed 's/^_//; s/_$//' | cut -c1-48)"
  if [[ -z "$TASK_SLUG" ]]; then
    TASK_SLUG="task_${TASK_INDEX}"
  fi

  if [[ $i -lt $(( ${#TASK_LINES[@]} - 1 )) ]]; then
    NEXT_TASK_LINE="${TASK_LINES[$((i + 1))]%%:*}"
    END_LINE=$((NEXT_TASK_LINE - 1))
  else
    END_LINE="$TOTAL_LINES"
  fi

  BLOCK="$(sed -n "$((TASK_LINE + 1)),$END_LINE p" "$PLAN_FILE")"
  EXEC_CMD="$(extract_field_command "$BLOCK" "Execute:")"
  VERIFY_CMD="$(extract_field_command "$BLOCK" "Verification:")"

  if [[ "$EXEC_CMD" == "true" || "$EXEC_CMD" == ":" ]]; then
    echo "FAILED: Task '$TASK_TITLE' has no-op Execute command ('$EXEC_CMD') in hard TDD mode." >&2
    exit 1
  fi
  if [[ "$VERIFY_CMD" == "true" || "$VERIFY_CMD" == ":" ]]; then
    echo "FAILED: Task '$TASK_TITLE' has no-op Verification command ('$VERIFY_CMD') in hard TDD mode." >&2
    exit 1
  fi

  DISPLAY_INDEX=$((i + 1))
  echo "[$DISPLAY_INDEX/${TOTAL_TASKS}] $TASK_TITLE"

  if [[ -z "$EXEC_CMD" ]]; then
    echo "FAILED: Task '$TASK_TITLE' has no Execute command in hard TDD mode." >&2
    exit 1
  fi
  EXEC_LOG="$EVIDENCE_DIR/${TASK_INDEX}-${TASK_SLUG}-execute.log"
  if run_command "$EXEC_CMD" "$EXEC_LOG"; then
    printf "%s\t%s\texecute\tPASS\t%s\t%s\n" "$TASK_INDEX" "$TASK_TITLE" "$EXEC_LOG" "$EXEC_CMD" >> "$RESULTS_FILE"
  else
    printf "%s\t%s\texecute\tFAIL\t%s\t%s\n" "$TASK_INDEX" "$TASK_TITLE" "$EXEC_LOG" "$EXEC_CMD" >> "$RESULTS_FILE"
    echo "FAILED: Execute command for task '$TASK_TITLE'. See: $EXEC_LOG" >&2
    exit 1
  fi

  if [[ -z "$VERIFY_CMD" ]]; then
    echo "FAILED: Task '$TASK_TITLE' has no Verification command in hard TDD mode." >&2
    exit 1
  fi
  VERIFY_LOG="$EVIDENCE_DIR/${TASK_INDEX}-${TASK_SLUG}-verify.log"
  if run_command "$VERIFY_CMD" "$VERIFY_LOG"; then
    printf "%s\t%s\tverify\tPASS\t%s\t%s\n" "$TASK_INDEX" "$TASK_TITLE" "$VERIFY_LOG" "$VERIFY_CMD" >> "$RESULTS_FILE"
    mark_task_done "$TASK_LINE"
  else
    printf "%s\t%s\tverify\tFAIL\t%s\t%s\n" "$TASK_INDEX" "$TASK_TITLE" "$VERIFY_LOG" "$VERIFY_CMD" >> "$RESULTS_FILE"
    echo "FAILED: Verification command for task '$TASK_TITLE'. See: $VERIFY_LOG" >&2
    exit 1
  fi
done

echo "Completed task loop for: $PLAN_FILE"
echo "Evidence: $EVIDENCE_DIR"

if [[ "$GENERATE_REPORT" -eq 1 ]]; then
  if [[ -x "$REPORT_SCRIPT" ]]; then
    "$REPORT_SCRIPT" "$PLAN_FILE"
  else
    echo "WARN: report_generate.sh is not executable. Skipping report generation." >&2
  fi
else
  echo "Report file generation skipped by default. Use --write-report to persist report files."
fi
