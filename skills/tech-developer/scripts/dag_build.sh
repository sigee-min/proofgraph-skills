#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  dag_build.sh [--from <scenario-dir>] [--source <ux-scenario-dir>] [--out <pipeline-file>] [--dry-run] [--synthetic-nodes <count>] [--no-compile] [--enforce-layer-guard] [--changed-file <path>]

Examples:
  SIGEE_RUNTIME_ROOT=.sigee/.runtime dag_build.sh --out .sigee/.runtime/dag/pipelines/default.pipeline.yml
  SIGEE_RUNTIME_ROOT=.sigee/.runtime dag_build.sh --source .sigee/dag/scenarios --out .sigee/.runtime/dag/pipelines/default.pipeline.yml --dry-run
  SIGEE_RUNTIME_ROOT=.sigee/.runtime dag_build.sh --out .sigee/.runtime/dag/pipelines/synthetic-200.pipeline.yml --synthetic-nodes 200
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_DAG_BUILD_SCRIPT="${SIGEE_DAG_BUILD_NODE_SCRIPT:-$SCRIPT_DIR/../../../scripts/node/runtime/dag-build.mjs}"

if command -v node >/dev/null 2>&1 && [[ -f "$NODE_DAG_BUILD_SCRIPT" ]]; then
  exec node "$NODE_DAG_BUILD_SCRIPT" "$@"
fi

RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"
if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi
PRODUCT_TRUTH_VALIDATE_SCRIPT="$SCRIPT_DIR/../../tech-planner/scripts/product_truth_validate.sh"
GOAL_GOV_VALIDATE_SCRIPT="$SCRIPT_DIR/../../tech-planner/scripts/goal_governance_validate.sh"
DAG_COMPILE_SCRIPT="$SCRIPT_DIR/dag_compile.sh"
CHANGE_IMPACT_GATE_SCRIPT="$SCRIPT_DIR/../../tech-planner/scripts/change_impact_gate.sh"

SCENARIO_DIR="${RUNTIME_ROOT}/dag/scenarios"
SOURCE_SCENARIO_DIR=".sigee/dag/scenarios"
OUT_FILE="${RUNTIME_ROOT}/dag/pipelines/default.pipeline.yml"
DRY_RUN=0
SYNTHETIC_NODES=0
COMPILE_MODE="auto"
VALIDATION_SCENARIO_DIR=""
ENFORCE_LAYER_GUARD=0
CHANGED_FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      SCENARIO_DIR="${2:-}"
      shift 2
      ;;
    --source)
      SOURCE_SCENARIO_DIR="${2:-}"
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
    --synthetic-nodes)
      SYNTHETIC_NODES="${2:-0}"
      shift 2
      ;;
    --no-compile)
      COMPILE_MODE="off"
      shift
      ;;
    --enforce-layer-guard)
      ENFORCE_LAYER_GUARD=1
      shift
      ;;
    --changed-file)
      CHANGED_FILES+=("${2:-}")
      shift 2
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

if [[ "$SYNTHETIC_NODES" -eq 0 && ! -x "$PRODUCT_TRUTH_VALIDATE_SCRIPT" ]]; then
  echo "ERROR: product-truth validator not executable: $PRODUCT_TRUTH_VALIDATE_SCRIPT" >&2
  exit 1
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel)"
else
  PROJECT_ROOT="$(pwd)"
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

