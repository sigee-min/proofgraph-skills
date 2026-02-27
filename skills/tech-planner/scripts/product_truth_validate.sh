#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  product_truth_validate.sh [--project-root <path>] [--scenario-dir <path>] [--require-scenarios]

Options:
  --project-root <path>   Repository root. Defaults to current git root or cwd.
  --scenario-dir <path>   Scenario directory. Defaults to .sigee/dag/scenarios under project root.
  --require-scenarios     Fail if scenario directory has no *.scenario.yml files.
  --help                  Show this message.
USAGE
}

RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"
if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

resolve_project_root() {
  local candidate="${1:-$(pwd)}"
  if [[ ! -d "$candidate" ]]; then
    echo "ERROR: project root not found: $candidate" >&2
    exit 1
  fi
  if git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$candidate" rev-parse --show-toplevel
  else
    (cd "$candidate" && pwd)
  fi
}

PROJECT_ROOT=""
SCENARIO_DIR=""
REQUIRE_SCENARIOS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --scenario-dir)
      SCENARIO_DIR="${2:-}"
      shift 2
      ;;
    --require-scenarios)
      REQUIRE_SCENARIOS=1
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

PROJECT_ROOT="$(resolve_project_root "$PROJECT_ROOT")"
if [[ -z "$SCENARIO_DIR" ]]; then
  SCENARIO_DIR="$PROJECT_ROOT/.sigee/dag/scenarios"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required for product-truth validation." >&2
  exit 1
fi

python3 - "$PROJECT_ROOT" "$SCENARIO_DIR" "$REQUIRE_SCENARIOS" <<'PY'
import datetime as dt
import os
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"ERROR: PyYAML is required for product-truth validation: {exc}", file=sys.stderr)
    raise SystemExit(1)


def fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def load_yaml(path: Path):
    if not path.exists():
        fail(f"missing required file: {path}")
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"invalid YAML at {path}: {exc}")
    if data is None:
        fail(f"empty YAML file: {path}")
    if not isinstance(data, dict):
        fail(f"expected mapping YAML at {path}")
    return data


def require_utc_timestamp(name: str, value, path: Path):
    if not isinstance(value, str):
        fail(f"{path}: '{name}' must be UTC timestamp string")
    try:
        dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        fail(f"{path}: '{name}' must match YYYY-MM-DDTHH:MM:SSZ")


def require_positive_int(name: str, value, path: Path):
    if not isinstance(value, int) or value < 1:
        fail(f"{path}: '{name}' must be integer >= 1")


def require_list(name: str, value, path: Path):
    if not isinstance(value, list):
        fail(f"{path}: '{name}' must be a list")
    return value


def require_str(name: str, value, path: Path):
    if not isinstance(value, str) or not value.strip():
        fail(f"{path}: '{name}' must be non-empty string")
    return value.strip()


def require_layer(name: str, value, path: Path):
    layer = require_str(name, value, path)
    if layer not in {"core", "system", "experimental"}:
        fail(f"{path}: '{name}' must be one of core|system|experimental (got '{layer}')")
    return layer


def ensure_unique_ids(items, key: str, path: Path):
    seen = set()
    for idx, item in enumerate(items):
        if not isinstance(item, dict):
            fail(f"{path}: '{key}' entry at index {idx} must be mapping")
        v = require_str("id", item.get("id"), path)
        if v in seen:
            fail(f"{path}: duplicate id '{v}'")
        seen.add(v)
    return seen


project_root = Path(sys.argv[1]).resolve()
scenario_dir = Path(sys.argv[2]).resolve()
require_scenarios = int(sys.argv[3]) == 1

product_truth_dir = project_root / ".sigee" / "product-truth"
if not product_truth_dir.exists():
    fail(f"missing product-truth directory: {product_truth_dir}")

outcomes_path = product_truth_dir / "outcomes.yaml"
caps_path = product_truth_dir / "capabilities.yaml"
trace_path = product_truth_dir / "traceability.yaml"
objectives_path = product_truth_dir / "objectives.yaml"

