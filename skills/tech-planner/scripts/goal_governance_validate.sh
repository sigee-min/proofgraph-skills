#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  goal_governance_validate.sh [--project-root <path>] [--scenario-dir <path>] [--require-scenarios] [--strict]

Options:
  --project-root <path>   Repository root. Defaults to current git root or cwd.
  --scenario-dir <path>   Scenario directory. Defaults to .sigee/dag/scenarios under project root.
  --require-scenarios     Fail if scenario directory has no *.scenario.yml files.
  --strict                Require full goal hierarchy files and strict parity checks.
  --help                  Show this message.
USAGE
}

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
STRICT=0

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
    --strict)
      STRICT=1
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_VALIDATE="$SCRIPT_DIR/product_truth_validate.sh"
if [[ ! -x "$BASE_VALIDATE" ]]; then
  echo "ERROR: base product-truth validator not executable: $BASE_VALIDATE" >&2
  exit 1
fi

base_cmd=("$BASE_VALIDATE" --project-root "$PROJECT_ROOT" --scenario-dir "$SCENARIO_DIR")
if [[ "$REQUIRE_SCENARIOS" -eq 1 ]]; then
  base_cmd+=(--require-scenarios)
fi
"${base_cmd[@]}" >/dev/null

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required for goal governance validation." >&2
  exit 1
fi

python3 - "$PROJECT_ROOT" "$SCENARIO_DIR" "$REQUIRE_SCENARIOS" "$STRICT" <<'PY'
import datetime as dt
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"ERROR: PyYAML is required for goal governance validation: {exc}", file=sys.stderr)
    raise SystemExit(1)


def fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def load_yaml(path: Path, required: bool = True):
    if not path.exists():
        if required:
            fail(f"missing required file: {path}")
        return None
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"invalid YAML at {path}: {exc}")
    if data is None:
        fail(f"empty YAML file: {path}")
    if not isinstance(data, dict):
        fail(f"expected mapping YAML at {path}")
    return data


def require_str(name: str, value, path: Path) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{path}: '{name}' must be non-empty string")
    return value.strip()


def require_positive_int(name: str, value, path: Path) -> int:
    if not isinstance(value, int) or value < 1:
        fail(f"{path}: '{name}' must be integer >= 1")
    return value


def parse_utc(name: str, value, path: Path) -> dt.datetime:
    if not isinstance(value, str):
        fail(f"{path}: '{name}' must be UTC timestamp string")
    try:
        parsed = dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        fail(f"{path}: '{name}' must match YYYY-MM-DDTHH:MM:SSZ")
    parsed = parsed.replace(tzinfo=dt.timezone.utc)
    now = dt.datetime.now(dt.timezone.utc)
    if parsed > now + dt.timedelta(minutes=1):
        fail(f"{path}: '{name}' must not be in the future")
    return parsed


def parse_utc_allow_future(name: str, value, path: Path) -> dt.datetime:
    if not isinstance(value, str):
        fail(f"{path}: '{name}' must be UTC timestamp string")
    try:
        parsed = dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        fail(f"{path}: '{name}' must match YYYY-MM-DDTHH:MM:SSZ")
    return parsed.replace(tzinfo=dt.timezone.utc)


def require_list(name: str, value, path: Path):
    if not isinstance(value, list):
        fail(f"{path}: '{name}' must be a list")
    return value


def ensure_unique_id(items, id_key: str, path: Path):
    seen = set()
    for idx, item in enumerate(items):
        if not isinstance(item, dict):
            fail(f"{path}: item at index {idx} must be mapping")
        v = require_str(id_key, item.get(id_key), path)
        if v in seen:
            fail(f"{path}: duplicate {id_key} '{v}'")
        seen.add(v)
    return seen


def require_layer(name: str, value, path: Path) -> str:
    value = require_str(name, value, path)
    allowed = {"core", "system", "experimental"}
    if value not in allowed:
        fail(f"{path}: '{name}' must be one of core|system|experimental (got '{value}')")
    return value


project_root = Path(sys.argv[1]).resolve()
scenario_dir = Path(sys.argv[2]).resolve()
require_scenarios = int(sys.argv[3]) == 1
strict = int(sys.argv[4]) == 1

truth_dir = project_root / ".sigee" / "product-truth"
if not truth_dir.exists():
    fail(f"missing product-truth directory: {truth_dir}")

