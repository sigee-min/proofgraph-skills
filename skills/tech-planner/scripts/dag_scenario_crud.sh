#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  dag_scenario_crud.sh <command> [options]

Commands:
  list [--from <scenario-dir>]
  show --id <scenario-id> [--field <key>] [--from <scenario-dir>]
  summary --id <scenario-id> [--from <scenario-dir>]
  create --id <scenario-id> --title <text> --owner <text> --outcome <id> --capability <id> --layer <core|system|experimental> \
         --linked <csv> --changed <csv> --red <cmd> --impl <cmd> --green <cmd> --verify <cmd> \
         --unit-normal <cmd1|||cmd2> --unit-boundary <cmd1|||cmd2> \
         --unit-failure <cmd1|||cmd2> --boundary-smoke <cmd1|||cmd2|||cmd3|||cmd4|||cmd5> \
         [--depends-on <csv>] [--from <scenario-dir>]
  set --id <scenario-id> --field <key> --value <text> [--from <scenario-dir>]
  delete --id <scenario-id> [--yes] [--from <scenario-dir>]
  validate [--id <scenario-id>] [--from <scenario-dir>]
  scaffold --id <scenario-id> [--from <scenario-dir>]

Notes:
  - Intended for internal skill automation (planner/developer).
  - Default scenario dir (UX DAG SSoT): .sigee/dag/scenarios
  - Test contract is mandatory per scenario:
      unit_normal_tests=2, unit_boundary_tests=2, unit_failure_tests=2, boundary_smoke_tests=5
  - Scenario stability layer is mandatory: core|system|experimental
USAGE
}

RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"
if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

DEFAULT_SCENARIO_DIR=".sigee/dag/scenarios"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAG_BUILD_SCRIPT="$SCRIPT_DIR/../../tech-developer/scripts/dag_build.sh"
PRODUCT_TRUTH_VALIDATE_SCRIPT="$SCRIPT_DIR/product_truth_validate.sh"
GOAL_GOV_VALIDATE_SCRIPT="$SCRIPT_DIR/goal_governance_validate.sh"

trim() {
  local value="$1"
  value="$(printf "%s" "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf "%s" "$value"
}

normalize() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf "%s" "$value"
}

read_field() {
  local file="$1"
  local key="$2"
  sed -nE "s/^${key}:[[:space:]]*(.*)$/\1/p" "$file" | head -n1
}

ensure_dir() {
  local dir="$1"
  mkdir -p "$dir"
}

resolve_project_root_for_dir() {
  local dir="$1"
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$dir" rev-parse --show-toplevel
  else
    pwd
  fi
}

is_noop_command() {
  local cmd
  cmd="$(trim "$1")"
  [[ "$cmd" == "true" || "$cmd" == ":" ]]
}

split_csv_lines() {
  local raw="$1"
  raw="$(trim "$raw")"
  if [[ -z "$raw" ]]; then
    return 0
  fi
  local chunk
  IFS=',' read -r -a chunks <<<"$raw"
  for chunk in "${chunks[@]-}"; do
    chunk="$(trim "$chunk")"
    [[ -n "$chunk" ]] && printf "%s\n" "$chunk"
  done
}

split_bundle_lines() {
  local raw="$1"
  raw="$(trim "$raw")"
  if [[ -z "$raw" ]]; then
    return 0
  fi
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
    [[ -n "$part" ]] && printf "%s\n" "$part"
    [[ -z "$rest" ]] && break
  done
}

bundle_count() {
  local raw="$1"
  local count=0
  while IFS= read -r _line; do
    count=$((count + 1))
  done < <(split_bundle_lines "$raw")
  printf "%s" "$count"
}

validate_required_cmd() {
  local cmd="$1"
  local field="$2"
  local file="$3"
  if [[ -z "$cmd" ]]; then
    echo "ERROR: missing ${field} in scenario file: $file" >&2
    exit 1
  fi
  if is_noop_command "$cmd"; then
    echo "ERROR: ${field} must be an executable command (got no-op '$cmd') in scenario file: $file" >&2
    exit 1
  fi
}

