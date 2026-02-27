#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  test_smoke.sh [--dry-run] [--cmd <command>] [--mode product|framework] [--self-check]

Modes:
  - product (default): run product smoke command
  - framework: run framework internal regression checks
  - --self-check is a backward-compatible alias for --mode framework
USAGE
}

DRY_RUN=0
CMD=""
MODE="${SIGEE_VALIDATION_MODE:-product}"

resolve_self_check_cmd() {
  local cmd=""
  if [[ -x skills/tech-planner/scripts/orchestration_queue_regression.sh ]]; then
    cmd="bash skills/tech-planner/scripts/orchestration_queue_regression.sh"
  fi
  if [[ -x scripts/response_rendering_contract_regression.sh ]]; then
    if [[ -n "$cmd" ]]; then
      cmd="$cmd && bash scripts/response_rendering_contract_regression.sh"
    else
      cmd="bash scripts/response_rendering_contract_regression.sh"
    fi
  fi
  printf "%s" "$cmd"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --cmd)
      CMD="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --self-check)
      MODE="framework"
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

case "$MODE" in
  product|framework)
    ;;
  *)
    echo "ERROR: --mode must be one of product|framework (got: $MODE)" >&2
    exit 1
    ;;
esac

if [[ -z "$CMD" ]]; then
  if [[ "$MODE" == "framework" ]]; then
    CMD="$(resolve_self_check_cmd)"
    if [[ -z "$CMD" ]]; then
      echo "ERROR: no framework smoke command available." >&2
      exit 1
    fi
  elif [[ -n "${SIGEE_SMOKE_CMD:-}" ]]; then
    CMD="${SIGEE_SMOKE_CMD}"
  elif [[ -f package.json ]] && rg -n '"smoke"\s*:' package.json >/dev/null 2>&1; then
    CMD="npm run smoke"
  elif [[ -f Makefile ]] && rg -n '^smoke:' Makefile >/dev/null 2>&1; then
    CMD="make smoke"
  else
    echo "ERROR: no product smoke command configured. Set SIGEE_SMOKE_CMD, add package.json script 'smoke' (or Makefile target 'smoke'), or pass --cmd. For framework checks use --mode framework." >&2
    exit 1
  fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[DRY-RUN][$MODE] smoke command: $CMD"
  exit 0
fi

bash -lc "$CMD"
