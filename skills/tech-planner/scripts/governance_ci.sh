#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  governance_ci.sh [--project-root <path>] [--base-ref <ref>] [--head-ref <ref>] [--changed-file <path>] [--no-layer-guard]

Runs governance + impact + DAG verification bundle suitable for CI.
USAGE
}

PROJECT_ROOT=""
BASE_REF="HEAD~1"
HEAD_REF="HEAD"
NO_LAYER_GUARD=0
CHANGED_FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --base-ref)
      BASE_REF="${2:-}"
      shift 2
      ;;
    --head-ref)
      HEAD_REF="${2:-}"
      shift 2
      ;;
    --changed-file)
      CHANGED_FILES+=("${2:-}")
      shift 2
      ;;
    --no-layer-guard)
      NO_LAYER_GUARD=1
      shift
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
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
  else
    PROJECT_ROOT="$(pwd)"
  fi
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

cd "$PROJECT_ROOT"

if [[ "${#CHANGED_FILES[@]}" -eq 0 ]] && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r changed; do
    [[ -z "$changed" ]] && continue
    CHANGED_FILES+=("$changed")
  done < <(git -C "$PROJECT_ROOT" diff --name-only "$BASE_REF" "$HEAD_REF" 2>/dev/null || true)
fi

IMPACT_CMD=(
  bash skills/tech-planner/scripts/change_impact_gate.sh
  --project-root "$PROJECT_ROOT"
  --base-ref "$BASE_REF"
  --head-ref "$HEAD_REF"
  --format markdown
  --emit-required-verification
)
if [[ "$NO_LAYER_GUARD" -ne 1 ]]; then
  IMPACT_CMD+=(--enforce-layer-guard)
fi
if [[ "${#CHANGED_FILES[@]}" -gt 0 ]]; then
  for changed in "${CHANGED_FILES[@]}"; do
    [[ -z "$changed" ]] && continue
    IMPACT_CMD+=(--changed-file "$changed")
  done
fi

bash skills/tech-planner/scripts/product_truth_validate.sh --project-root "$PROJECT_ROOT" --require-scenarios
bash skills/tech-planner/scripts/goal_governance_validate.sh --project-root "$PROJECT_ROOT" --strict --require-scenarios
bash skills/tech-planner/scripts/dag_scenario_crud.sh validate --from .sigee/dag/scenarios
"${IMPACT_CMD[@]}"
SIGEE_RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}" bash skills/tech-developer/scripts/dag_build.sh --out .sigee/.runtime/dag/pipelines/default.pipeline.yml

DAG_RUN_CMD=(
  bash
  skills/tech-developer/scripts/dag_run.sh
  .sigee/.runtime/dag/pipelines/default.pipeline.yml
  --changed-only
)
if [[ "${#CHANGED_FILES[@]}" -gt 0 ]]; then
  for changed in "${CHANGED_FILES[@]}"; do
    [[ -z "$changed" ]] && continue
    DAG_RUN_CMD+=(--changed-file "$changed")
  done
fi
SIGEE_RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}" \
SIGEE_VALIDATION_MODE="${SIGEE_VALIDATION_MODE:-framework}" \
  "${DAG_RUN_CMD[@]}"

echo "governance_ci passed"