validate_layer_value() {
  local layer="$1"
  local field="$2"
  local file="$3"
  case "$layer" in
    core|system|experimental)
      return 0
      ;;
    *)
      echo "ERROR: ${field} must be one of core|system|experimental (got '$layer') in scenario file: $file" >&2
      exit 1
      ;;
  esac
}

find_scenario_file_by_id() {
  local dir="$1"
  local id="$2"
  local file rid
  while IFS= read -r file; do
    rid="$(trim "$(normalize "$(read_field "$file" "id")")")"
    if [[ "$rid" == "$id" ]]; then
      printf "%s" "$file"
      return 0
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.scenario.yml' | sort)
  return 1
}

collect_all_ids() {
  local dir="$1"
  local file rid
  while IFS= read -r file; do
    rid="$(trim "$(normalize "$(read_field "$file" "id")")")"
    [[ -n "$rid" ]] && printf "%s\n" "$rid"
  done < <(find "$dir" -maxdepth 1 -type f -name '*.scenario.yml' | sort)
}

id_exists_in_set() {
  local target="$1"
  shift
  local id
  for id in "$@"; do
    if [[ "$id" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

validate_contract_file() {
  local file="$1"
  local check_links="${2:-0}"
  local all_ids_csv="${3:-}"

  local id outcome capability layer linked depends changed red impl green verify
  local unit_normal unit_boundary unit_failure boundary_smoke
  local linked_id dep_id

  id="$(trim "$(normalize "$(read_field "$file" "id")")")"
  outcome="$(trim "$(normalize "$(read_field "$file" "outcome_id")")")"
  capability="$(trim "$(normalize "$(read_field "$file" "capability_id")")")"
  layer="$(trim "$(normalize "$(read_field "$file" "stability_layer")")")"
  linked="$(trim "$(normalize "$(read_field "$file" "linked_nodes")")")"
  depends="$(trim "$(normalize "$(read_field "$file" "depends_on")")")"
  changed="$(trim "$(normalize "$(read_field "$file" "changed_paths")")")"
  red="$(trim "$(normalize "$(read_field "$file" "red_run")")")"
  impl="$(trim "$(normalize "$(read_field "$file" "impl_run")")")"
  green="$(trim "$(normalize "$(read_field "$file" "green_run")")")"
  verify="$(trim "$(normalize "$(read_field "$file" "verify")")")"
  unit_normal="$(trim "$(normalize "$(read_field "$file" "unit_normal_tests")")")"
  unit_boundary="$(trim "$(normalize "$(read_field "$file" "unit_boundary_tests")")")"
  unit_failure="$(trim "$(normalize "$(read_field "$file" "unit_failure_tests")")")"
  boundary_smoke="$(trim "$(normalize "$(read_field "$file" "boundary_smoke_tests")")")"

  if [[ -z "$id" ]]; then
    echo "ERROR: missing id in scenario file: $file" >&2
    exit 1
  fi
  if [[ -z "$outcome" ]]; then
    echo "ERROR: missing outcome_id in scenario file: $file" >&2
    exit 1
  fi
  if [[ -z "$capability" ]]; then
    echo "ERROR: missing capability_id in scenario file: $file" >&2
    exit 1
  fi
  if [[ -z "$layer" ]]; then
    echo "ERROR: missing stability_layer in scenario file: $file" >&2
    exit 1
  fi
  validate_layer_value "$layer" "stability_layer" "$file"
  if [[ -z "$linked" ]]; then
    echo "ERROR: missing linked_nodes in scenario file: $file" >&2
    exit 1
  fi
  if [[ -z "$changed" ]]; then
    echo "ERROR: missing changed_paths in scenario file: $file" >&2
    exit 1
  fi

  validate_required_cmd "$red" "red_run" "$file"
  validate_required_cmd "$impl" "impl_run" "$file"
  validate_required_cmd "$green" "green_run" "$file"
  validate_required_cmd "$verify" "verify" "$file"

  if [[ "$(bundle_count "$unit_normal")" -ne 2 ]]; then
    echo "ERROR: unit_normal_tests must contain exactly 2 commands in scenario file: $file" >&2
    exit 1
  fi
  if [[ "$(bundle_count "$unit_boundary")" -ne 2 ]]; then
    echo "ERROR: unit_boundary_tests must contain exactly 2 commands in scenario file: $file" >&2
    exit 1
  fi
  if [[ "$(bundle_count "$unit_failure")" -ne 2 ]]; then
    echo "ERROR: unit_failure_tests must contain exactly 2 commands in scenario file: $file" >&2
    exit 1
  fi
  if [[ "$(bundle_count "$boundary_smoke")" -ne 5 ]]; then
    echo "ERROR: boundary_smoke_tests must contain exactly 5 commands in scenario file: $file" >&2
    exit 1
  fi

  if [[ "$check_links" -eq 1 ]]; then
    IFS=',' read -r -a all_ids <<<"$all_ids_csv"

    while IFS= read -r linked_id; do
      if [[ "$linked_id" == "$id" ]]; then
        echo "ERROR: linked_nodes must not include self '$id' in scenario file: $file" >&2
        exit 1
      fi
      if ! id_exists_in_set "$linked_id" "${all_ids[@]}"; then
        echo "ERROR: linked_nodes references unknown scenario id '$linked_id' in scenario file: $file" >&2
        exit 1
      fi
    done < <(split_csv_lines "$linked")

    while IFS= read -r dep_id; do
      [[ -z "$dep_id" ]] && continue
      if [[ "$dep_id" == "$id" ]]; then
        echo "ERROR: depends_on must not include self '$id' in scenario file: $file" >&2
        exit 1
      fi
      if ! id_exists_in_set "$dep_id" "${all_ids[@]}"; then
        echo "ERROR: depends_on references unknown scenario id '$dep_id' in scenario file: $file" >&2
        exit 1
      fi
    done < <(split_csv_lines "$depends")
  fi
}

escape_yaml_double_quoted() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf "%s" "$value"
}

write_field() {
  local file="$1"
  local key="$2"
  local value="$3"
  local escaped tmp
  escaped="$(escape_yaml_double_quoted "$value")"
  tmp="$(mktemp)"
  awk -v key="$key" -v val="$escaped" '
    BEGIN {done=0}
    $0 ~ ("^" key ":[[:space:]]*") && done==0 {
      print key ": \"" val "\""
      done=1
      next
    }
    { print }
    END {
      if (done==0) {
        print key ": \"" val "\""
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

cmd_list() {
  local scenario_dir="$DEFAULT_SCENARIO_DIR"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) scenario_dir="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for list: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  ensure_dir "$scenario_dir"
  echo "id|outcome_id|capability_id|stability_layer|depends_on|linked_nodes|changed_paths"
  local file id outcome capability layer depends linked changed
  while IFS= read -r file; do
    id="$(trim "$(normalize "$(read_field "$file" "id")")")"
    outcome="$(trim "$(normalize "$(read_field "$file" "outcome_id")")")"
    capability="$(trim "$(normalize "$(read_field "$file" "capability_id")")")"
    layer="$(trim "$(normalize "$(read_field "$file" "stability_layer")")")"
    depends="$(trim "$(normalize "$(read_field "$file" "depends_on")")")"
    linked="$(trim "$(normalize "$(read_field "$file" "linked_nodes")")")"
    changed="$(trim "$(normalize "$(read_field "$file" "changed_paths")")")"
    echo "${id}|${outcome}|${capability}|${layer}|${depends}|${linked}|${changed}"
  done < <(find "$scenario_dir" -maxdepth 1 -type f -name '*.scenario.yml' | sort)
}

cmd_show() {
  local scenario_dir="$DEFAULT_SCENARIO_DIR"
  local id=""
  local field=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="${2:-}"; shift 2 ;;
      --field) field="${2:-}"; shift 2 ;;
      --from) scenario_dir="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for show: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
  if [[ -z "$id" ]]; then
    echo "ERROR: show requires --id" >&2
    exit 1
  fi
  ensure_dir "$scenario_dir"
  local file
  file="$(find_scenario_file_by_id "$scenario_dir" "$id" || true)"
  if [[ -z "$file" ]]; then
    echo "ERROR: scenario id not found: $id" >&2
    exit 1
  fi
  if [[ -n "$field" ]]; then
    normalize "$(read_field "$file" "$field")"
    echo
    return 0
  fi
  cat "$file"
}

cmd_summary() {
  local scenario_dir="$DEFAULT_SCENARIO_DIR"
  local id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="${2:-}"; shift 2 ;;
      --from) scenario_dir="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for summary: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
  if [[ -z "$id" ]]; then
    echo "ERROR: summary requires --id" >&2
    exit 1
  fi

  local file
  file="$(find_scenario_file_by_id "$scenario_dir" "$id" || true)"
  if [[ -z "$file" ]]; then
    echo "ERROR: scenario id not found: $id" >&2
    exit 1
  fi

  local outcome capability layer depends linked changed
  local u_normal u_boundary u_failure b_smoke
  outcome="$(trim "$(normalize "$(read_field "$file" "outcome_id")")")"
  capability="$(trim "$(normalize "$(read_field "$file" "capability_id")")")"
  layer="$(trim "$(normalize "$(read_field "$file" "stability_layer")")")"
  depends="$(trim "$(normalize "$(read_field "$file" "depends_on")")")"
  linked="$(trim "$(normalize "$(read_field "$file" "linked_nodes")")")"
  changed="$(trim "$(normalize "$(read_field "$file" "changed_paths")")")"
  u_normal="$(bundle_count "$(normalize "$(read_field "$file" "unit_normal_tests")")")"
  u_boundary="$(bundle_count "$(normalize "$(read_field "$file" "unit_boundary_tests")")")"
  u_failure="$(bundle_count "$(normalize "$(read_field "$file" "unit_failure_tests")")")"
  b_smoke="$(bundle_count "$(normalize "$(read_field "$file" "boundary_smoke_tests")")")"

  cat <<EOF
id: $id
outcome_id: $outcome
capability_id: $capability
stability_layer: $layer
depends_on: $depends
linked_nodes: $linked
changed_paths: $changed
test_contract:
  unit_normal_tests: $u_normal
  unit_boundary_tests: $u_boundary
  unit_failure_tests: $u_failure
  boundary_smoke_tests: $b_smoke
EOF
}

cmd_create() {
  local scenario_dir="$DEFAULT_SCENARIO_DIR"
  local id="" title="" owner="" outcome="" capability="" layer="" depends="" linked="" changed=""
  local red="" impl="" green="" verify=""
  local unit_normal="" unit_boundary="" unit_failure="" boundary_smoke=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="${2:-}"; shift 2 ;;
      --title) title="${2:-}"; shift 2 ;;
      --owner) owner="${2:-}"; shift 2 ;;
      --outcome) outcome="${2:-}"; shift 2 ;;
      --capability) capability="${2:-}"; shift 2 ;;
      --layer) layer="${2:-}"; shift 2 ;;
      --depends-on) depends="${2:-}"; shift 2 ;;
      --linked) linked="${2:-}"; shift 2 ;;
      --changed) changed="${2:-}"; shift 2 ;;
      --red) red="${2:-}"; shift 2 ;;
      --impl) impl="${2:-}"; shift 2 ;;
      --green) green="${2:-}"; shift 2 ;;
      --verify) verify="${2:-}"; shift 2 ;;
      --unit-normal) unit_normal="${2:-}"; shift 2 ;;
      --unit-boundary) unit_boundary="${2:-}"; shift 2 ;;
      --unit-failure) unit_failure="${2:-}"; shift 2 ;;
      --boundary-smoke) boundary_smoke="${2:-}"; shift 2 ;;
      --from) scenario_dir="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for create: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$id" || -z "$title" || -z "$owner" || -z "$outcome" || -z "$capability" || -z "$layer" || -z "$linked" || -z "$changed" || -z "$red" || -z "$impl" || -z "$green" || -z "$verify" || -z "$unit_normal" || -z "$unit_boundary" || -z "$unit_failure" || -z "$boundary_smoke" ]]; then
    echo "ERROR: create requires all mandatory fields (see usage)." >&2
    exit 1
  fi
  validate_layer_value "$layer" "stability_layer" "create"

  ensure_dir "$scenario_dir"
  local existing
  existing="$(find_scenario_file_by_id "$scenario_dir" "$id" || true)"
  if [[ -n "$existing" ]]; then
    echo "ERROR: scenario id already exists: $id ($existing)" >&2
    exit 1
  fi

  local file="$scenario_dir/${id}.scenario.yml"
  cat > "$file" <<EOF
