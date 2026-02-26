#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  dag_build.sh [--from <scenario-dir>] [--out <pipeline-file>] [--dry-run]

Examples:
  SIGEE_RUNTIME_ROOT=.codex dag_build.sh --from .codex/dag/scenarios --out .codex/dag/pipelines/default.pipeline.yml
  SIGEE_RUNTIME_ROOT=.runtime dag_build.sh --from .runtime/dag/scenarios --out .runtime/dag/pipelines/default.pipeline.yml --dry-run
USAGE
}

RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.codex}"
if [[ "$RUNTIME_ROOT" == */* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a single directory name (e.g. .codex or .runtime)" >&2
  exit 1
fi

SCENARIO_DIR="${RUNTIME_ROOT}/dag/scenarios"
OUT_FILE="${RUNTIME_ROOT}/dag/pipelines/default.pipeline.yml"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      SCENARIO_DIR="${2:-}"
      shift 2
      ;;
    --out)
      OUT_FILE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

if [[ ! -d "$SCENARIO_DIR" ]]; then
  echo "ERROR: scenario directory not found: $SCENARIO_DIR" >&2
  exit 1
fi

TMP_FILE="$(mktemp)"
cleanup() {
  rm -f "$TMP_FILE"
}
trap cleanup EXIT

read_field() {
  local file="$1"
  local key="$2"
  sed -nE "s/^${key}:[[:space:]]*(.*)$/\1/p" "$file" | head -n1
}

normalize() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf "%s" "$value"
}

{
  echo "version: 1"
  echo "pipeline_id: default"
  echo "description: Generated from scenario catalog"
  echo "nodes:"
  echo "  - id: preflight"
  echo "    type: utility"
  echo "    deps: \"\""
  echo "    changed_paths: \"*\""
  echo "    run: \"bash -n skills/tech-developer/scripts/dag_build.sh skills/tech-developer/scripts/dag_run.sh skills/tech-developer/scripts/test_smoke.sh skills/tech-developer/scripts/test_e2e.sh\""
  echo "    verify: \"true\""

  GREEN_IDS=()
  SCENARIO_FILES=()
  while IFS= read -r file; do
    SCENARIO_FILES+=("$file")
  done < <(find "$SCENARIO_DIR" -maxdepth 1 -type f -name '*.scenario.yml' | sort)

  if [[ ${#SCENARIO_FILES[@]} -eq 0 ]]; then
    echo "ERROR: no scenario files found in $SCENARIO_DIR (hard TDD mode requires at least one .scenario.yml)." >&2
    exit 1
  else
    for file in "${SCENARIO_FILES[@]}"; do
      id_raw="$(read_field "$file" "id")"
      changed_raw="$(read_field "$file" "changed_paths")"
      red_raw="$(read_field "$file" "red_run")"
      impl_raw="$(read_field "$file" "impl_run")"
      green_raw="$(read_field "$file" "green_run")"
      verify_raw="$(read_field "$file" "verify")"

      SCENARIO_ID="$(normalize "${id_raw:-}")"
      CHANGED_PATHS="$(normalize "${changed_raw:-}")"
      RED_RUN="$(normalize "${red_raw:-}")"
      IMPL_RUN="$(normalize "${impl_raw:-}")"
      GREEN_RUN="$(normalize "${green_raw:-}")"
      VERIFY_CMD="$(normalize "${verify_raw:-}")"

      if [[ -z "$SCENARIO_ID" ]]; then
        echo "ERROR: missing id in scenario file: $file" >&2
        exit 1
      fi
      if [[ -z "$CHANGED_PATHS" ]]; then
        echo "ERROR: missing changed_paths in scenario file: $file" >&2
        exit 1
      fi
      if [[ -z "$RED_RUN" ]]; then
        echo "ERROR: missing red_run in scenario file: $file" >&2
        exit 1
      fi
      if [[ "$RED_RUN" == "true" || "$RED_RUN" == ":" ]]; then
        echo "ERROR: red_run must be a real command (got no-op '$RED_RUN') in scenario file: $file" >&2
        exit 1
      fi
      if [[ -z "$IMPL_RUN" ]]; then
        echo "ERROR: missing impl_run in scenario file: $file" >&2
        exit 1
      fi
      if [[ "$IMPL_RUN" == "true" || "$IMPL_RUN" == ":" ]]; then
        echo "ERROR: impl_run must be a real command (got no-op '$IMPL_RUN') in scenario file: $file" >&2
        exit 1
      fi
      if [[ -z "$GREEN_RUN" ]]; then
        echo "ERROR: missing green_run in scenario file: $file" >&2
        exit 1
      fi
      if [[ "$GREEN_RUN" == "true" || "$GREEN_RUN" == ":" ]]; then
        echo "ERROR: green_run must be a real command (got no-op '$GREEN_RUN') in scenario file: $file" >&2
        exit 1
      fi
      if [[ -z "$VERIFY_CMD" ]]; then
        echo "ERROR: missing verify in scenario file: $file" >&2
        exit 1
      fi
      if [[ "$VERIFY_CMD" == "true" || "$VERIFY_CMD" == ":" ]]; then
        echo "ERROR: verify must be a real command (got no-op '$VERIFY_CMD') in scenario file: $file" >&2
        exit 1
      fi

      RED_ID="${SCENARIO_ID}_red"
      IMPL_ID="${SCENARIO_ID}_impl"
      GREEN_ID="${SCENARIO_ID}_green"
      GREEN_IDS+=("$GREEN_ID")

      echo "  - id: $RED_ID"
      echo "    type: tdd_red"
      echo "    deps: \"preflight\""
      echo "    changed_paths: \"$CHANGED_PATHS\""
      echo "    run: \"$RED_RUN\""
      echo "    verify: \"$VERIFY_CMD\""

      echo "  - id: $IMPL_ID"
      echo "    type: impl"
      echo "    deps: \"$RED_ID\""
      echo "    changed_paths: \"$CHANGED_PATHS\""
      echo "    run: \"$IMPL_RUN\""
      echo "    verify: \"$VERIFY_CMD\""

      echo "  - id: $GREEN_ID"
      echo "    type: tdd_green"
      echo "    deps: \"$IMPL_ID\""
      echo "    changed_paths: \"$CHANGED_PATHS\""
      echo "    run: \"$GREEN_RUN\""
      echo "    verify: \"$VERIFY_CMD\""
    done

    SMOKE_DEPS=""
    for gid in "${GREEN_IDS[@]}"; do
      if [[ -z "$SMOKE_DEPS" ]]; then
        SMOKE_DEPS="$gid"
      else
        SMOKE_DEPS="$SMOKE_DEPS,$gid"
      fi
    done

    echo "  - id: smoke_gate"
    echo "    type: smoke"
    echo "    deps: \"$SMOKE_DEPS\""
    echo "    changed_paths: \"*\""
    echo "    run: \"skills/tech-developer/scripts/test_smoke.sh\""
    echo "    verify: \"true\""

    echo "  - id: e2e_gate"
    echo "    type: e2e"
    echo "    deps: \"smoke_gate\""
    echo "    changed_paths: \"*\""
    echo "    run: \"skills/tech-developer/scripts/test_e2e.sh\""
    echo "    verify: \"true\""
  fi
} > "$TMP_FILE"

if [[ "$DRY_RUN" -eq 1 ]]; then
  cat "$TMP_FILE"
  exit 0
fi

mkdir -p "$(dirname "$OUT_FILE")"
cp "$TMP_FILE" "$OUT_FILE"
echo "Pipeline generated: $OUT_FILE"
