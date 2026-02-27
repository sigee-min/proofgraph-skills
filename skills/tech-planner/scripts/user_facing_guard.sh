#!/usr/bin/env bash

# Shared single-source rule for blocking internal orchestration terms
# from default user-facing output across planner/developer/scientist flows.
SIGEE_USER_FACING_INTERNAL_LEAK_PATTERN='(\$tech-|runtime-root|SIGEE_RUNTIME_ROOT|<runtime-root>|\.sigee(/|\.runtime)|/orchestration/|planner-inbox|scientist-todo|developer-todo|planner-review|blocked-user-confirmation|LOOP_STATUS|NEXT_PROMPT_|CLAIM_|done-gate|lease|phase|error_class|attempt_count|retry_budget|evidence_links|source=plan:|plan:[A-Za-z0-9._-]+|[A-Z]{2,}-[0-9]{2,})'

sigee_user_facing_internal_leak_detected() {
  local text="${1:-}"
  if printf "%s" "$text" | grep -Eiq "$SIGEE_USER_FACING_INTERNAL_LEAK_PATTERN"; then
    return 0
  fi
  return 1
}

sigee_assert_no_internal_leak() {
  local haystack="${1:-}"
  local label="${2:-internal leak check}"
  if sigee_user_facing_internal_leak_detected "$haystack"; then
    echo "ERROR: assertion failed ($label): leaked internal terms in user-facing output" >&2
    return 1
  fi
  return 0
}
