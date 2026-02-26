#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  codex_flow.sh <plan-file> [--mode strict] [--resume] [--skip-lint] [--write-report]

Examples:
  SIGEE_RUNTIME_ROOT=.codex codex_flow.sh .codex/plans/auth-refactor.md
  SIGEE_RUNTIME_ROOT=.runtime codex_flow.sh .runtime/plans/auth-refactor.md --mode strict
  SIGEE_RUNTIME_ROOT=.runtime codex_flow.sh .runtime/plans/auth-refactor.md --resume
  SIGEE_RUNTIME_ROOT=.runtime codex_flow.sh .runtime/plans/auth-refactor.md --write-report
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

PLAN_FILE="$1"
shift

MODE="strict"
RESUME=0
SKIP_LINT=0
WRITE_REPORT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --resume)
      RESUME=1
      shift
      ;;
    --skip-lint)
      SKIP_LINT=1
      shift
      ;;
    --write-report)
      WRITE_REPORT=1
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_LINT_SCRIPT="$SCRIPT_DIR/../../tech-planner/scripts/plan_lint.sh"
PLAN_RUN_SCRIPT="$SCRIPT_DIR/plan_run.sh"
REPORT_SCRIPT="$SCRIPT_DIR/report_generate.sh"

if [[ "$SKIP_LINT" -eq 0 ]]; then
  if [[ ! -x "$PLAN_LINT_SCRIPT" ]]; then
    echo "ERROR: plan_lint.sh not executable: $PLAN_LINT_SCRIPT" >&2
    exit 1
  fi
  echo "[1/3] Plan lint"
  "$PLAN_LINT_SCRIPT" "$PLAN_FILE"
else
  echo "[1/3] Plan lint skipped (--skip-lint)"
fi

if [[ ! -x "$PLAN_RUN_SCRIPT" ]]; then
  echo "ERROR: plan_run.sh not executable: $PLAN_RUN_SCRIPT" >&2
  exit 1
fi
if [[ "$WRITE_REPORT" -eq 1 && ! -x "$REPORT_SCRIPT" ]]; then
  echo "ERROR: report_generate.sh not executable: $REPORT_SCRIPT" >&2
  exit 1
fi

echo "[2/3] Plan run"
RUN_ARGS=("$PLAN_FILE" "--mode" "$MODE")
if [[ "$RESUME" -eq 1 ]]; then
  RUN_ARGS+=("--resume")
fi
if [[ "$WRITE_REPORT" -eq 1 ]]; then
  RUN_ARGS+=("--write-report")
fi
"$PLAN_RUN_SCRIPT" "${RUN_ARGS[@]}"
if [[ "$WRITE_REPORT" -eq 1 ]]; then
  echo "[3/3] Report generated via plan_run (--write-report)."
else
  echo "[3/3] Report generate skipped (default). Use --write-report to persist files."
fi

echo "codex_flow completed successfully."
