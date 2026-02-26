#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  dag_run.sh <pipeline-file> [--dry-run] [--changed-only] [--only <node-id>]

Examples:
  SIGEE_RUNTIME_ROOT=.codex dag_run.sh .codex/dag/pipelines/default.pipeline.yml --dry-run
  SIGEE_RUNTIME_ROOT=.runtime dag_run.sh .runtime/dag/pipelines/default.pipeline.yml --changed-only
  SIGEE_RUNTIME_ROOT=.runtime dag_run.sh .runtime/dag/pipelines/default.pipeline.yml --only smoke_gate
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

PIPELINE_FILE="$1"
shift
DRY_RUN=0
CHANGED_ONLY=0
ONLY_NODE=""
RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.codex}"

if [[ "$RUNTIME_ROOT" == */* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a single directory name (e.g. .codex or .runtime)" >&2
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --changed-only)
      CHANGED_ONLY=1
      shift
      ;;
    --only)
      ONLY_NODE="${2:-}"
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

if [[ ! -f "$PIPELINE_FILE" ]]; then
  echo "ERROR: pipeline file not found: $PIPELINE_FILE" >&2
  exit 1
fi

ABS_PIPELINE="$(cd "$(dirname "$PIPELINE_FILE")" && pwd)/$(basename "$PIPELINE_FILE")"
NORM_PIPELINE="${ABS_PIPELINE//\\//}"
if [[ "$NORM_PIPELINE" != *"/${RUNTIME_ROOT}/dag/pipelines/"* ]] || [[ "$NORM_PIPELINE" != *.yml ]]; then
  echo "ERROR: pipeline path must be under ${RUNTIME_ROOT}/dag/pipelines and end with .yml" >&2
  exit 1
fi

PROJECT_ROOT="${NORM_PIPELINE%%/${RUNTIME_ROOT}/dag/pipelines/*}"
if [[ -z "$PROJECT_ROOT" || "$PROJECT_ROOT" == "$NORM_PIPELINE" ]]; then
  PROJECT_ROOT="$(cd "$(dirname "$PIPELINE_FILE")/../../.." && pwd)"
fi
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)"
else
  REPO_ROOT="$PROJECT_ROOT"
fi

EVIDENCE_ROOT="$PROJECT_ROOT/${RUNTIME_ROOT}/evidence/dag"
STATE_FILE="$PROJECT_ROOT/${RUNTIME_ROOT}/dag/state/last-run.json"
mkdir -p "$EVIDENCE_ROOT" "$(dirname "$STATE_FILE")"

PIPELINE_ID="$(sed -nE 's/^pipeline_id:[[:space:]]*([A-Za-z0-9._-]+)[[:space:]]*$/\1/p' "$PIPELINE_FILE" | head -n1)"
if [[ -z "$PIPELINE_ID" ]]; then
  PIPELINE_ID="default"
fi

trim() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf "%s" "$s"
}

unquote() {
  local v="$1"
  if [[ "$v" == \"*\" && "$v" == *\" ]]; then
    v="${v#\"}"
    v="${v%\"}"
  fi
  if [[ "$v" == \'*\' && "$v" == *\' ]]; then
    v="${v#\'}"
    v="${v%\'}"
  fi
  printf "%s" "$v"
}

NODE_IDS=()
NODE_TYPES=()
NODE_DEPS=()
NODE_CHANGED=()
NODE_RUN=()
NODE_VERIFY=()

current_id=""
current_type=""
current_deps=""
current_changed=""
current_run=""
current_verify=""

flush_node() {
  if [[ -z "$current_id" ]]; then
    return
  fi
  if [[ -z "$current_run" || -z "$current_verify" ]]; then
    echo "ERROR: node '$current_id' missing run or verify" >&2
    exit 1
  fi
  if [[ -z "$current_changed" ]]; then
    current_changed="*"
  fi

  NODE_IDS+=("$current_id")
  NODE_TYPES+=("$current_type")
  NODE_DEPS+=("$current_deps")
  NODE_CHANGED+=("$current_changed")
  NODE_RUN+=("$current_run")
  NODE_VERIFY+=("$current_verify")

  current_id=""
  current_type=""
  current_deps=""
  current_changed=""
  current_run=""
  current_verify=""
}

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]id:[[:space:]]*(.*)$ ]]; then
    flush_node
    current_id="$(unquote "$(trim "${BASH_REMATCH[1]}")")"
    continue
  fi

  if [[ -n "$current_id" && "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="$(unquote "$(trim "${BASH_REMATCH[2]}")")"
    case "$key" in
      type) current_type="$val" ;;
      deps) current_deps="$val" ;;
      changed_paths) current_changed="$val" ;;
      run) current_run="$val" ;;
      verify) current_verify="$val" ;;
    esac
  fi
done < "$PIPELINE_FILE"
flush_node

NODE_COUNT=${#NODE_IDS[@]}
if [[ "$NODE_COUNT" -eq 0 ]]; then
  echo "ERROR: no nodes parsed from pipeline: $PIPELINE_FILE" >&2
  exit 1
fi

index_of_id() {
  local target="$1"
  local i
  for ((i=0; i<NODE_COUNT; i++)); do
    if [[ "${NODE_IDS[$i]}" == "$target" ]]; then
      printf "%s" "$i"
      return 0
    fi
  done
  printf "%s" "-1"
  return 0
}

contains_id() {
  local csv="$1"
  local target="$2"
  local item
  local -a parts=()
  IFS=',' read -r -a parts <<< "$csv" || true
  for item in "${parts[@]:-}"; do
    item="$(trim "$item")"
    [[ -z "$item" ]] && continue
    if [[ "$item" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

match_changed() {
  local pattern_csv="$1"
  local file="$2"
  local p
  local -a patterns=()
  IFS=',' read -r -a patterns <<< "$pattern_csv" || true
  for p in "${patterns[@]:-}"; do
    p="$(trim "$p")"
    [[ -z "$p" ]] && continue
    if [[ "$p" == "*" ]]; then
      return 0
    fi
    if [[ "$file" == $p ]]; then
      return 0
    fi
  done
  return 1
}

# Validate dependency references.
for ((i=0; i<NODE_COUNT; i++)); do
  dep_csv="${NODE_DEPS[$i]}"
  deps=()
  IFS=',' read -r -a deps <<< "$dep_csv" || true
  for dep in "${deps[@]:-}"; do
    dep="$(trim "$dep")"
    [[ -z "$dep" ]] && continue
    dep_idx="$(index_of_id "$dep")"
    if [[ "$dep_idx" == "-1" ]]; then
      echo "ERROR: node '${NODE_IDS[$i]}' references unknown dep '$dep'" >&2
      exit 1
    fi
  done
done

SELECTED=()
for ((i=0; i<NODE_COUNT; i++)); do
  SELECTED+=(0)
done

if [[ -n "$ONLY_NODE" ]]; then
  only_idx="$(index_of_id "$ONLY_NODE")"
  if [[ "$only_idx" == "-1" ]]; then
    echo "ERROR: --only node not found: $ONLY_NODE" >&2
    exit 1
  fi
  SELECTED[$only_idx]=1
elif [[ "$CHANGED_ONLY" -eq 1 ]]; then
  CHANGED_FILES=()
  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      CHANGED_FILES+=("$file")
    done < <(git -C "$REPO_ROOT" status --porcelain | sed -E 's/^...//' | sed '/^$/d')
  fi

  if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
    echo "No changed files detected. --changed-only exits without execution."
    exit 0
  fi

  for ((i=0; i<NODE_COUNT; i++)); do
    for file in "${CHANGED_FILES[@]}"; do
      if match_changed "${NODE_CHANGED[$i]}" "$file"; then
        SELECTED[$i]=1
        break
      fi
    done
  done
else
  for ((i=0; i<NODE_COUNT; i++)); do
    SELECTED[$i]=1
  done
fi

# Include downstream closure.
changed=1
while [[ "$changed" -eq 1 ]]; do
  changed=0
  for ((i=0; i<NODE_COUNT; i++)); do
    if [[ "${SELECTED[$i]}" -eq 1 ]]; then
      continue
    fi
    dep_csv="${NODE_DEPS[$i]}"
    deps=()
    IFS=',' read -r -a deps <<< "$dep_csv" || true
    for dep in "${deps[@]:-}"; do
      dep="$(trim "$dep")"
      [[ -z "$dep" ]] && continue
      dep_idx="$(index_of_id "$dep")"
      [[ "$dep_idx" == "-1" ]] && continue
      if [[ "${SELECTED[$dep_idx]}" -eq 1 ]]; then
        SELECTED[$i]=1
        changed=1
        break
      fi
    done
  done
done

# Include upstream closure.
changed=1
while [[ "$changed" -eq 1 ]]; do
  changed=0
  for ((i=0; i<NODE_COUNT; i++)); do
    if [[ "${SELECTED[$i]}" -eq 0 ]]; then
      continue
    fi
    dep_csv="${NODE_DEPS[$i]}"
    deps=()
    IFS=',' read -r -a deps <<< "$dep_csv" || true
    for dep in "${deps[@]:-}"; do
      dep="$(trim "$dep")"
      [[ -z "$dep" ]] && continue
      dep_idx="$(index_of_id "$dep")"
      [[ "$dep_idx" == "-1" ]] && continue
      if [[ "${SELECTED[$dep_idx]}" -eq 0 ]]; then
        SELECTED[$dep_idx]=1
        changed=1
      fi
    done
  done
done

SELECTED_COUNT=0
for ((i=0; i<NODE_COUNT; i++)); do
  if [[ "${SELECTED[$i]}" -eq 1 ]]; then
    SELECTED_COUNT=$((SELECTED_COUNT + 1))
  fi
done

if [[ "$SELECTED_COUNT" -eq 0 ]]; then
  echo "No nodes selected for execution."
  exit 0
fi

INDEGREE=()
PROCESSED=()
for ((i=0; i<NODE_COUNT; i++)); do
  INDEGREE+=(0)
  PROCESSED+=(0)
done

for ((i=0; i<NODE_COUNT; i++)); do
  if [[ "${SELECTED[$i]}" -eq 0 ]]; then
    continue
  fi
  dep_csv="${NODE_DEPS[$i]}"
  deps=()
  IFS=',' read -r -a deps <<< "$dep_csv" || true
  for dep in "${deps[@]:-}"; do
    dep="$(trim "$dep")"
    [[ -z "$dep" ]] && continue
    dep_idx="$(index_of_id "$dep")"
    [[ "$dep_idx" == "-1" ]] && continue
    if [[ "${SELECTED[$dep_idx]}" -eq 1 ]]; then
      INDEGREE[$i]=$((INDEGREE[$i] + 1))
    fi
  done
done

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$EVIDENCE_ROOT/${PIPELINE_ID}-${RUN_ID}"
mkdir -p "$RUN_DIR"

ORDER=()
STATUS="PASS"
FAILED_NODE=""
FAILED_STAGE=""
FAILED_DEPS=""

run_cmd() {
  local command="$1"
  local log_path="$2"
  local rc=0
  (
    cd "$REPO_ROOT"
    echo "+ $command"
    bash -lc "$command"
  ) >"$log_path" 2>&1 || rc=$?
  return $rc
}

processed_count=0
while [[ "$processed_count" -lt "$SELECTED_COUNT" ]]; do
  progress=0

  for ((i=0; i<NODE_COUNT; i++)); do
    if [[ "${SELECTED[$i]}" -eq 0 || "${PROCESSED[$i]}" -eq 1 ]]; then
      continue
    fi
    if [[ "${INDEGREE[$i]}" -ne 0 ]]; then
      continue
    fi

    progress=1
    PROCESSED[$i]=1
    processed_count=$((processed_count + 1))
    id="${NODE_IDS[$i]}"
    ORDER+=("$id")

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY-RUN] node=$id type=${NODE_TYPES[$i]} deps=${NODE_DEPS[$i]}"
      echo "  run: ${NODE_RUN[$i]}"
      echo "  verify: ${NODE_VERIFY[$i]}"
    else
      RUN_LOG="$RUN_DIR/${id}-run.log"
      VERIFY_LOG="$RUN_DIR/${id}-verify.log"

      echo "Running node: $id (${NODE_TYPES[$i]})"
      if ! run_cmd "${NODE_RUN[$i]}" "$RUN_LOG"; then
        STATUS="FAIL"
        FAILED_NODE="$id"
        FAILED_STAGE="run"
        FAILED_DEPS="${NODE_DEPS[$i]}"
        echo "FAILED NODE: $id"
        echo "Dependency context: deps=${NODE_DEPS[$i]}"
        echo "Rerun command: skills/tech-developer/scripts/dag_run.sh $PIPELINE_FILE --only $id"
        break 2
      fi

      if ! run_cmd "${NODE_VERIFY[$i]}" "$VERIFY_LOG"; then
        STATUS="FAIL"
        FAILED_NODE="$id"
        FAILED_STAGE="verify"
        FAILED_DEPS="${NODE_DEPS[$i]}"
        echo "FAILED NODE: $id"
        echo "Dependency context: deps=${NODE_DEPS[$i]}"
        echo "Rerun command: skills/tech-developer/scripts/dag_run.sh $PIPELINE_FILE --only $id"
        break 2
      fi
    fi

    for ((j=0; j<NODE_COUNT; j++)); do
      if [[ "${SELECTED[$j]}" -eq 0 || "${PROCESSED[$j]}" -eq 1 ]]; then
        continue
      fi
      if contains_id "${NODE_DEPS[$j]}" "$id"; then
        INDEGREE[$j]=$((INDEGREE[$j] - 1))
      fi
    done
  done

  if [[ "$STATUS" == "FAIL" ]]; then
    break
  fi

  if [[ "$progress" -eq 0 ]]; then
    STATUS="FAIL"
    FAILED_NODE="cycle_or_unresolved"
    FAILED_STAGE="topology"
    FAILED_DEPS="unresolved indegree"
    echo "ERROR: cycle or unresolved dependency in selected subgraph" >&2
    break
  fi
done

ORDER_JSON=""
for id in "${ORDER[@]}"; do
  if [[ -z "$ORDER_JSON" ]]; then
    ORDER_JSON="\"$id\""
  else
    ORDER_JSON="$ORDER_JSON,\"$id\""
  fi
done

cat > "$STATE_FILE" <<STATE_JSON
{
  "pipeline_id": "$PIPELINE_ID",
  "pipeline_file": "$PIPELINE_FILE",
  "status": "$STATUS",
  "dry_run": $DRY_RUN,
  "changed_only": $CHANGED_ONLY,
  "only_node": "${ONLY_NODE}",
  "failed_node": "$FAILED_NODE",
  "failed_stage": "$FAILED_STAGE",
  "failed_deps": "$FAILED_DEPS",
  "run_id": "$RUN_ID",
  "evidence_dir": "$RUN_DIR",
  "execution_order": [${ORDER_JSON}]
}
STATE_JSON

if [[ "$STATUS" == "FAIL" ]]; then
  exit 1
fi

echo "DAG run completed: pipeline=$PIPELINE_ID status=$STATUS"
echo "State file: $STATE_FILE"
if [[ "$DRY_RUN" -eq 0 ]]; then
  echo "Evidence dir: $RUN_DIR"
fi