id: $id
title: "$(escape_yaml_double_quoted "$title")"
owner: "$(escape_yaml_double_quoted "$owner")"
outcome_id: "$(escape_yaml_double_quoted "$outcome")"
capability_id: "$(escape_yaml_double_quoted "$capability")"
stability_layer: "$(escape_yaml_double_quoted "$layer")"
depends_on: "$(escape_yaml_double_quoted "$depends")"
linked_nodes: "$(escape_yaml_double_quoted "$linked")"
changed_paths: "$(escape_yaml_double_quoted "$changed")"
red_run: "$(escape_yaml_double_quoted "$red")"
impl_run: "$(escape_yaml_double_quoted "$impl")"
green_run: "$(escape_yaml_double_quoted "$green")"
verify: "$(escape_yaml_double_quoted "$verify")"
unit_normal_tests: "$(escape_yaml_double_quoted "$unit_normal")"
unit_boundary_tests: "$(escape_yaml_double_quoted "$unit_boundary")"
unit_failure_tests: "$(escape_yaml_double_quoted "$unit_failure")"
boundary_smoke_tests: "$(escape_yaml_double_quoted "$boundary_smoke")"
EOF

  validate_contract_file "$file" 0
  echo "Created scenario: $file"
}

cmd_set() {
  local scenario_dir="$DEFAULT_SCENARIO_DIR"
  local id="" field="" value=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="${2:-}"; shift 2 ;;
      --field) field="${2:-}"; shift 2 ;;
      --value) value="${2:-}"; shift 2 ;;
      --from) scenario_dir="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for set: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
  if [[ -z "$id" || -z "$field" ]]; then
    echo "ERROR: set requires --id and --field" >&2
    exit 1
  fi
  local file
  file="$(find_scenario_file_by_id "$scenario_dir" "$id" || true)"
  if [[ -z "$file" ]]; then
    echo "ERROR: scenario id not found: $id" >&2
    exit 1
  fi
  write_field "$file" "$field" "$value"
  validate_contract_file "$file" 0
  echo "Updated field '$field' in scenario: $file"
}

