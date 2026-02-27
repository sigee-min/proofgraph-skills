#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  reports_index.sh <project-root>

Example:
  reports_index.sh /path/to/repo
USAGE
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

PROJECT_ROOT="$1"
RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"

if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "ERROR: project root not found: $PROJECT_ROOT" >&2
  exit 1
fi

REPORT_DIR="$PROJECT_ROOT/${RUNTIME_ROOT}/reports"
INDEX_FILE="$REPORT_DIR/index.md"

mkdir -p "$REPORT_DIR"

{
  echo "# Codex Reports Dashboard"
  echo
  echo "| Plan ID | Generated (UTC) | Completed | Blocked | Status | Report |"
  echo "|---|---|---:|---:|---|---|"
} > "$INDEX_FILE"

FOUND=0
while IFS= read -r report; do
  FOUND=1
  base="$(basename "$report")"
  plan_id="${base%-report.md}"
  generated="$(sed -nE 's/^- Generated at \(UTC\):[[:space:]]*(.+)$/\1/p' "$report" | head -n1)"
  completed="$(sed -nE 's/^- Completed tasks:[[:space:]]*([0-9]+\/[0-9]+)$/\1/p' "$report" | head -n1)"
  blocked="$(sed -nE 's/^- Blocked tasks:[[:space:]]*([0-9]+)$/\1/p' "$report" | head -n1)"

  if [[ -z "$generated" ]]; then generated="-"; fi
  if [[ -z "$completed" ]]; then completed="-"; fi
  if [[ -z "$blocked" ]]; then blocked="-"; fi

  status="PASS"
  if [[ "$blocked" != "-" && "$blocked" != "0" ]]; then
    status="BLOCKED"
  fi

  results_file="$PROJECT_ROOT/${RUNTIME_ROOT}/evidence/$plan_id/verification-results.tsv"
  if [[ -f "$results_file" ]] && awk -F'\t' 'NR>1 && $4=="FAIL"{found=1} END{exit found?0:1}' "$results_file"; then
    status="FAIL"
  fi

  rel_report="${RUNTIME_ROOT}/reports/$base"
  echo "| $plan_id | $generated | $completed | $blocked | $status | [$base]($rel_report) |" >> "$INDEX_FILE"
done < <(find "$REPORT_DIR" -maxdepth 1 -type f -name '*-report.md' | sort)

if [[ "$FOUND" -eq 0 ]]; then
  echo "| - | - | - | - | - | - |" >> "$INDEX_FILE"
fi

echo "Reports dashboard updated: $INDEX_FILE"
