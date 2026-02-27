#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  planner_entry_guard.sh --worker <tech-developer|tech-scientist> [--plan-file <path>] [--project-root <path>]

Purpose:
  Enforce planner-first entry policy for execution skills.
  Direct execution is blocked unless planner-routed queue context exists.

Bypass:
  SIGEE_ALLOW_DIRECT_ENTRY=1  (only for controlled migration/debug)
USAGE
}

WORKER=""
PLAN_FILE=""
PROJECT_ROOT=""
RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"

if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worker)
      WORKER="${2:-}"
      shift 2
      ;;
    --plan-file)
      PLAN_FILE="${2:-}"
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

if [[ "$WORKER" != "tech-developer" && "$WORKER" != "tech-scientist" ]]; then
  echo "ERROR: --worker must be tech-developer|tech-scientist" >&2
  exit 1
fi

if [[ "${SIGEE_ALLOW_DIRECT_ENTRY:-0}" == "1" ]]; then
  echo "ENTRY_GUARD_BYPASS: SIGEE_ALLOW_DIRECT_ENTRY=1"
  exit 0
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

PROJECT_ROOT="$(resolve_project_root "$PROJECT_ROOT")"

QUEUE_NAME=""
case "$WORKER" in
  tech-developer) QUEUE_NAME="developer-todo" ;;
  tech-scientist) QUEUE_NAME="scientist-todo" ;;
esac

QUEUE_FILE="$PROJECT_ROOT/$RUNTIME_ROOT/orchestration/queues/$QUEUE_NAME.tsv"
if [[ ! -f "$QUEUE_FILE" ]]; then
  echo "ENTRY_GUARD_BLOCKED: missing planner routing context for $WORKER (queue file not found)." >&2
  echo "Run through tech-planner first so work is dispatched in the governed loop." >&2
  exit 2
fi

PLAN_ID=""
if [[ -n "$PLAN_FILE" ]]; then
  if [[ ! -f "$PLAN_FILE" ]]; then
    echo "ERROR: --plan-file not found: $PLAN_FILE" >&2
    exit 1
  fi
  PLAN_ID="$(sed -nE 's/^id:[[:space:]]*([A-Za-z0-9._-]+)[[:space:]]*$/\1/p' "$PLAN_FILE" | head -n1)"
  if [[ -z "$PLAN_ID" ]]; then
    PLAN_ID="$(basename "$PLAN_FILE" .md)"
  fi
fi

if [[ -n "$PLAN_ID" ]]; then
  if awk -F'\t' -v source="plan:${PLAN_ID}" '
    NR==1 { next }
    $5==source && ($2=="pending" || $2=="in_progress" || $2=="review") { found=1; exit 0 }
    END { exit(found?0:1) }
  ' "$QUEUE_FILE"; then
    echo "ENTRY_GUARD_PASS: planner-routed context found for plan:$PLAN_ID"
    exit 0
  fi
else
  if awk -F'\t' '
    NR==1 { next }
    ($2=="pending" || $2=="in_progress" || $2=="review") { found=1; exit 0 }
    END { exit(found?0:1) }
  ' "$QUEUE_FILE"; then
    echo "ENTRY_GUARD_PASS: planner-routed actionable context found"
    exit 0
  fi
fi

if [[ -n "$PLAN_ID" ]]; then
  echo "ENTRY_GUARD_BLOCKED: plan:$PLAN_ID is not currently planner-routed for $WORKER." >&2
else
  echo "ENTRY_GUARD_BLOCKED: no planner-routed actionable work for $WORKER." >&2
fi
echo "Run through tech-planner first so execution follows the governed loop." >&2
exit 2
