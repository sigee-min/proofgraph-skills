#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAG_BUILD_SCRIPT="$SCRIPT_DIR/dag_build.sh"
DAG_RUN_SCRIPT="$SCRIPT_DIR/dag_run.sh"

if [[ ! -x "$DAG_BUILD_SCRIPT" || ! -x "$DAG_RUN_SCRIPT" ]]; then
  echo "ERROR: dag_build.sh and dag_run.sh must be executable." >&2
  exit 1
fi

if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
else
  REPO_ROOT="$(pwd)"
fi
cd "$REPO_ROOT"

fail() {
  echo "REGRESSION FAIL: $1" >&2
  exit 1
}

extract_selected_count() {
  local file="$1"
  sed -nE 's/^[[:space:]]*"selected_node_count":[[:space:]]*([0-9]+).*/\1/p' "$file" | head -n1
}

has_execution_node() {
  local file="$1"
  local node="$2"
  rg -n "\"${node}\"" "$file" >/dev/null 2>&1
}

SOURCE_DIR=".sigee/dag/scenarios"
PIPELINE_FILE=".sigee/.runtime/dag/pipelines/default.pipeline.yml"
STATE_FILE=".sigee/.runtime/dag/state/last-run.json"
TARGET_CHANGED_FILE="skills/tech-developer/scripts/dag_run.sh"
TARGET_RUNTIME_SCENARIO=".sigee/.runtime/dag/scenarios/orchestration_state_lifecycle.scenario.yml"

[[ -d "$SOURCE_DIR" ]] || fail "source scenario dir missing: $SOURCE_DIR"

TMP_DIR="$(mktemp -d)"
BACKUP_CHANGED_FILE="$TMP_DIR/dag_run.sh.bak"
BACKUP_RUNTIME_SCENARIO="$TMP_DIR/runtime_scenario.bak"

restore() {
  if [[ -f "$BACKUP_CHANGED_FILE" ]]; then
    cp "$BACKUP_CHANGED_FILE" "$TARGET_CHANGED_FILE"
  fi
  if [[ -f "$BACKUP_RUNTIME_SCENARIO" ]]; then
    cp "$BACKUP_RUNTIME_SCENARIO" "$TARGET_RUNTIME_SCENARIO"
  fi
  rm -rf "$TMP_DIR"
}
trap restore EXIT

cp "$TARGET_CHANGED_FILE" "$BACKUP_CHANGED_FILE"

SIGEE_RUNTIME_ROOT=.sigee/.runtime "$DAG_BUILD_SCRIPT" --out "$PIPELINE_FILE" >/dev/null

[[ -f .sigee/.runtime/dag/scenarios/.compiled-manifest.tsv ]] || fail "compiled manifest missing"
head -n 1 "$TARGET_RUNTIME_SCENARIO" | rg -n "^# GENERATED_FROM: .sigee/dag/scenarios/orchestration_state_lifecycle.scenario.yml$" >/dev/null || fail "generated header missing"
cp "$TARGET_RUNTIME_SCENARIO" "$BACKUP_RUNTIME_SCENARIO"

SIGEE_RUNTIME_ROOT=.sigee/.runtime "$DAG_RUN_SCRIPT" "$PIPELINE_FILE" --dry-run >/dev/null
FULL_SELECTED="$(extract_selected_count "$STATE_FILE")"
[[ "$FULL_SELECTED" =~ ^[0-9]+$ ]] || fail "invalid full selected count"

echo "# regression-changed-only-marker" >> "$TARGET_CHANGED_FILE"

SIGEE_RUNTIME_ROOT=.sigee/.runtime "$DAG_RUN_SCRIPT" "$PIPELINE_FILE" --changed-only --changed-file "$TARGET_CHANGED_FILE" >/dev/null
CHANGED_SELECTED="$(extract_selected_count "$STATE_FILE")"
[[ "$CHANGED_SELECTED" =~ ^[0-9]+$ ]] || fail "invalid changed-only selected count"
if [[ "$CHANGED_SELECTED" -ge "$FULL_SELECTED" ]]; then
  fail "changed-only did not reduce selected subgraph (changed=$CHANGED_SELECTED full=$FULL_SELECTED)"
fi

if has_execution_node "$STATE_FILE" "smoke_gate"; then
  fail "global smoke gate unexpectedly selected without --include-global-gates"
fi
if has_execution_node "$STATE_FILE" "e2e_gate"; then
  fail "global e2e gate unexpectedly selected without --include-global-gates"
fi

SIGEE_SMOKE_CMD="bash skills/tech-planner/scripts/orchestration_queue_regression.sh" \
SIGEE_E2E_CMD="bash -n skills/tech-planner/scripts/orchestration_queue.sh && bash -n skills/tech-planner/scripts/orchestration_queue_regression.sh" \
SIGEE_RUNTIME_ROOT=.sigee/.runtime \
"$DAG_RUN_SCRIPT" "$PIPELINE_FILE" --changed-only --changed-file "$TARGET_CHANGED_FILE" --include-global-gates >/dev/null
if ! has_execution_node "$STATE_FILE" "smoke_gate"; then
  fail "global smoke gate not selected when --include-global-gates is enabled"
fi

echo "# manual drift" >> "$TARGET_RUNTIME_SCENARIO"
if SIGEE_RUNTIME_ROOT=.sigee/.runtime "$DAG_RUN_SCRIPT" "$PIPELINE_FILE" --dry-run >/dev/null 2>&1; then
  fail "runtime drift was not blocked"
fi

cp "$BACKUP_RUNTIME_SCENARIO" "$TARGET_RUNTIME_SCENARIO"
SIGEE_RUNTIME_ROOT=.sigee/.runtime "$DAG_BUILD_SCRIPT" --out "$PIPELINE_FILE" >/dev/null
SIGEE_RUNTIME_ROOT=.sigee/.runtime "$DAG_RUN_SCRIPT" "$PIPELINE_FILE" --dry-run >/dev/null

echo "dag_dual_layer_regression passed: source/runtime compile + changed-only scoping + drift guard"
