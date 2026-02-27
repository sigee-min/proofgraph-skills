#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  codex_flow.sh <plan-file> [--mode strict] [--resume] [--write-report]

Note:
  Deprecated compatibility shim.
  Execution is delegated to plan_run.sh so the runtime has a single execution path.
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
WRITE_REPORT=0
UNSUPPORTED_SKIP_LINT=0

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
    --write-report)
      WRITE_REPORT=1
      shift
      ;;
    --skip-lint)
      # Kept only for backward compatibility; lint orchestration belongs to planner/plan_lint.
      UNSUPPORTED_SKIP_LINT=1
      shift
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

if [[ "$MODE" != "strict" ]]; then
  echo "ERROR: --mode must be 'strict'" >&2
  exit 1
fi

if [[ "$UNSUPPORTED_SKIP_LINT" -eq 1 ]]; then
  echo "WARN: --skip-lint is ignored in this compatibility shim." >&2
fi

echo "codex_flow is deprecated. Delegating to plan_run.sh."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_RUN_SCRIPT="$SCRIPT_DIR/plan_run.sh"

if [[ ! -x "$PLAN_RUN_SCRIPT" ]]; then
  echo "ERROR: plan_run.sh not executable: $PLAN_RUN_SCRIPT" >&2
  exit 1
fi

ARGS=("$PLAN_FILE" "--mode" "strict")
if [[ "$RESUME" -eq 1 ]]; then
  ARGS+=("--resume")
fi
if [[ "$WRITE_REPORT" -eq 1 ]]; then
  ARGS+=("--write-report")
fi

exec "$PLAN_RUN_SCRIPT" "${ARGS[@]}"