outcomes_doc = load_yaml(outcomes_path)
caps_doc = load_yaml(caps_path)
trace_doc = load_yaml(trace_path)
objectives_doc = load_yaml(objectives_path) if objectives_path.exists() else None

docs = [(outcomes_doc, outcomes_path), (caps_doc, caps_path), (trace_doc, trace_path)]
if objectives_doc is not None:
    docs.append((objectives_doc, objectives_path))

for doc, path in docs:
    require_positive_int("revision", doc.get("revision"), path)
    require_utc_timestamp("updated_at", doc.get("updated_at"), path)

outcomes = require_list("outcomes", outcomes_doc.get("outcomes"), outcomes_path)
caps = require_list("capabilities", caps_doc.get("capabilities"), caps_path)
links = require_list("links", trace_doc.get("links"), trace_path)
objectives = require_list("objectives", objectives_doc.get("objectives"), objectives_path) if objectives_doc is not None else []

if not outcomes:
    fail(f"{outcomes_path}: outcomes must not be empty")
if not caps:
    fail(f"{caps_path}: capabilities must not be empty")
if not links:
    fail(f"{trace_path}: links must not be empty")
if objectives_doc is not None and not objectives:
    fail(f"{objectives_path}: objectives must not be empty")

outcome_ids = ensure_unique_ids(outcomes, "outcomes", outcomes_path)
cap_ids = ensure_unique_ids(caps, "capabilities", caps_path)
objective_ids = ensure_unique_ids(objectives, "objectives", objectives_path) if objectives_doc is not None else set()

cap_to_outcome = {}
cap_layer_defaults = {}
for cap in caps:
    cap_id = require_str("id", cap.get("id"), caps_path)
    outcome_id = require_str("outcome_id", cap.get("outcome_id"), caps_path)
    if outcome_id not in outcome_ids:
        fail(f"{caps_path}: capability '{cap_id}' references unknown outcome_id '{outcome_id}'")
    cap_to_outcome[cap_id] = outcome_id
    cap_layer_defaults[cap_id] = require_layer("stability_layer_default", cap.get("stability_layer_default"), caps_path)

for outcome in outcomes:
    oid = require_str("id", outcome.get("id"), outcomes_path)
    objective_id = require_str("objective_id", outcome.get("objective_id"), outcomes_path)
    if objectives_doc is not None and objective_id not in objective_ids:
        fail(f"{outcomes_path}: outcome '{oid}' references unknown objective_id '{objective_id}'")

link_by_scenario = {}
for idx, link in enumerate(links):
    if not isinstance(link, dict):
        fail(f"{trace_path}: link at index {idx} must be mapping")
    scenario_id = require_str("scenario_id", link.get("scenario_id"), trace_path)
    outcome_id = require_str("outcome_id", link.get("outcome_id"), trace_path)
    capability_id = require_str("capability_id", link.get("capability_id"), trace_path)
    dag_prefix = require_str("dag_node_prefix", link.get("dag_node_prefix"), trace_path)
    link_layer = require_layer("stability_layer", link.get("stability_layer"), trace_path)

    if scenario_id in link_by_scenario:
        fail(f"{trace_path}: duplicate scenario_id in links: '{scenario_id}'")
    if outcome_id not in outcome_ids:
        fail(f"{trace_path}: link scenario '{scenario_id}' references unknown outcome_id '{outcome_id}'")
    if capability_id not in cap_ids:
        fail(f"{trace_path}: link scenario '{scenario_id}' references unknown capability_id '{capability_id}'")
    expected_outcome = cap_to_outcome[capability_id]
    if outcome_id != expected_outcome:
        fail(
            f"{trace_path}: link scenario '{scenario_id}' has inconsistent outcome/capability pair "
            f"('{outcome_id}' vs capability '{capability_id}' -> '{expected_outcome}')"
        )
    expected_layer = cap_layer_defaults[capability_id]
    if link_layer != expected_layer:
        fail(
            f"{trace_path}: scenario '{scenario_id}' layer '{link_layer}' does not match "
            f"capability '{capability_id}' default layer '{expected_layer}'"
        )

    contract = link.get("required_test_contract")
    if not isinstance(contract, dict):
        fail(f"{trace_path}: scenario '{scenario_id}' missing required_test_contract mapping")
    required = {
        "unit_normal": 2,
        "unit_boundary": 2,
        "unit_failure": 2,
        "boundary_smoke": 5,
    }
    for key, expected in required.items():
        val = contract.get(key)
        if val != expected:
            fail(
                f"{trace_path}: scenario '{scenario_id}' required_test_contract.{key} "
                f"must be {expected} (got {val!r})"
            )

    if not dag_prefix:
        fail(f"{trace_path}: scenario '{scenario_id}' dag_node_prefix must be non-empty")
    link_by_scenario[scenario_id] = {
        "outcome_id": outcome_id,
        "capability_id": capability_id,
        "dag_node_prefix": dag_prefix,
        "stability_layer": link_layer,
    }

