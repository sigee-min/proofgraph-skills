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
  "Verification confidence"
  "Remaining risks, unknowns, and open decisions"
  "Problem formulation"
  "Evidence matrix"
  "Recommended approach and alternatives"
  "Project-ready pseudocode"
  "Integration plan"
  "Validation and benchmark plan"
  "다음 실행 프롬프트"
)

for pattern in "${required_patterns[@]}"; do
  if ! rg -n "$pattern" "$TARGET_FILE" >/dev/null 2>&1; then
    echo "ERROR: missing required section pattern: $pattern" >&2
    exit 1
  fi
done

line_of_heading() {
  local heading="$1"
  rg -n "^## ${heading}$" "$TARGET_FILE" | head -n1 | cut -d: -f1
}

LINE_NONTECH="$(line_of_heading "Non-technical summary")"
LINE_VERIFY="$(line_of_heading "Verification confidence")"
LINE_RISK="$(line_of_heading "Remaining risks, unknowns, and open decisions")"

if [[ -z "$LINE_NONTECH" || -z "$LINE_VERIFY" || -z "$LINE_RISK" ]]; then
  echo "ERROR: missing mandatory top-level headings for rendering order." >&2
  exit 1
fi
if [[ "$LINE_NONTECH" -ge "$LINE_VERIFY" || "$LINE_VERIFY" -ge "$LINE_RISK" ]]; then
  echo "ERROR: rendering order must start with Non-technical summary -> Verification confidence -> Remaining risks." >&2
  exit 1
fi

if [[ "$EXPECT_AI" -eq 1 ]]; then
  if ! rg -n "training/inference pipeline blueprint|data.*train.*eval.*serve.*monitor" "$TARGET_FILE" >/dev/null 2>&1; then
    echo "ERROR: AI mode requires training/inference pipeline blueprint section." >&2
    exit 1
  fi
fi

NEXT_PROMPT_SECTION_COUNT="$(rg -n '^## 다음 실행 프롬프트$' "$TARGET_FILE" | wc -l | tr -d ' ')"
if [[ "$NEXT_PROMPT_SECTION_COUNT" -ne 1 ]]; then
  echo "ERROR: response must include exactly one '다음 실행 프롬프트' section (got $NEXT_PROMPT_SECTION_COUNT)." >&2
  exit 1
fi

NEXT_PROMPT_OPEN_COUNT="$(
  awk '
    BEGIN { in_section=0; count=0 }
    /^## 다음 실행 프롬프트$/ { in_section=1; next }
    /^## / && in_section { in_section=0 }
    in_section && /^```md$/ { count++ }
    END { print count }
  ' "$TARGET_FILE"
)"
if [[ "$NEXT_PROMPT_OPEN_COUNT" -ne 1 ]]; then
  echo 'ERROR: next prompt section must include exactly one opening markdown fence (```md).' >&2
  exit 1
fi

NEXT_PROMPT_CLOSE_COUNT="$(
  awk '
    BEGIN { in_section=0; count=0 }
    /^## 다음 실행 프롬프트$/ { in_section=1; next }
    /^## / && in_section { in_section=0 }
    in_section && /^```$/ { count++ }
    END { print count }
  ' "$TARGET_FILE"
)"
if [[ "$NEXT_PROMPT_CLOSE_COUNT" -ne 1 ]]; then
  echo "ERROR: next prompt section must include exactly one closing markdown fence." >&2
  exit 1
fi

if rg -n '^\$tech-|runtime-root|SIGEE_RUNTIME_ROOT' "$TARGET_FILE" >/dev/null 2>&1; then
  echo 'ERROR: handoff block leaks internal skill/runtime identifiers.' >&2
  exit 1
fi

"$SCRIPT_DIR/citation_lint.sh" "$TARGET_FILE" --min-urls 1
echo "output_contract_smoke passed: file=$TARGET_FILE ai=$EXPECT_AI"
