#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  output_contract_smoke.sh <response-file> [--ai]

Examples:
  output_contract_smoke.sh response.md
  output_contract_smoke.sh response-ai.md --ai
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

TARGET_FILE="$1"
shift
EXPECT_AI=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ai)
      EXPECT_AI=1
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

if [[ ! -f "$TARGET_FILE" ]]; then
  echo "ERROR: file not found: $TARGET_FILE" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -x "$SCRIPT_DIR/citation_lint.sh" ]]; then
  echo "ERROR: missing executable citation_lint.sh in $SCRIPT_DIR" >&2
  exit 1
fi

required_patterns=(
  "Non-technical summary"
  "Problem formulation"
  "Evidence matrix"
  "Recommended approach and alternatives"
  "Project-ready pseudocode"
  "Integration plan"
  "Validation and benchmark plan"
  "Risks, unknowns, and open decisions"
  "다음 실행 프롬프트"
)

for pattern in "${required_patterns[@]}"; do
  if ! rg -n "$pattern" "$TARGET_FILE" >/dev/null 2>&1; then
    echo "ERROR: missing required section pattern: $pattern" >&2
    exit 1
  fi
done

if [[ "$EXPECT_AI" -eq 1 ]]; then
  if ! rg -n "training/inference pipeline blueprint|data.*train.*eval.*serve.*monitor" "$TARGET_FILE" >/dev/null 2>&1; then
    echo "ERROR: AI mode requires training/inference pipeline blueprint section." >&2
    exit 1
  fi
fi

if ! rg -n '^```md$|^```text$|^```$' "$TARGET_FILE" >/dev/null 2>&1; then
  echo 'ERROR: missing fenced handoff block under 다음 실행 프롬프트.' >&2
  exit 1
fi

if rg -n '^\$tech-|runtime-root|SIGEE_RUNTIME_ROOT' "$TARGET_FILE" >/dev/null 2>&1; then
  echo 'ERROR: handoff block leaks internal skill/runtime identifiers.' >&2
  exit 1
fi

"$SCRIPT_DIR/citation_lint.sh" "$TARGET_FILE" --min-urls 1
echo "output_contract_smoke passed: file=$TARGET_FILE ai=$EXPECT_AI"