scenario_files = sorted(scenario_dir.glob("*.scenario.yml")) if scenario_dir.exists() else []
if require_scenarios and not scenario_files:
    fail(f"no scenario files found in required scenario directory: {scenario_dir}")

if scenario_files:
    seen_scenario_ids = set()
    for path in scenario_files:
        doc = load_yaml(path)
        sid = require_str("id", doc.get("id"), path)
        if sid in seen_scenario_ids:
            fail(f"duplicate scenario id in scenario catalog: '{sid}' ({path})")
        seen_scenario_ids.add(sid)

        outcome_id = require_str("outcome_id", doc.get("outcome_id"), path)
        capability_id = require_str("capability_id", doc.get("capability_id"), path)
        stability_layer = require_layer("stability_layer", doc.get("stability_layer"), path)
        linked_nodes = require_str("linked_nodes", doc.get("linked_nodes"), path)
        changed_paths = require_str("changed_paths", doc.get("changed_paths"), path)
        _ = linked_nodes, changed_paths

        if outcome_id not in outcome_ids:
            fail(f"{path}: outcome_id '{outcome_id}' not found in outcomes.yaml")
        if capability_id not in cap_ids:
            fail(f"{path}: capability_id '{capability_id}' not found in capabilities.yaml")

        expected_outcome = cap_to_outcome[capability_id]
        if outcome_id != expected_outcome:
            fail(
                f"{path}: outcome/capability mismatch "
                f"('{outcome_id}' vs capability '{capability_id}' -> '{expected_outcome}')"
            )

        link = link_by_scenario.get(sid)
        if link is None:
            fail(f"{path}: scenario id '{sid}' is missing in traceability.yaml links")
        if link["outcome_id"] != outcome_id or link["capability_id"] != capability_id:
            fail(
                f"{path}: scenario id '{sid}' does not match traceability mapping "
                f"(scenario outcome/capability={outcome_id}/{capability_id}, "
                f"traceability={link['outcome_id']}/{link['capability_id']})"
            )
        if stability_layer != link["stability_layer"]:
            fail(
                f"{path}: scenario id '{sid}' stability_layer '{stability_layer}' "
                f"must match traceability '{link['stability_layer']}'"
            )
        if not sid.startswith(link["dag_node_prefix"]):
            fail(
                f"{path}: scenario id '{sid}' must start with dag_node_prefix "
                f"'{link['dag_node_prefix']}' from traceability.yaml"
            )

    missing_scenarios = sorted(set(link_by_scenario.keys()) - seen_scenario_ids)
    if missing_scenarios:
        fail(
            "traceability.yaml includes scenario ids not present in scenario catalog: "
            + ", ".join(missing_scenarios)
        )

print(
    "Product-truth validation passed: "
    f"root={project_root} scenarios={scenario_dir} "
    f"counts(outcomes={len(outcomes)},capabilities={len(caps)},links={len(links)},scenario_files={len(scenario_files)})"
)
PY
