#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  test_smoke.sh [--dry-run] [--cmd <command>]
USAGE
}

DRY_RUN=0
CMD=""

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

if [[ -z "$CMD" ]]; then
  if [[ -f package.json ]] && rg -n '"smoke"\s*:' package.json >/dev/null 2>&1; then
    CMD="npm run smoke"
  else
    echo "ERROR: no project smoke command configured. Add package.json script 'smoke' or pass --cmd." >&2
    exit 1
  fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[DRY-RUN] smoke command: $CMD"
  exit 0
fi

bash -lc "$CMD"