vision_path = truth_dir / "vision.yaml"
pillars_path = truth_dir / "pillars.yaml"
objectives_path = truth_dir / "objectives.yaml"
outcomes_path = truth_dir / "outcomes.yaml"
caps_path = truth_dir / "capabilities.yaml"
trace_path = truth_dir / "traceability.yaml"
overrides_path = truth_dir / "core-overrides.yaml"

vision_doc = load_yaml(vision_path, required=strict)
pillars_doc = load_yaml(pillars_path, required=strict)
objectives_doc = load_yaml(objectives_path, required=strict)
outcomes_doc = load_yaml(outcomes_path, required=True)
caps_doc = load_yaml(caps_path, required=True)
trace_doc = load_yaml(trace_path, required=True)
overrides_doc = load_yaml(overrides_path, required=strict)

if strict and (vision_doc is None or pillars_doc is None or objectives_doc is None):
    fail("strict mode requires vision.yaml, pillars.yaml, and objectives.yaml")

docs = []
if vision_doc is not None:
    docs.append((vision_doc, vision_path, "visions"))
if pillars_doc is not None:
    docs.append((pillars_doc, pillars_path, "pillars"))
if objectives_doc is not None:
    docs.append((objectives_doc, objectives_path, "objectives"))
docs.extend([
    (outcomes_doc, outcomes_path, "outcomes"),
    (caps_doc, caps_path, "capabilities"),
    (trace_doc, trace_path, "links"),
])

revisions = []
for doc, path, list_key in docs:
    rev = require_positive_int("revision", doc.get("revision"), path)
    parse_utc("updated_at", doc.get("updated_at"), path)
    revisions.append((path.name, rev))
    entries = require_list(list_key, doc.get(list_key), path)
    if strict and not entries:
        fail(f"{path}: '{list_key}' must not be empty in strict mode")

if strict:
    unique_revs = {r for _, r in revisions}
    if len(unique_revs) != 1:
        details = ", ".join(f"{name}:{rev}" for name, rev in revisions)
        fail(f"strict mode requires revision parity across hierarchy docs ({details})")

vision_ids = set()
pillar_ids = set()
objective_ids = set()

if vision_doc is not None:
    visions = require_list("visions", vision_doc.get("visions"), vision_path)
    vision_ids = ensure_unique_id(visions, "id", vision_path)

if pillars_doc is not None:
    pillars = require_list("pillars", pillars_doc.get("pillars"), pillars_path)
    pillar_ids = ensure_unique_id(pillars, "id", pillars_path)
    for pillar in pillars:
        if vision_ids:
            vision_id = require_str("vision_id", pillar.get("vision_id"), pillars_path)
            if vision_id not in vision_ids:
                fail(f"{pillars_path}: unknown vision_id '{vision_id}'")

if objectives_doc is not None:
    objectives = require_list("objectives", objectives_doc.get("objectives"), objectives_path)
    objective_ids = ensure_unique_id(objectives, "id", objectives_path)
    for objective in objectives:
        if pillar_ids:
            pillar_id = require_str("pillar_id", objective.get("pillar_id"), objectives_path)
            if pillar_id not in pillar_ids:
                fail(f"{objectives_path}: unknown pillar_id '{pillar_id}'")

outcomes = require_list("outcomes", outcomes_doc.get("outcomes"), outcomes_path)
outcome_ids = ensure_unique_id(outcomes, "id", outcomes_path)
outcome_to_objective = {}
for outcome in outcomes:
    oid = require_str("id", outcome.get("id"), outcomes_path)
    objective_id = require_str("objective_id", outcome.get("objective_id"), outcomes_path)
    if objective_ids and objective_id not in objective_ids:
        fail(f"{outcomes_path}: outcome '{oid}' references unknown objective_id '{objective_id}'")
    outcome_to_objective[oid] = objective_id

capabilities = require_list("capabilities", caps_doc.get("capabilities"), caps_path)
cap_ids = ensure_unique_id(capabilities, "id", caps_path)
cap_to_outcome = {}
cap_layer_default = {}
for cap in capabilities:
    cap_id = require_str("id", cap.get("id"), caps_path)
    outcome_id = require_str("outcome_id", cap.get("outcome_id"), caps_path)
    if outcome_id not in outcome_ids:
        fail(f"{caps_path}: capability '{cap_id}' references unknown outcome_id '{outcome_id}'")
    cap_to_outcome[cap_id] = outcome_id
    cap_layer_default[cap_id] = require_layer("stability_layer_default", cap.get("stability_layer_default"), caps_path)

