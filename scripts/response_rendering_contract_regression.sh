#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  response_rendering_contract_regression.sh [--project-root <path>]

What it validates:
  1) planner/developer/scientist skills reference shared response contract
  2) all three skills require common response order (impact -> confidence -> risk)
  3) all three skills require exactly one `다음 실행 프롬프트` block
  4) user-facing queue helper outputs remain black-box and single-block
USAGE
}

PROJECT_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
USER_FACING_GUARD_SCRIPT="$PROJECT_ROOT/skills/tech-planner/scripts/user_facing_guard.sh"
if [[ ! -f "$USER_FACING_GUARD_SCRIPT" ]]; then
  echo "ERROR: missing shared user-facing guard: $USER_FACING_GUARD_SCRIPT" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$USER_FACING_GUARD_SCRIPT"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! rg -n "$pattern" "$file" >/dev/null 2>&1; then
    echo "ERROR: missing contract pattern ($label) in $file" >&2
    exit 1
  fi
}

assert_match_count() {
  local haystack="$1"
  local pattern="$2"
  local expected="$3"
  local label="$4"
  local count
  count="$(printf "%s\n" "$haystack" | grep -Ec "$pattern" || true)"
  if [[ "$count" -ne "$expected" ]]; then
    echo "ERROR: assertion failed ($label): expected $expected matches for /$pattern/, got $count" >&2
    exit 1
  fi
}

assert_no_internal_leak() {
  local haystack="$1"
  local label="$2"
  if ! sigee_assert_no_internal_leak "$haystack" "$label"; then
    exit 1
  fi
}

SKILL_FILES=(
  "$PROJECT_ROOT/skills/tech-planner/SKILL.md"
  "$PROJECT_ROOT/skills/tech-developer/SKILL.md"
  "$PROJECT_ROOT/skills/tech-scientist/SKILL.md"
)

for file in "${SKILL_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: missing skill file: $file" >&2
    exit 1
  fi
  require_pattern "$file" "response-rendering-contract\\.md" "shared contract reference"
  require_pattern "$file" "Behavior and user impact|behavior and user impact" "impact-first order"
  require_pattern "$file" "Verification confidence|verification confidence|Verification narrative|verification narrative" "verification confidence order"
  require_pattern "$file" "Remaining risks|remaining risks" "risk order"
  require_pattern "$file" "정확히 1개|exactly one" "single next prompt block rule"
done

QUEUE_SCRIPT="$PROJECT_ROOT/skills/tech-planner/scripts/orchestration_queue.sh"
if [[ ! -x "$QUEUE_SCRIPT" ]]; then
  echo "ERROR: missing executable queue helper: $QUEUE_SCRIPT" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"
TEST_PROJECT="$TMP_ROOT/project"
mkdir -p "$TEST_PROJECT"

SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$QUEUE_SCRIPT" init --project-root "$TEST_PROJECT" >/dev/null
USER_OUT="$(SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$QUEUE_SCRIPT" next-prompt --user-facing --project-root "$TEST_PROJECT" 2>&1)"

assert_match_count "$USER_OUT" '^다음 실행 프롬프트$' 1 "user-facing next prompt title count"
assert_match_count "$USER_OUT" '^```md$' 1 "user-facing next prompt fence open count"
assert_match_count "$USER_OUT" '^```$' 1 "user-facing next prompt fence close count"
assert_match_count "$USER_OUT" '^왜 지금 이 작업인가:' 1 "user-facing next prompt rationale line count"
assert_no_internal_leak "$USER_OUT" "user-facing next prompt leak check"

LOOP_USER_OUT="$(SIGEE_RUNTIME_ROOT="$RUNTIME_ROOT" bash "$QUEUE_SCRIPT" loop-status --user-facing --project-root "$TEST_PROJECT" 2>&1)"
assert_match_count "$LOOP_USER_OUT" '^요약:' 1 "user-facing loop-status summary line count"
assert_no_internal_leak "$LOOP_USER_OUT" "user-facing loop-status leak check"

echo "response_rendering_contract_regression passed: shared order + black-box masking + next-prompt/loop-status leak checks"
