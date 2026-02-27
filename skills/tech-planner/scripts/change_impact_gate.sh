#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  change_impact_gate.sh [options]

Options:
  --project-root <path>      Repository root (default: git root or cwd)
  --base-ref <ref>           Base git ref for diff (default: HEAD~1)
  --head-ref <ref>           Head git ref for diff (default: HEAD)
  --changed-file <path>      Explicit changed file (repeatable)
  --format <text|markdown|json>
  --emit-required-verification
  --enforce-layer-guard
  --help

Notes:
  - If --changed-file is provided, git diff refs are not required.
  - Layer guard blocks when impacted scenarios include `core` and no active override is present.
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
BASE_REF="HEAD~1"
HEAD_REF="HEAD"
FORMAT="text"
EMIT_REQUIRED_VERIFICATION=0
ENFORCE_LAYER_GUARD=0
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
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    --emit-required-verification)
      EMIT_REQUIRED_VERIFICATION=1
      shift
      ;;
    --enforce-layer-guard)
      ENFORCE_LAYER_GUARD=1
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

if [[ "$FORMAT" != "text" && "$FORMAT" != "markdown" && "$FORMAT" != "json" ]]; then
  echo "ERROR: --format must be one of text|markdown|json" >&2
  exit 1
fi

PROJECT_ROOT="$(resolve_project_root "$PROJECT_ROOT")"

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: git repository required when --changed-file is not provided." >&2
    exit 1
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] && CHANGED_FILES+=("$f")
  done < <(git -C "$PROJECT_ROOT" diff --name-only "$BASE_REF" "$HEAD_REF")
fi

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  echo "No changed files detected for impact analysis."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required for change impact gate." >&2
  exit 1
fi

CHANGED_FILES_JOINED="$(printf '%s\n' "${CHANGED_FILES[@]}")"

python3 - "$PROJECT_ROOT" "$BASE_REF" "$HEAD_REF" "$FORMAT" "$EMIT_REQUIRED_VERIFICATION" "$ENFORCE_LAYER_GUARD" "$CHANGED_FILES_JOINED" <<'PY'
import datetime as dt
import fnmatch
import json
import re
import subprocess
import sys
from collections import defaultdict, deque
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"ERROR: PyYAML is required for change impact gate: {exc}", file=sys.stderr)
    raise SystemExit(1)


def fail(msg: str, code: int = 1):
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(code)


def load_yaml(path: Path):
    if not path.exists():
        return None
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"invalid YAML at {path}: {exc}")
    if data is None:
        return None
    if not isinstance(data, dict):
        fail(f"expected mapping YAML at {path}")
    return data


def run_git(args, cwd: Path) -> str:
    proc = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    if proc.returncode != 0:
        return ""
    return proc.stdout


def parse_csv(value: str):
    if not value:
        return []
    return [x.strip() for x in value.split(",") if x.strip()]


def parse_changed_paths(value: str):
    return parse_csv(value)


def extract_ids_from_patch(text: str):
    ids = {
        "vision_ids": set(re.findall(r"VIS-[A-Z0-9-]+", text)),
        "pillar_ids": set(re.findall(r"PIL-[A-Z0-9-]+", text)),
        "objective_ids": set(re.findall(r"OBJ-[A-Z0-9-]+", text)),
        "outcome_ids": set(re.findall(r"OUT-[A-Z0-9-]+", text)),
        "capability_ids": set(re.findall(r"CAP-[A-Z0-9-]+", text)),
    }
    return ids