resolve_path() {
  local value="$1"
  if [[ "$value" == /* ]]; then
    printf "%s" "$value"
  else
    printf "%s/%s" "$PROJECT_ROOT" "$value"
  fi
}

SCENARIO_DIR_ABS="$(resolve_path "$SCENARIO_DIR")"
SOURCE_SCENARIO_DIR_ABS="$(resolve_path "$SOURCE_SCENARIO_DIR")"
OUT_FILE_ABS="$(resolve_path "$OUT_FILE")"
RUNTIME_SCENARIO_DEFAULT_ABS="$(resolve_path "${RUNTIME_ROOT}/dag/scenarios")"
VALIDATION_SCENARIO_DIR="$SCENARIO_DIR_ABS"

if [[ "$SYNTHETIC_NODES" -eq 0 && "$COMPILE_MODE" != "off" && "$SCENARIO_DIR_ABS" == "$RUNTIME_SCENARIO_DEFAULT_ABS" ]]; then
  if [[ ! -x "$DAG_COMPILE_SCRIPT" ]]; then
    echo "ERROR: dag compiler not executable: $DAG_COMPILE_SCRIPT" >&2
    exit 1
  fi
  if [[ ! -d "$SOURCE_SCENARIO_DIR_ABS" ]]; then
    echo "ERROR: UX scenario source directory not found: $SOURCE_SCENARIO_DIR_ABS" >&2
    exit 1
  fi
  "$DAG_COMPILE_SCRIPT" \
    --project-root "$PROJECT_ROOT" \
    --source "$SOURCE_SCENARIO_DIR_ABS" \
    --out "$RUNTIME_SCENARIO_DEFAULT_ABS" >/dev/null
  SCENARIO_DIR_ABS="$RUNTIME_SCENARIO_DEFAULT_ABS"
  VALIDATION_SCENARIO_DIR="$SOURCE_SCENARIO_DIR_ABS"
fi

SCENARIO_DIR="$SCENARIO_DIR_ABS"
OUT_FILE="$OUT_FILE_ABS"

if [[ ! -d "$SCENARIO_DIR" ]]; then
  if [[ "$SYNTHETIC_NODES" -eq 0 ]]; then
    echo "ERROR: scenario directory not found: $SCENARIO_DIR" >&2
    exit 1
  fi
fi

if [[ "$SYNTHETIC_NODES" -eq 0 ]]; then
  "$PRODUCT_TRUTH_VALIDATE_SCRIPT" \
    --project-root "$PROJECT_ROOT" \
    --scenario-dir "$VALIDATION_SCENARIO_DIR" \
    --require-scenarios >/dev/null

  if [[ ! -x "$GOAL_GOV_VALIDATE_SCRIPT" ]]; then
    echo "ERROR: goal governance validator not executable: $GOAL_GOV_VALIDATE_SCRIPT" >&2
    exit 1
  fi
  "$GOAL_GOV_VALIDATE_SCRIPT" \
    --project-root "$PROJECT_ROOT" \
    --scenario-dir "$VALIDATION_SCENARIO_DIR" \
    --require-scenarios \
    --strict >/dev/null

  if [[ "$ENFORCE_LAYER_GUARD" -eq 1 ]]; then
    if [[ ! -x "$CHANGE_IMPACT_GATE_SCRIPT" ]]; then
      echo "ERROR: change impact gate script not executable: $CHANGE_IMPACT_GATE_SCRIPT" >&2
      exit 1
    fi
    impact_cmd=(
      "$CHANGE_IMPACT_GATE_SCRIPT"
      --project-root "$PROJECT_ROOT"
      --format text
      --enforce-layer-guard
    )
    for changed in "${CHANGED_FILES[@]:-}"; do
      impact_cmd+=(--changed-file "$changed")
    done
    "${impact_cmd[@]}" >/dev/null
  fi
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

trim() {
  local value="$1"
  value="$(printf "%s" "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf "%s" "$value"
}

is_noop_command() {
  local cmd
  cmd="$(trim "$1")"
  [[ "$cmd" == "true" || "$cmd" == ":" ]]
}

split_csv_lines() {
  local raw="$1"
  local chunk
  IFS=',' read -r -a chunks <<<"$raw"
  for chunk in "${chunks[@]}"; do
    chunk="$(trim "$chunk")"
    [[ -n "$chunk" ]] && printf "%s\n" "$chunk"
  done
}

split_bundle_lines() {
  local raw="$1"
  local rest="$raw"
  local part
  while :; do
    if [[ "$rest" == *"|||"* ]]; then
      part="${rest%%|||*}"
      rest="${rest#*|||}"
    else
      part="$rest"
      rest=""
    fi
    part="$(trim "$part")"
    printf "%s\n" "$part"
    [[ -z "$rest" ]] && break
  done
}

join_csv() {
  if [[ $# -eq 0 ]]; then
    printf ""
    return 0
  fi
  local out="$1"
  shift
  local item
  for item in "$@"; do
    out="${out},${item}"
  done
  printf "%s" "$out"
}

validate_command() {
  local cmd="$1"
  local field="$2"
  local file="$3"
  if [[ -z "$cmd" ]]; then
    echo "ERROR: ${field} contains an empty command in scenario file: $file" >&2
    exit 1
  fi
  if is_noop_command "$cmd"; then
    echo "ERROR: ${field} contains no-op command '$cmd' in scenario file: $file" >&2
    exit 1
  fi
}

validate_layer() {
  local layer="$1"
  local file="$2"
  case "$layer" in
    core|system|experimental)
      return 0
      ;;
    *)
      echo "ERROR: stability_layer must be core|system|experimental in scenario file: $file" >&2
      exit 1
      ;;
  esac
}

validate_unique_commands() {
  local field="$1"
  local file="$2"
  shift 2
  local cmds=("$@")
  local i j
  for ((i=0; i<${#cmds[@]}; i++)); do
    for ((j=i+1; j<${#cmds[@]}; j++)); do
      if [[ "${cmds[$i]}" == "${cmds[$j]}" ]]; then
        echo "ERROR: ${field} must not contain duplicate commands in scenario file: $file" >&2
        exit 1
      fi
    done
  done
}

if [[ "$SYNTHETIC_NODES" -ne 0 ]]; then
  if [[ ! "$SYNTHETIC_NODES" =~ ^[0-9]+$ || "$SYNTHETIC_NODES" -lt 1 ]]; then
    echo "ERROR: --synthetic-nodes must be an integer >= 1 (got: $SYNTHETIC_NODES)" >&2
    exit 1
  fi

  {
    echo "version: 1"
    echo "pipeline_id: synthetic-${SYNTHETIC_NODES}"
    echo "description: Generated synthetic DAG pipeline for scale validation"
    echo "nodes:"
    echo "  - id: synthetic_preflight"
    echo "    type: utility"
    echo "    deps: \"\""
    echo "    changed_paths: \"synthetic/**\""
    echo "    run: \"echo synthetic-preflight\""
    echo "    verify: \"echo synthetic-preflight-verify\""

    for ((n=1; n<=SYNTHETIC_NODES; n++)); do
      node_id="synthetic_node_${n}"
      if [[ "$n" -eq 1 ]]; then
        deps="synthetic_preflight"
      else
        deps="synthetic_node_$((n - 1))"
      fi
      echo "  - id: $node_id"
      echo "    type: synthetic"
      echo "    deps: \"$deps\""
      echo "    changed_paths: \"synthetic/**\""
      echo "    run: \"echo run-$node_id\""
      echo "    verify: \"echo verify-$node_id\""
    done

    echo "  - id: synthetic_smoke_gate"
    echo "    type: smoke"
    echo "    deps: \"synthetic_node_${SYNTHETIC_NODES}\""
    echo "    changed_paths: \"synthetic/**\""
    echo "    run: \"echo synthetic-smoke\""
    echo "    verify: \"echo synthetic-smoke-verify\""

    echo "  - id: synthetic_e2e_gate"
    echo "    type: e2e"
    echo "    deps: \"synthetic_smoke_gate\""
    echo "    changed_paths: \"synthetic/**\""
    echo "    run: \"echo synthetic-e2e\""
    echo "    verify: \"echo synthetic-e2e-verify\""
  } > "$TMP_FILE"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    cat "$TMP_FILE"
    exit 0
  fi

  mkdir -p "$(dirname "$OUT_FILE")"
  cp "$TMP_FILE" "$OUT_FILE"
  echo "Synthetic pipeline generated: $OUT_FILE (nodes=$SYNTHETIC_NODES)"
  exit 0
fi

SCENARIO_FILES=()
while IFS= read -r file; do
  SCENARIO_FILES+=("$file")
done < <(find "$SCENARIO_DIR" -maxdepth 1 -type f -name '*.scenario.yml' | sort)

if [[ "$SYNTHETIC_NODES" -eq 0 && ${#SCENARIO_FILES[@]} -eq 0 ]]; then
  echo "ERROR: no scenario files found in $SCENARIO_DIR (hard TDD mode requires at least one .scenario.yml)." >&2
  exit 1
fi

SCENARIO_IDS=()
for file in "${SCENARIO_FILES[@]}"; do
  id_raw="$(read_field "$file" "id")"
  scenario_id="$(trim "$(normalize "${id_raw:-}")")"
  if [[ -z "$scenario_id" ]]; then
    echo "ERROR: missing id in scenario file: $file" >&2
    exit 1
  fi
  existing=""
  for existing in "${SCENARIO_IDS[@]:-}"; do
    [[ -z "$existing" ]] && continue
    if [[ "$existing" == "$scenario_id" ]]; then
      echo "ERROR: duplicate scenario id '$scenario_id' in scenario file: $file" >&2
      exit 1
    fi
  done
  SCENARIO_IDS+=("$scenario_id")
done

scenario_id_exists() {
  local target="$1"
  local id
  for id in "${SCENARIO_IDS[@]:-}"; do
    [[ -z "$id" ]] && continue
    if [[ "$id" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

  {
    echo "version: 1"
    echo "pipeline_id: default"
    echo "description: Generated from scenario catalog"
  echo "nodes:"
    echo "  - id: preflight"
    echo "    type: utility"
    echo "    deps: \"\""
    echo "    changed_paths: \".sigee/dag/**,.sigee/product-truth/**,skills/tech-developer/scripts/dag_build.sh,skills/tech-developer/scripts/dag_run.sh\""
    echo "    run: \"bash -n skills/tech-developer/scripts/dag_build.sh skills/tech-developer/scripts/dag_run.sh skills/tech-developer/scripts/test_smoke.sh skills/tech-developer/scripts/test_e2e.sh\""
    echo "    verify: \"true\""

  SCENARIO_SMOKE_IDS=()

  for file in "${SCENARIO_FILES[@]}"; do
    id_raw="$(read_field "$file" "id")"
    outcome_raw="$(read_field "$file" "outcome_id")"
    capability_raw="$(read_field "$file" "capability_id")"
    stability_raw="$(read_field "$file" "stability_layer")"
    depends_raw="$(read_field "$file" "depends_on")"
    linked_raw="$(read_field "$file" "linked_nodes")"
    changed_raw="$(read_field "$file" "changed_paths")"
    red_raw="$(read_field "$file" "red_run")"
    impl_raw="$(read_field "$file" "impl_run")"
    green_raw="$(read_field "$file" "green_run")"
    verify_raw="$(read_field "$file" "verify")"
    unit_normal_raw="$(read_field "$file" "unit_normal_tests")"
    unit_boundary_raw="$(read_field "$file" "unit_boundary_tests")"
    unit_failure_raw="$(read_field "$file" "unit_failure_tests")"
    boundary_smoke_raw="$(read_field "$file" "boundary_smoke_tests")"

    SCENARIO_ID="$(trim "$(normalize "${id_raw:-}")")"
    OUTCOME_ID="$(trim "$(normalize "${outcome_raw:-}")")"
    CAPABILITY_ID="$(trim "$(normalize "${capability_raw:-}")")"
    STABILITY_LAYER="$(trim "$(normalize "${stability_raw:-}")")"
    DEPENDS_ON="$(trim "$(normalize "${depends_raw:-}")")"
    LINKED_NODES="$(trim "$(normalize "${linked_raw:-}")")"
    CHANGED_PATHS="$(trim "$(normalize "${changed_raw:-}")")"
    RED_RUN="$(trim "$(normalize "${red_raw:-}")")"
    IMPL_RUN="$(trim "$(normalize "${impl_raw:-}")")"
    GREEN_RUN="$(trim "$(normalize "${green_raw:-}")")"
    VERIFY_CMD="$(trim "$(normalize "${verify_raw:-}")")"
    UNIT_NORMAL_RAW="$(trim "$(normalize "${unit_normal_raw:-}")")"
    UNIT_BOUNDARY_RAW="$(trim "$(normalize "${unit_boundary_raw:-}")")"
    UNIT_FAILURE_RAW="$(trim "$(normalize "${unit_failure_raw:-}")")"
    BOUNDARY_SMOKE_RAW="$(trim "$(normalize "${boundary_smoke_raw:-}")")"

    if [[ -z "$OUTCOME_ID" ]]; then
      echo "ERROR: missing outcome_id in scenario file: $file" >&2
      exit 1
    fi
    if [[ -z "$CAPABILITY_ID" ]]; then
      echo "ERROR: missing capability_id in scenario file: $file" >&2
      exit 1
    fi
    if [[ -z "$STABILITY_LAYER" ]]; then
      echo "ERROR: missing stability_layer in scenario file: $file" >&2
      exit 1
    fi
    validate_layer "$STABILITY_LAYER" "$file"
    if [[ -z "$LINKED_NODES" ]]; then
      echo "ERROR: missing linked_nodes in scenario file: $file (must reference at least one bug-prone linked scenario id)" >&2
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
    if [[ -z "$IMPL_RUN" ]]; then
      echo "ERROR: missing impl_run in scenario file: $file" >&2
      exit 1
    fi
    if [[ -z "$GREEN_RUN" ]]; then
      echo "ERROR: missing green_run in scenario file: $file" >&2
      exit 1
    fi
    if [[ -z "$VERIFY_CMD" ]]; then
      echo "ERROR: missing verify in scenario file: $file" >&2
      exit 1
    fi

    validate_command "$RED_RUN" "red_run" "$file"
    validate_command "$IMPL_RUN" "impl_run" "$file"
    validate_command "$GREEN_RUN" "green_run" "$file"
    validate_command "$VERIFY_CMD" "verify" "$file"

    UNIT_NORMAL_CMDS=()
    while IFS= read -r cmd; do
      cmd="$(trim "$cmd")"
      [[ -n "$cmd" ]] && UNIT_NORMAL_CMDS+=("$cmd")
    done < <(split_bundle_lines "$UNIT_NORMAL_RAW")
    if [[ ${#UNIT_NORMAL_CMDS[@]} -ne 2 ]]; then
      echo "ERROR: unit_normal_tests must contain exactly 2 commands (delimiter '|||') in scenario file: $file" >&2
      exit 1
    fi
    validate_unique_commands "unit_normal_tests" "$file" "${UNIT_NORMAL_CMDS[@]}"
    for cmd in "${UNIT_NORMAL_CMDS[@]}"; do
      validate_command "$cmd" "unit_normal_tests" "$file"
    done

    UNIT_BOUNDARY_CMDS=()
    while IFS= read -r cmd; do
      cmd="$(trim "$cmd")"
      [[ -n "$cmd" ]] && UNIT_BOUNDARY_CMDS+=("$cmd")
    done < <(split_bundle_lines "$UNIT_BOUNDARY_RAW")
    if [[ ${#UNIT_BOUNDARY_CMDS[@]} -ne 2 ]]; then
      echo "ERROR: unit_boundary_tests must contain exactly 2 commands (delimiter '|||') in scenario file: $file" >&2
      exit 1
    fi
    validate_unique_commands "unit_boundary_tests" "$file" "${UNIT_BOUNDARY_CMDS[@]}"
    for cmd in "${UNIT_BOUNDARY_CMDS[@]}"; do
      validate_command "$cmd" "unit_boundary_tests" "$file"
    done

    UNIT_FAILURE_CMDS=()
    while IFS= read -r cmd; do
      cmd="$(trim "$cmd")"
      [[ -n "$cmd" ]] && UNIT_FAILURE_CMDS+=("$cmd")
    done < <(split_bundle_lines "$UNIT_FAILURE_RAW")
    if [[ ${#UNIT_FAILURE_CMDS[@]} -ne 2 ]]; then
      echo "ERROR: unit_failure_tests must contain exactly 2 commands (delimiter '|||') in scenario file: $file" >&2
      exit 1
    fi
    validate_unique_commands "unit_failure_tests" "$file" "${UNIT_FAILURE_CMDS[@]}"
    for cmd in "${UNIT_FAILURE_CMDS[@]}"; do
      validate_command "$cmd" "unit_failure_tests" "$file"
    done

    BOUNDARY_SMOKE_CMDS=()
    while IFS= read -r cmd; do
      cmd="$(trim "$cmd")"
      [[ -n "$cmd" ]] && BOUNDARY_SMOKE_CMDS+=("$cmd")
    done < <(split_bundle_lines "$BOUNDARY_SMOKE_RAW")
    if [[ ${#BOUNDARY_SMOKE_CMDS[@]} -ne 5 ]]; then
      echo "ERROR: boundary_smoke_tests must contain exactly 5 commands (delimiter '|||') in scenario file: $file" >&2
      exit 1
    fi
    validate_unique_commands "boundary_smoke_tests" "$file" "${BOUNDARY_SMOKE_CMDS[@]}"
    for cmd in "${BOUNDARY_SMOKE_CMDS[@]}"; do
      validate_command "$cmd" "boundary_smoke_tests" "$file"
    done

    DEP_IDS=()
    if [[ -n "$DEPENDS_ON" ]]; then
      while IFS= read -r dep; do
        dep="$(trim "$dep")"
        [[ -z "$dep" ]] && continue
        if [[ "$dep" == "$SCENARIO_ID" ]]; then
          echo "ERROR: depends_on must not include self ('${SCENARIO_ID}') in scenario file: $file" >&2
          exit 1
        fi
        if ! scenario_id_exists "$dep"; then
          echo "ERROR: depends_on references unknown scenario id '$dep' in scenario file: $file" >&2
          exit 1
        fi
        DEP_IDS+=("$dep")
      done < <(split_csv_lines "$DEPENDS_ON")
    fi

    LINKED_IDS=()
    while IFS= read -r linked; do
      linked="$(trim "$linked")"
      [[ -z "$linked" ]] && continue
      if [[ "$linked" == "$SCENARIO_ID" ]]; then
        echo "ERROR: linked_nodes must not include self ('${SCENARIO_ID}') in scenario file: $file" >&2
        exit 1
      fi
      if ! scenario_id_exists "$linked"; then
        echo "ERROR: linked_nodes references unknown scenario id '$linked' in scenario file: $file" >&2
        exit 1
      fi
      LINKED_IDS+=("$linked")
    done < <(split_csv_lines "$LINKED_NODES")
    if [[ ${#LINKED_IDS[@]} -eq 0 ]]; then
      echo "ERROR: linked_nodes must contain at least one scenario id in scenario file: $file" >&2
      exit 1
    fi

    RED_ID="${SCENARIO_ID}_red"
    IMPL_ID="${SCENARIO_ID}_impl"
    GREEN_ID="${SCENARIO_ID}_green"

    RED_DEPS=("preflight")
    for dep in "${DEP_IDS[@]:-}"; do
      [[ -z "$dep" ]] && continue
      RED_DEPS+=("${dep}_green")
    done
    RED_DEPS_CSV="$(join_csv "${RED_DEPS[@]}")"

    echo "  - id: $RED_ID"
    echo "    type: tdd_red"
    echo "    deps: \"$RED_DEPS_CSV\""
    echo "    changed_paths: \"$CHANGED_PATHS\""
    echo "    run: \"$RED_RUN\""
    echo "    verify: \"$VERIFY_CMD\""

    echo "  - id: $IMPL_ID"
    echo "    type: impl"
    echo "    deps: \"$RED_ID\""
    echo "    changed_paths: \"$CHANGED_PATHS\""
    echo "    run: \"$IMPL_RUN\""
    echo "    verify: \"$VERIFY_CMD\""

    UNIT_NODE_IDS=()

    for i in "${!UNIT_NORMAL_CMDS[@]}"; do
      idx=$((i + 1))
      node_id="${SCENARIO_ID}_unit_normal_${idx}"
      UNIT_NODE_IDS+=("$node_id")
      echo "  - id: $node_id"
      echo "    type: unit_normal"
      echo "    deps: \"$IMPL_ID\""
      echo "    changed_paths: \"$CHANGED_PATHS\""
      echo "    run: \"${UNIT_NORMAL_CMDS[$i]}\""
      echo "    verify: \"true\""
    done

    for i in "${!UNIT_BOUNDARY_CMDS[@]}"; do
      idx=$((i + 1))
      node_id="${SCENARIO_ID}_unit_boundary_${idx}"
      UNIT_NODE_IDS+=("$node_id")
      echo "  - id: $node_id"
      echo "    type: unit_boundary"
      echo "    deps: \"$IMPL_ID\""
      echo "    changed_paths: \"$CHANGED_PATHS\""
      echo "    run: \"${UNIT_BOUNDARY_CMDS[$i]}\""
      echo "    verify: \"true\""
    done

    for i in "${!UNIT_FAILURE_CMDS[@]}"; do
      idx=$((i + 1))
      node_id="${SCENARIO_ID}_unit_failure_${idx}"
      UNIT_NODE_IDS+=("$node_id")
      echo "  - id: $node_id"
      echo "    type: unit_failure"
      echo "    deps: \"$IMPL_ID\""
      echo "    changed_paths: \"$CHANGED_PATHS\""
      echo "    run: \"${UNIT_FAILURE_CMDS[$i]}\""
      echo "    verify: \"true\""
    done

    GREEN_DEPS=("$IMPL_ID")
    for unit_node in "${UNIT_NODE_IDS[@]:-}"; do
      [[ -z "$unit_node" ]] && continue
      GREEN_DEPS+=("$unit_node")
    done
    GREEN_DEPS_CSV="$(join_csv "${GREEN_DEPS[@]}")"

    echo "  - id: $GREEN_ID"
    echo "    type: tdd_green"
    echo "    deps: \"$GREEN_DEPS_CSV\""
    echo "    changed_paths: \"$CHANGED_PATHS\""
    echo "    run: \"$GREEN_RUN\""
    echo "    verify: \"$VERIFY_CMD\""

    SMOKE_DEPS=("$GREEN_ID")
    for linked in "${LINKED_IDS[@]:-}"; do
      [[ -z "$linked" ]] && continue
      SMOKE_DEPS+=("${linked}_green")
    done
    SMOKE_DEPS_CSV="$(join_csv "${SMOKE_DEPS[@]}")"

    for i in "${!BOUNDARY_SMOKE_CMDS[@]}"; do
      idx=$((i + 1))
      smoke_id="${SCENARIO_ID}_smoke_boundary_${idx}"
      SCENARIO_SMOKE_IDS+=("$smoke_id")
      echo "  - id: $smoke_id"
      echo "    type: smoke_boundary"
      echo "    deps: \"$SMOKE_DEPS_CSV\""
      echo "    changed_paths: \"$CHANGED_PATHS\""
      echo "    run: \"${BOUNDARY_SMOKE_CMDS[$i]}\""
      echo "    verify: \"true\""
    done
  done

  SMOKE_GATE_DEPS="$(join_csv "${SCENARIO_SMOKE_IDS[@]}")"
  echo "  - id: smoke_gate"
  echo "    type: smoke"
  echo "    deps: \"$SMOKE_GATE_DEPS\""
  echo "    changed_paths: \".sigee/dag/pipelines/**,.sigee/dag/scenarios/**\""
  echo "    run: \"skills/tech-developer/scripts/test_smoke.sh\""
  echo "    verify: \"true\""

  echo "  - id: e2e_gate"
  echo "    type: e2e"
  echo "    deps: \"smoke_gate\""
  echo "    changed_paths: \".sigee/dag/pipelines/**,.sigee/dag/scenarios/**\""
  echo "    run: \"skills/tech-developer/scripts/test_e2e.sh\""
  echo "    verify: \"true\""
} > "$TMP_FILE"

if [[ "$DRY_RUN" -eq 1 ]]; then
  cat "$TMP_FILE"
  exit 0
fi

mkdir -p "$(dirname "$OUT_FILE")"
cp "$TMP_FILE" "$OUT_FILE"
echo "Pipeline generated: $OUT_FILE"