cmd_delete() {
  local scenario_dir="$DEFAULT_SCENARIO_DIR"
  local id=""
  local yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="${2:-}"; shift 2 ;;
      --yes) yes=1; shift ;;
      --from) scenario_dir="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for delete: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
  if [[ -z "$id" ]]; then
    echo "ERROR: delete requires --id" >&2
    exit 1
  fi
  if [[ "$yes" -ne 1 ]]; then
    echo "ERROR: delete requires --yes for safety" >&2
    exit 1
  fi
  local file
  file="$(find_scenario_file_by_id "$scenario_dir" "$id" || true)"
  if [[ -z "$file" ]]; then
    echo "ERROR: scenario id not found: $id" >&2
    exit 1
  fi
  rm -f "$file"
  echo "Deleted scenario: $id"
}

cmd_validate() {
  local scenario_dir="$DEFAULT_SCENARIO_DIR"
  local id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="${2:-}"; shift 2 ;;
      --from) scenario_dir="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for validate: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  ensure_dir "$scenario_dir"
  if [[ ! -x "$PRODUCT_TRUTH_VALIDATE_SCRIPT" ]]; then
    echo "ERROR: product-truth validator not executable: $PRODUCT_TRUTH_VALIDATE_SCRIPT" >&2
    exit 1
  fi
  if [[ ! -x "$GOAL_GOV_VALIDATE_SCRIPT" ]]; then
    echo "ERROR: goal-governance validator not executable: $GOAL_GOV_VALIDATE_SCRIPT" >&2
    exit 1
  fi
  local project_root
  project_root="$(resolve_project_root_for_dir "$scenario_dir")"

  if [[ -n "$id" ]]; then
    local file
    file="$(find_scenario_file_by_id "$scenario_dir" "$id" || true)"
    if [[ -z "$file" ]]; then
      echo "ERROR: scenario id not found: $id" >&2
      exit 1
    fi
    local all_ids_csv
    all_ids_csv="$(collect_all_ids "$scenario_dir" | paste -sd, -)"
    validate_contract_file "$file" 1 "$all_ids_csv"
    "$PRODUCT_TRUTH_VALIDATE_SCRIPT" \
      --project-root "$project_root" \
      --scenario-dir "$scenario_dir" \
      --require-scenarios >/dev/null
    "$GOAL_GOV_VALIDATE_SCRIPT" \
      --project-root "$project_root" \
      --scenario-dir "$scenario_dir" \
      --require-scenarios \
      --strict >/dev/null
    echo "Scenario contract + product-truth valid: $id"
    return 0
  fi

  if [[ ! -x "$DAG_BUILD_SCRIPT" ]]; then
    echo "ERROR: dag_build.sh not executable: $DAG_BUILD_SCRIPT" >&2
    exit 1
  fi
  local tmp_out
  tmp_out="$(mktemp)"
  "$DAG_BUILD_SCRIPT" --from "$scenario_dir" --out "$tmp_out" --dry-run >/dev/null
  rm -f "$tmp_out"
  echo "Scenario catalog + product-truth valid: $scenario_dir"
}

