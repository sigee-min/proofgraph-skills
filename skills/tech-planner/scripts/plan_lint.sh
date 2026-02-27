#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  plan_lint.sh <plan-file>

Example:
  SIGEE_RUNTIME_ROOT=.sigee/.runtime plan_lint.sh .sigee/.runtime/plans/auth-refactor.md
USAGE
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

PLAN_FILE="$1"
RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"

if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: Plan file not found: $PLAN_FILE" >&2
  exit 1
fi

ABS_PLAN="$(cd "$(dirname "$PLAN_FILE")" && pwd)/$(basename "$PLAN_FILE")"
NORM_PLAN="${ABS_PLAN//\\//}"
ERRORS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITIGNORE_GUARD_SCRIPT="$SCRIPT_DIR/sigee_gitignore_guard.sh"
PRODUCT_TRUTH_VALIDATE_SCRIPT="$SCRIPT_DIR/product_truth_validate.sh"
GOAL_GOV_VALIDATE_SCRIPT="$SCRIPT_DIR/goal_governance_validate.sh"

fail() {
  echo "LINT ERROR: $1" >&2
  ERRORS=$((ERRORS + 1))
}

check_heading() {
  local heading="$1"
  if ! grep -Eq "^${heading}\$" "$PLAN_FILE"; then
    fail "Missing heading: ${heading}"
  fi
}

check_key() {
  local key="$1"
  if ! grep -Eq "^${key}:[[:space:]]*.*$" "$PLAN_FILE"; then
    fail "Missing PlanSpec key: ${key}"
  fi
}

check_list_under_key() {
  local key="$1"
  if ! awk -v key="$key" '
    $0 ~ ("^" key ":[[:space:]]*$") {in_key=1; next}
    in_key && $0 ~ "^[[:space:]]*-[[:space:]]+.+$" {found=1; exit}
    in_key && $0 !~ "^[[:space:]]+" {in_key=0}
    END {exit found ? 0 : 1}
  ' "$PLAN_FILE"; then
    fail "Key '${key}' must include at least one list item"
  fi
}

extract_task_command() {
  local block="$1"
  local field="$2"
  local cmd
  cmd="$(printf "%s\n" "$block" | sed -nE "s/^[[:space:]]*- ${field}[[:space:]]*\`(.*)\`[[:space:]]*$/\1/p" | head -n1)"
  printf "%s" "$cmd"
}

if [[ "$NORM_PLAN" != *"/${RUNTIME_ROOT}/plans/"* ]] || [[ "$NORM_PLAN" != *.md ]]; then
  fail "Plan path must be under ${RUNTIME_ROOT}/plans and end with .md (got: $PLAN_FILE)"
fi

PROJECT_ROOT="${NORM_PLAN%%/${RUNTIME_ROOT}/plans/*}"
if [[ -z "$PROJECT_ROOT" || "$PROJECT_ROOT" == "$NORM_PLAN" ]]; then
  PROJECT_ROOT="$(cd "$(dirname "$PLAN_FILE")/../.." && pwd)"
fi
if [[ ! -x "$GITIGNORE_GUARD_SCRIPT" ]]; then
  fail "Missing executable gitignore guard: $GITIGNORE_GUARD_SCRIPT"
else
  if ! "$GITIGNORE_GUARD_SCRIPT" "$PROJECT_ROOT"; then
    fail "Failed to apply/verify .sigee gitignore policy"
  fi
fi

if [[ ! -x "$PRODUCT_TRUTH_VALIDATE_SCRIPT" ]]; then
  fail "Missing executable product-truth validator: $PRODUCT_TRUTH_VALIDATE_SCRIPT"
else
  if ! "$PRODUCT_TRUTH_VALIDATE_SCRIPT" --project-root "$PROJECT_ROOT"; then
    fail "Product-truth cross-reference validation failed"
  fi
fi

if [[ ! -x "$GOAL_GOV_VALIDATE_SCRIPT" ]]; then
  fail "Missing executable goal-governance validator: $GOAL_GOV_VALIDATE_SCRIPT"
else
  if ! "$GOAL_GOV_VALIDATE_SCRIPT" --project-root "$PROJECT_ROOT" --strict; then
    fail "Goal-governance validation failed"
  fi
fi

check_heading "## PlanSpec v2"
check_heading "## TL;DR"
check_heading "## Objective"
check_heading "## Scope"
check_heading "### In Scope"
check_heading "### Out of Scope"
check_heading "## Constraints"
check_heading "## Assumptions"
check_heading "## Delivery Waves"
check_heading "## Integration"
check_heading "## Final Verification"
check_heading "## Rollout and Rollback"

check_key "id"
check_key "owner"
if ! grep -Eq '^risk:[[:space:]]*(low|medium|high)$' "$PLAN_FILE"; then
  fail "PlanSpec key 'risk' must be one of: low, medium, high"
fi
if ! grep -Eq '^mode:[[:space:]]*strict$' "$PLAN_FILE"; then
  fail "PlanSpec key 'mode' must be 'strict' (hard TDD enforcement)"
fi
check_key "verify_commands"
check_key "done_definition"
check_list_under_key "verify_commands"
check_list_under_key "done_definition"

TASK_LINES=()
while IFS= read -r line; do
  TASK_LINES+=("$line")
done < <(grep -nE '^- \[ \]' "$PLAN_FILE" || true)

CHECKED_TASK_COUNT="$(grep -cE '^- \[x\]' "$PLAN_FILE" || true)"
if [[ ${#TASK_LINES[@]} -eq 0 && "$CHECKED_TASK_COUNT" -eq 0 ]]; then
  fail "At least one task marker is required ('- [ ]' or '- [x]')"
fi

FILE_LINES="$(wc -l < "$PLAN_FILE" | tr -d ' ')"
for i in "${!TASK_LINES[@]}"; do
  CURRENT_LINE="${TASK_LINES[$i]%%:*}"
  if [[ $i -lt $(( ${#TASK_LINES[@]} - 1 )) ]]; then
    NEXT_LINE="${TASK_LINES[$((i + 1))]%%:*}"
    END_LINE=$((NEXT_LINE - 1))
  else
    END_LINE="$FILE_LINES"
  fi

  BLOCK="$(sed -n "$((CURRENT_LINE + 1)),$END_LINE p" "$PLAN_FILE")"

  if ! grep -Eq '^[[:space:]]*- Targets:[[:space:]]*.+$' <<<"$BLOCK"; then
    fail "Task at line $CURRENT_LINE is missing '- Targets:'"
  fi
  if ! grep -Eq '^[[:space:]]*- Expected behavior:[[:space:]]*.+$' <<<"$BLOCK"; then
    fail "Task at line $CURRENT_LINE is missing '- Expected behavior:'"
  fi
  if ! grep -Eq '^[[:space:]]*- Execute:[[:space:]]*`.+`[[:space:]]*$' <<<"$BLOCK"; then
    fail "Task at line $CURRENT_LINE is missing '- Execute: `<command>`'"
  fi
  if ! grep -Eq '^[[:space:]]*- Verification:[[:space:]]*`.+`[[:space:]]*$' <<<"$BLOCK"; then
    fail "Task at line $CURRENT_LINE is missing '- Verification: `<command>`'"
  fi

  EXEC_CMD="$(extract_task_command "$BLOCK" "Execute:")"
  VERIFY_CMD="$(extract_task_command "$BLOCK" "Verification:")"
  if [[ "$EXEC_CMD" == "true" || "$EXEC_CMD" == ":" ]]; then
    fail "Task at line $CURRENT_LINE has no-op Execute command ('$EXEC_CMD')"
  fi
  if [[ "$VERIFY_CMD" == "true" || "$VERIFY_CMD" == ":" ]]; then
    fail "Task at line $CURRENT_LINE has no-op Verification command ('$VERIFY_CMD')"
  fi
done

if [[ $ERRORS -gt 0 ]]; then
  echo "Plan lint failed with $ERRORS error(s)." >&2
  exit 1
fi

echo "Plan lint passed: $PLAN_FILE"