links = require_list("links", trace_doc.get("links"), trace_path)
scenario_to_link = {}
for idx, link in enumerate(links):
    if not isinstance(link, dict):
        fail(f"{trace_path}: link at index {idx} must be mapping")
    scenario_id = require_str("scenario_id", link.get("scenario_id"), trace_path)
    if scenario_id in scenario_to_link:
        fail(f"{trace_path}: duplicate scenario_id '{scenario_id}'")
    outcome_id = require_str("outcome_id", link.get("outcome_id"), trace_path)
    capability_id = require_str("capability_id", link.get("capability_id"), trace_path)
    layer = require_layer("stability_layer", link.get("stability_layer"), trace_path)

    if outcome_id not in outcome_ids:
        fail(f"{trace_path}: scenario '{scenario_id}' references unknown outcome_id '{outcome_id}'")
    if capability_id not in cap_ids:
        fail(f"{trace_path}: scenario '{scenario_id}' references unknown capability_id '{capability_id}'")
    expected_outcome = cap_to_outcome[capability_id]
    if outcome_id != expected_outcome:
        fail(
            f"{trace_path}: scenario '{scenario_id}' outcome/capability mismatch "
            f"('{outcome_id}' vs capability '{capability_id}' -> '{expected_outcome}')"
        )

    expected_layer = cap_layer_default[capability_id]
    if strict and layer != expected_layer:
        fail(
            f"{trace_path}: scenario '{scenario_id}' layer '{layer}' must match "
            f"capability default '{expected_layer}'"
        )

    scenario_to_link[scenario_id] = {
        "outcome_id": outcome_id,
        "capability_id": capability_id,
        "layer": layer,
    }

if scenario_dir.exists():
    scenario_files = sorted(scenario_dir.glob("*.scenario.yml"))
else:
    scenario_files = []

if require_scenarios and not scenario_files:
    fail(f"no scenario files found in required scenario directory: {scenario_dir}")

scenario_ids_seen = set()
for path in scenario_files:
    doc = load_yaml(path, required=True)
    sid = require_str("id", doc.get("id"), path)
    if sid in scenario_ids_seen:
        fail(f"duplicate scenario id in scenario dir: '{sid}'")
    scenario_ids_seen.add(sid)

    outcome_id = require_str("outcome_id", doc.get("outcome_id"), path)
    capability_id = require_str("capability_id", doc.get("capability_id"), path)
    layer = require_layer("stability_layer", doc.get("stability_layer"), path)

    link = scenario_to_link.get(sid)
    if link is None:
        fail(f"{path}: scenario '{sid}' missing in traceability links")
    if outcome_id != link["outcome_id"] or capability_id != link["capability_id"]:
        fail(
            f"{path}: mismatch with traceability mapping for '{sid}' "
            f"(scenario={outcome_id}/{capability_id}, traceability={link['outcome_id']}/{link['capability_id']})"
        )
    if strict and layer != link["layer"]:
        fail(
            f"{path}: stability_layer '{layer}' must match traceability '{link['layer']}' for scenario '{sid}'"
        )

if strict:
    missing = sorted(set(scenario_to_link.keys()) - scenario_ids_seen)
    if missing:
        fail(f"traceability links reference missing scenario files: {', '.join(missing)}")

if overrides_doc is not None:
    require_positive_int("revision", overrides_doc.get("revision"), overrides_path)
    parse_utc("updated_at", overrides_doc.get("updated_at"), overrides_path)
    overrides = require_list("overrides", overrides_doc.get("overrides"), overrides_path)
    for idx, item in enumerate(overrides):
        if not isinstance(item, dict):
            fail(f"{overrides_path}: override index {idx} must be mapping")
        require_str("approved_by", item.get("approved_by"), overrides_path)
        require_str("reason", item.get("reason"), overrides_path)
        parse_utc("created_at", item.get("created_at"), overrides_path)
        expires = parse_utc_allow_future("expires_at", item.get("expires_at"), overrides_path)
        layer = item.get("layer", "core")
        if layer != "core":
            fail(f"{overrides_path}: override index {idx} layer must be 'core'")
        if expires <= dt.datetime.now(dt.timezone.utc):
            fail(f"{overrides_path}: override index {idx} expires_at must be in the future")

print(
    "Goal governance validation passed: "
    f"visions={len(vision_ids)} pillars={len(pillar_ids)} objectives={len(objective_ids)} "
    f"outcomes={len(outcome_ids)} capabilities={len(cap_ids)} scenarios={len(scenario_to_link)} strict={strict}"
)
PY