cmd_scaffold() {
  local scenario_dir="$DEFAULT_SCENARIO_DIR"
  local id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="${2:-}"; shift 2 ;;
      --from) scenario_dir="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for scaffold: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
  if [[ -z "$id" ]]; then
    echo "ERROR: scaffold requires --id" >&2
    exit 1
  fi
  ensure_dir "$scenario_dir"
  local file="$scenario_dir/${id}.scenario.yml"
  if [[ -f "$file" ]]; then
    echo "ERROR: scaffold target already exists: $file" >&2
    exit 1
  fi

  cat > "$file" <<EOF
id: $id
title: "TODO"
owner: "TODO"
outcome_id: "OUT-001"
capability_id: "CAP-001"
stability_layer: "system"
depends_on: ""
linked_nodes: "TODO_LINKED_SCENARIO_ID"
changed_paths: "src/**,tests/**"
red_run: "TODO_RED_COMMAND"
impl_run: "TODO_IMPL_COMMAND"
green_run: "TODO_GREEN_COMMAND"
verify: "TODO_VERIFY_COMMAND"
unit_normal_tests: "TODO_NORMAL_1|||TODO_NORMAL_2"
unit_boundary_tests: "TODO_BOUNDARY_1|||TODO_BOUNDARY_2"
unit_failure_tests: "TODO_FAILURE_1|||TODO_FAILURE_2"
boundary_smoke_tests: "TODO_SMOKE_1|||TODO_SMOKE_2|||TODO_SMOKE_3|||TODO_SMOKE_4|||TODO_SMOKE_5"
EOF
  echo "Scaffold created: $file"
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  list) cmd_list "$@" ;;
  show) cmd_show "$@" ;;
  summary) cmd_summary "$@" ;;
  create) cmd_create "$@" ;;
  set) cmd_set "$@" ;;
  delete) cmd_delete "$@" ;;
  validate) cmd_validate "$@" ;;
  scaffold) cmd_scaffold "$@" ;;
  --help|-h|help) usage ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac
