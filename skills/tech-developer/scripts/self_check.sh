#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  self_check.sh [--scope smoke|e2e|all] [--dry-run]

Purpose:
  Run framework internal regression checks without mixing them into
  default product smoke/e2e gates.
USAGE
}

SCOPE="all"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

if [[ "$SCOPE" != "smoke" && "$SCOPE" != "e2e" && "$SCOPE" != "all" ]]; then
  echo "ERROR: --scope must be one of smoke|e2e|all" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_SCRIPT="$SCRIPT_DIR/test_smoke.sh"
E2E_SCRIPT="$SCRIPT_DIR/test_e2e.sh"

if [[ ! -x "$SMOKE_SCRIPT" || ! -x "$E2E_SCRIPT" ]]; then
  echo "ERROR: expected executable test gate wrappers are missing." >&2
  exit 1
fi

if [[ "$SCOPE" == "smoke" || "$SCOPE" == "all" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    bash "$SMOKE_SCRIPT" --dry-run --mode framework
  else
    bash "$SMOKE_SCRIPT" --mode framework
  fi
fi

if [[ "$SCOPE" == "e2e" || "$SCOPE" == "all" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    bash "$E2E_SCRIPT" --dry-run --mode framework
  else
    bash "$E2E_SCRIPT" --mode framework
  fi
fi