def active_core_override(overrides_doc):
    if not overrides_doc:
        return None
    overrides = overrides_doc.get("overrides")
    if not isinstance(overrides, list):
        return None
    now = dt.datetime.now(dt.timezone.utc)
    for item in overrides:
        if not isinstance(item, dict):
            continue
        if str(item.get("layer", "core")) != "core":
            continue
        if item.get("enabled", True) is False:
            continue
        expires_at = item.get("expires_at")
        if not isinstance(expires_at, str):
            continue
        try:
            expiry = dt.datetime.strptime(expires_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
        except Exception:
            continue
        if expiry > now:
            return {
                "id": item.get("id", "(no-id)"),
                "approved_by": item.get("approved_by", "(unknown)"),
                "expires_at": expires_at,
                "reason": item.get("reason", ""),
            }
    return None


project_root = Path(sys.argv[1]).resolve()
base_ref = sys.argv[2]
head_ref = sys.argv[3]
out_format = sys.argv[4]
emit_required = int(sys.argv[5]) == 1
enforce_layer_guard = int(sys.argv[6]) == 1
changed_raw = sys.argv[7]
changed_files = [line.strip() for line in changed_raw.splitlines() if line.strip()]

truth_dir = project_root / ".sigee" / "product-truth"
scenario_dir = project_root / ".sigee" / "dag" / "scenarios"

vision_doc = load_yaml(truth_dir / "vision.yaml") or {}
pillars_doc = load_yaml(truth_dir / "pillars.yaml") or {}
objectives_doc = load_yaml(truth_dir / "objectives.yaml") or {}
outcomes_doc = load_yaml(truth_dir / "outcomes.yaml") or {}
caps_doc = load_yaml(truth_dir / "capabilities.yaml") or {}
trace_doc = load_yaml(truth_dir / "traceability.yaml") or {}
overrides_doc = load_yaml(truth_dir / "core-overrides.yaml") or {}

visions = vision_doc.get("visions") if isinstance(vision_doc.get("visions"), list) else []
pillars = pillars_doc.get("pillars") if isinstance(pillars_doc.get("pillars"), list) else []
objectives = objectives_doc.get("objectives") if isinstance(objectives_doc.get("objectives"), list) else []
outcomes = outcomes_doc.get("outcomes") if isinstance(outcomes_doc.get("outcomes"), list) else []
capabilities = caps_doc.get("capabilities") if isinstance(caps_doc.get("capabilities"), list) else []
links = trace_doc.get("links") if isinstance(trace_doc.get("links"), list) else []

vision_by_id = {item.get("id"): item for item in visions if isinstance(item, dict) and item.get("id")}
pillar_by_id = {item.get("id"): item for item in pillars if isinstance(item, dict) and item.get("id")}
objective_by_id = {item.get("id"): item for item in objectives if isinstance(item, dict) and item.get("id")}
outcome_by_id = {item.get("id"): item for item in outcomes if isinstance(item, dict) and item.get("id")}
cap_by_id = {item.get("id"): item for item in capabilities if isinstance(item, dict) and item.get("id")}

outcomes_by_objective = defaultdict(set)
for o in outcomes:
    if not isinstance(o, dict):
        continue
    oid = o.get("id")
    objective_id = o.get("objective_id")
    if oid and objective_id:
        outcomes_by_objective[objective_id].add(oid)

caps_by_outcome = defaultdict(set)
for c in capabilities:
    if not isinstance(c, dict):
        continue
    cid = c.get("id")
    oid = c.get("outcome_id")
    if cid and oid:
        caps_by_outcome[oid].add(cid)

scenarios_by_cap = defaultdict(set)
scenario_layer = {}
link_by_scenario = {}
for link in links:
    if not isinstance(link, dict):
        continue
    sid = link.get("scenario_id")
    cid = link.get("capability_id")
    if sid and cid:
        scenarios_by_cap[cid].add(sid)
        layer = str(link.get("stability_layer", ""))
        if layer:
            scenario_layer[sid] = layer
        link_by_scenario[sid] = link

scenario_docs = {}
reverse_dep = defaultdict(set)
if scenario_dir.exists():
    for path in sorted(scenario_dir.glob("*.scenario.yml")):
        doc = load_yaml(path)
        if not isinstance(doc, dict):
            continue
        sid = doc.get("id")
        if not isinstance(sid, str) or not sid:
            continue
        depends_on = parse_csv(str(doc.get("depends_on", "")))
        linked_nodes = parse_csv(str(doc.get("linked_nodes", "")))
        changed_paths = parse_changed_paths(str(doc.get("changed_paths", "")))
        layer = str(doc.get("stability_layer", "")).strip()
        scenario_docs[sid] = {
            "path": str(path.relative_to(project_root)),
            "depends_on": depends_on,
            "linked_nodes": linked_nodes,
            "changed_paths": changed_paths,
            "stability_layer": layer,
        }
        if layer:
            scenario_layer[sid] = layer
        for dep in depends_on:
            reverse_dep[dep].add(sid)

changed_file_set = set(changed_files)

impacted_scenarios = set()
product_truth_changed = any(p.startswith(".sigee/product-truth/") for p in changed_file_set)

# Scenario direct/file-pattern impact.
for sid, meta in scenario_docs.items():
    scenario_path = meta["path"]
    if scenario_path in changed_file_set:
        impacted_scenarios.add(sid)
        continue
    for changed in changed_files:
        if any(fnmatch.fnmatch(changed, pat) for pat in meta["changed_paths"]):
            impacted_scenarios.add(sid)
            break

# Product truth patch-derived impact.
ids_from_patch = {
    "vision_ids": set(),
    "pillar_ids": set(),
    "objective_ids": set(),
    "outcome_ids": set(),
    "capability_ids": set(),
}
for rel in [
    ".sigee/product-truth/vision.yaml",
    ".sigee/product-truth/pillars.yaml",
    ".sigee/product-truth/objectives.yaml",
    ".sigee/product-truth/outcomes.yaml",
    ".sigee/product-truth/capabilities.yaml",
    ".sigee/product-truth/traceability.yaml",
]:
    patch = run_git(["diff", "-U0", base_ref, head_ref, "--", rel], project_root)
    if not patch:
        continue
    extracted = extract_ids_from_patch(patch)
    for k in ids_from_patch:
        ids_from_patch[k].update(extracted[k])

if product_truth_changed and not any(ids_from_patch.values()):
    # Conservative fallback when semantic extraction misses specific IDs.
    impacted_scenarios.update(scenario_docs.keys())

# Resolve ID-derived impacts.
resolved_outcomes = set(ids_from_patch["outcome_ids"])
resolved_caps = set(ids_from_patch["capability_ids"])

for obj_id in ids_from_patch["objective_ids"]:
    resolved_outcomes.update(outcomes_by_objective.get(obj_id, set()))

for pil_id in ids_from_patch["pillar_ids"]:
    for obj in objectives:
        if isinstance(obj, dict) and obj.get("pillar_id") == pil_id and obj.get("id"):
            resolved_outcomes.update(outcomes_by_objective.get(obj["id"], set()))

for vis_id in ids_from_patch["vision_ids"]:
    for pil in pillars:
        if isinstance(pil, dict) and pil.get("vision_id") == vis_id and pil.get("id"):
            pid = pil["id"]
            for obj in objectives:
                if isinstance(obj, dict) and obj.get("pillar_id") == pid and obj.get("id"):
                    resolved_outcomes.update(outcomes_by_objective.get(obj["id"], set()))

for out_id in list(resolved_outcomes):
    resolved_caps.update(caps_by_outcome.get(out_id, set()))

for cap_id in list(resolved_caps):
    impacted_scenarios.update(scenarios_by_cap.get(cap_id, set()))

# Scenario IDs referenced in patch text.
for patch_sid in re.findall(r"orchestration_[a-z0-9_]+", "\n".join(
    run_git(["diff", "-U0", base_ref, head_ref, "--", rel], project_root)
    for rel in [
        ".sigee/product-truth/traceability.yaml",
        ".sigee/dag/scenarios",
    ]
)):
    if patch_sid in scenario_docs:
        impacted_scenarios.add(patch_sid)

# Dependency closure (forward + reverse + linked).
q = deque(sorted(impacted_scenarios))
while q:
    sid = q.popleft()
    meta = scenario_docs.get(sid)
    if not meta:
        continue
    neighbors = set(meta["depends_on"]) | set(meta["linked_nodes"]) | set(reverse_dep.get(sid, set()))
    for nxt in neighbors:
        if nxt in scenario_docs and nxt not in impacted_scenarios:
            impacted_scenarios.add(nxt)
            q.append(nxt)

impacted_caps = set()
impacted_outcomes = set()
for sid in impacted_scenarios:
    link = link_by_scenario.get(sid)
    if not link:
        continue
    cid = link.get("capability_id")
    oid = link.get("outcome_id")
    if cid:
        impacted_caps.add(cid)
    if oid:
        impacted_outcomes.add(oid)

# Up-hierarchy expansion.
impacted_objectives = set()
impacted_pillars = set()
impacted_visions = set()
for out_id in impacted_outcomes:
    out = outcome_by_id.get(out_id, {})
    obj_id = out.get("objective_id")
    if obj_id:
        impacted_objectives.add(obj_id)
for obj_id in impacted_objectives:
    obj = objective_by_id.get(obj_id, {})
    pil_id = obj.get("pillar_id")
    if pil_id:
        impacted_pillars.add(pil_id)
for pil_id in impacted_pillars:
    pil = pillar_by_id.get(pil_id, {})
    vis_id = pil.get("vision_id")
    if vis_id:
        impacted_visions.add(vis_id)

layer_counts = defaultdict(int)
for sid in impacted_scenarios:
    layer = scenario_layer.get(sid) or "unknown"
    layer_counts[layer] += 1

required_verification = []
if emit_required:
    required_verification.extend([
        "bash skills/tech-planner/scripts/product_truth_validate.sh --project-root . --require-scenarios",
        "bash skills/tech-planner/scripts/goal_governance_validate.sh --project-root . --strict --require-scenarios",
        "bash skills/tech-planner/scripts/dag_scenario_crud.sh validate --from .sigee/dag/scenarios",
    ])
    if impacted_scenarios:
        required_verification.extend([
            "SIGEE_RUNTIME_ROOT=.sigee/.runtime bash skills/tech-developer/scripts/dag_build.sh --out .sigee/.runtime/dag/pipelines/default.pipeline.yml",
            "SIGEE_RUNTIME_ROOT=.sigee/.runtime bash skills/tech-developer/scripts/dag_run.sh .sigee/.runtime/dag/pipelines/default.pipeline.yml --changed-only",
        ])

core_impacted = sorted([sid for sid in impacted_scenarios if (scenario_layer.get(sid) == "core")])
override = active_core_override(overrides_doc)
layer_guard_pass = True
layer_guard_reason = ""
if enforce_layer_guard and core_impacted:
    if override is None:
        layer_guard_pass = False
        layer_guard_reason = "core layer impact without active override"
    else:
        layer_guard_reason = (
            f"core override active (id={override['id']}, approved_by={override['approved_by']}, expires_at={override['expires_at']})"
        )

payload = {
    "status": "PASS" if layer_guard_pass else "FAIL",
    "changed_files": sorted(changed_file_set),
    "impacted": {
        "visions": sorted(impacted_visions),
        "pillars": sorted(impacted_pillars),
        "objectives": sorted(impacted_objectives),
        "outcomes": sorted(impacted_outcomes),
        "capabilities": sorted(impacted_caps),
        "scenarios": sorted(impacted_scenarios),
    },
    "layer_counts": dict(sorted(layer_counts.items())),
    "core_impacted_scenarios": core_impacted,
    "layer_guard": {
        "enforced": enforce_layer_guard,
        "pass": layer_guard_pass,
        "reason": layer_guard_reason,
    },
    "required_verification": required_verification,
}

if out_format == "json":
    print(json.dumps(payload, ensure_ascii=False, indent=2))
elif out_format == "markdown":
    print("# Change Impact Gate")
    print("")
    print(f"- Status: **{payload['status']}**")
    print(f"- Changed files: {len(payload['changed_files'])}")
    print(f"- Impacted scenarios: {len(payload['impacted']['scenarios'])}")
    if enforce_layer_guard:
      reason = payload['layer_guard']['reason'] or "layer guard passed"
      print(f"- Layer guard: {'PASS' if payload['layer_guard']['pass'] else 'FAIL'} ({reason})")
    print("")
    print("## Impact Summary")
    print("| Level | Count | IDs |")
    print("|---|---:|---|")
    for key in ["visions", "pillars", "objectives", "outcomes", "capabilities", "scenarios"]:
        ids = payload["impacted"][key]
        joined = ", ".join(ids) if ids else "-"
        print(f"| {key} | {len(ids)} | {joined} |")
    print("")
    print("## Layer Distribution")
    if payload["layer_counts"]:
        for layer, count in payload["layer_counts"].items():
            print(f"- {layer}: {count}")
    else:
        print("- none")
    if emit_required:
        print("")
        print("## Required Verification")
        for cmd in payload["required_verification"]:
            print(f"- `{cmd}`")
else:
    print(f"IMPACT_STATUS:{payload['status']}")
    print(f"IMPACT_CHANGED_FILES:{len(payload['changed_files'])}")
    for key in ["visions", "pillars", "objectives", "outcomes", "capabilities", "scenarios"]:
        ids = payload["impacted"][key]
        print(f"IMPACT_{key.upper()}:{','.join(ids)}")
    layer_line = ",".join(f"{k}:{v}" for k, v in payload["layer_counts"].items())
    print(f"IMPACT_LAYERS:{layer_line}")
    print(f"LAYER_GUARD:{'PASS' if payload['layer_guard']['pass'] else 'FAIL'}")
    if payload["layer_guard"]["reason"]:
        print(f"LAYER_GUARD_REASON:{payload['layer_guard']['reason']}")
    if emit_required:
        for cmd in payload["required_verification"]:
            print(f"REQUIRED_VERIFY:{cmd}")

if not layer_guard_pass:
    fail(
        f"layer guard blocked: {layer_guard_reason}; impacted core scenarios: {', '.join(core_impacted)}",
        code=2,
    )
PY
