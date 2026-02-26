#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  report_generate.sh <plan-file>

Example:
  SIGEE_RUNTIME_ROOT=.codex report_generate.sh .codex/plans/auth-refactor.md
  SIGEE_RUNTIME_ROOT=.runtime report_generate.sh .runtime/plans/auth-refactor.md
USAGE
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

PLAN_FILE="$1"
RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.codex}"

if [[ "$RUNTIME_ROOT" == */* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a single directory name (e.g. .codex or .runtime)" >&2
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

REPORT_DIR="$PROJECT_ROOT/${RUNTIME_ROOT}/reports"
EVIDENCE_DIR="$PROJECT_ROOT/${RUNTIME_ROOT}/evidence/$PLAN_ID"
RESULTS_FILE="$EVIDENCE_DIR/verification-results.tsv"
REPORT_FILE="$REPORT_DIR/${PLAN_ID}-report.md"
INDEX_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/reports_index.sh"

mkdir -p "$REPORT_DIR"

TOTAL_TASKS="$(grep -Ec '^- \[[ xX]\]' "$PLAN_FILE" || true)"
COMPLETED_TASKS="$(grep -Ec '^- \[[xX]\]' "$PLAN_FILE" || true)"
BLOCKED_TASKS=$((TOTAL_TASKS - COMPLETED_TASKS))
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

{
  echo "## Execution Summary"
  echo "- Plan: $PLAN_FILE"
  echo "- Completed tasks: ${COMPLETED_TASKS}/${TOTAL_TASKS}"
  echo "- Blocked tasks: ${BLOCKED_TASKS}"
  echo "- Generated at (UTC): ${TIMESTAMP}"
  echo
  echo "## Files Changed"
  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    CHANGED="$(git -C "$REPO_ROOT" status --porcelain | sed -E 's/^...//' | sed '/^$/d' || true)"
    if [[ -n "$CHANGED" ]]; then
      while IFS= read -r file; do
        echo "- $file"
      done <<< "$CHANGED"
    else
      echo "- (no uncommitted file changes detected)"
    fi
  else
    echo "- (not a git repository)"
  fi
  echo
  echo "## Verification Evidence"
  if [[ -f "$RESULTS_FILE" ]]; then
    tail -n +2 "$RESULTS_FILE" | while IFS=$'\t' read -r task_no title kind status log_path command; do
      echo "- [task ${task_no}] ${kind}: ${status} | ${command}"
      if [[ "$log_path" != "-" ]]; then
        echo "  - log: ${log_path}"
      fi
    done
  else
    echo "- (no verification-results.tsv found at ${RESULTS_FILE})"
  fi
  echo
  echo "## Evidence Paths"
  echo "- ${EVIDENCE_DIR}"
  echo "- ${RESULTS_FILE}"
  echo
  echo "## Notes"
  echo "- Key implementation decisions:"
  echo "- Trade-offs accepted:"
  echo
  echo "## Remaining Risks / Follow-ups"
  echo "- (fill as needed)"
} > "$REPORT_FILE"

echo "Report generated: $REPORT_FILE"

if [[ -x "$INDEX_SCRIPT" ]]; then
  "$INDEX_SCRIPT" "$PROJECT_ROOT"
else
  echo "WARN: reports_index.sh is not executable. Skipping dashboard update." >&2
fi
