#!/usr/bin/env node

import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { runCommand, runCommandOrThrow } from "./command-runner.mjs";

function usage() {
  return `Usage:
  dag-build.mjs [--from <scenario-dir>] [--source <ux-scenario-dir>] [--out <pipeline-file>] [--dry-run] [--synthetic-nodes <count>] [--no-compile] [--enforce-layer-guard] [--changed-file <path>]

Examples:
  SIGEE_RUNTIME_ROOT=.sigee/.runtime node scripts/node/runtime/dag-build.mjs --out .sigee/.runtime/dag/pipelines/default.pipeline.yml
  SIGEE_RUNTIME_ROOT=.sigee/.runtime node scripts/node/runtime/dag-build.mjs --source .sigee/dag/scenarios --out .sigee/.runtime/dag/pipelines/default.pipeline.yml --dry-run
  SIGEE_RUNTIME_ROOT=.sigee/.runtime node scripts/node/runtime/dag-build.mjs --out .sigee/.runtime/dag/pipelines/synthetic-200.pipeline.yml --synthetic-nodes 200
`;
}

function fail(message) {
  throw new Error(message);
}

function trim(value) {
  return String(value ?? "").trim();
}

function normalize(value) {
  let out = String(value ?? "");
  if ((out.startsWith('"') && out.endsWith('"')) || (out.startsWith("'") && out.endsWith("'"))) {
    out = out.slice(1, -1);
  }
  return out;
}

function yamlQuote(value) {
  return String(value ?? "").replaceAll("\\", "\\\\").replaceAll('"', '\\"');
}

function splitCsv(raw) {
  return String(raw ?? "")
    .split(",")
    .map((chunk) => trim(chunk))
    .filter((chunk) => chunk.length > 0);
}

function splitBundle(raw) {
  return String(raw ?? "")
    .split("|||")
    .map((chunk) => trim(chunk))
    .filter((chunk) => chunk.length > 0);
}

function isNoopCommand(cmd) {
  const normalized = trim(cmd);
  return normalized === "true" || normalized === ":";
}

function joinCsv(items) {
  return items.join(",");
}

async function pathExists(targetPath) {
  try {
    await stat(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function resolveProjectRoot() {
  const result = await runCommand("git", ["rev-parse", "--show-toplevel"], {
    allowNonZero: true,
  });
  if (result.code === 0) {
    return path.resolve(trim(result.stdout));
  }
  return process.cwd();
}

function resolvePath(projectRoot, value) {
  if (path.isAbsolute(value)) {
    return path.resolve(value);
  }
  return path.resolve(projectRoot, value);
}

function parseArgs(argv) {
  const args = {
    scenarioDir: "",
    sourceScenarioDir: ".sigee/dag/scenarios",
    outFile: "",
    dryRun: false,
    syntheticNodes: 0,
    compileMode: "auto",
    enforceLayerGuard: false,
    changedFiles: [],
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--from") {
      const value = argv[i + 1];
      if (!value) fail("--from requires a value");
      args.scenarioDir = value;
      i += 1;
      continue;
    }
    if (token === "--source") {
      const value = argv[i + 1];
      if (!value) fail("--source requires a value");
      args.sourceScenarioDir = value;
      i += 1;
      continue;
    }
    if (token === "--out") {
      const value = argv[i + 1];
      if (!value) fail("--out requires a value");
      args.outFile = value;
      i += 1;
      continue;
    }
    if (token === "--dry-run") {
      args.dryRun = true;
      continue;
    }
    if (token === "--synthetic-nodes") {
      const value = argv[i + 1];
      if (!value) fail("--synthetic-nodes requires a value");
      args.syntheticNodes = Number.parseInt(value, 10);
      i += 1;
      continue;
    }
    if (token === "--no-compile") {
      args.compileMode = "off";
      continue;
    }
    if (token === "--enforce-layer-guard") {
      args.enforceLayerGuard = true;
      continue;
    }
    if (token === "--changed-file") {
      const value = argv[i + 1];
      if (!value) fail("--changed-file requires a value");
      args.changedFiles.push(value);
      i += 1;
      continue;
    }
    if (token === "--help" || token === "-h") {
      process.stdout.write(usage());
      process.exit(0);
    }
    fail(`Unknown option: ${token}`);
  }

  return args;
}

function parseScenarioContent(content) {
  const map = new Map();
  const lines = content.split(/\r?\n/);
  for (const line of lines) {
    const match = line.match(/^([a-z_]+):\s*(.*)$/);
    if (!match) continue;
    const key = match[1];
    const raw = match[2];
    map.set(key, trim(normalize(raw)));
  }
  return map;
}

function validateLayer(layer, file) {
  if (!["core", "system", "experimental"].includes(layer)) {
    fail(`stability_layer must be core|system|experimental in scenario file: ${file}`);
  }
}

function validateCommand(cmd, field, file) {
  if (!cmd) {
    fail(`${field} contains an empty command in scenario file: ${file}`);
  }
  if (isNoopCommand(cmd)) {
    fail(`${field} contains no-op command '${cmd}' in scenario file: ${file}`);
  }
}

function validateUniqueCommands(field, file, commands) {
  const seen = new Set();
  for (const command of commands) {
    if (seen.has(command)) {
      fail(`${field} must not contain duplicate commands in scenario file: ${file}`);
    }
    seen.add(command);
  }
}

function ensureBundleCount(field, file, bundle, expected) {
  if (bundle.length !== expected) {
    fail(`${field} must contain exactly ${expected} commands (delimiter '|||') in scenario file: ${file}`);
  }
}

function parseScenarioObjects(scenarioFiles) {
  const scenarios = [];

  for (const file of scenarioFiles) {
    scenarios.push({ file, id: "" });
  }

  return scenarios;
}

async function main() {
  const runtimeRoot = process.env.SIGEE_RUNTIME_ROOT || ".sigee/.runtime";
  if (!runtimeRoot || runtimeRoot === "." || runtimeRoot === ".." || runtimeRoot.startsWith("/") || runtimeRoot.includes("..")) {
    fail("SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)");
  }

  const args = parseArgs(process.argv.slice(2));
  const projectRoot = await resolveProjectRoot();

  const scriptPaths = {
    productTruthValidate: path.join(projectRoot, "skills/tech-planner/scripts/product_truth_validate.sh"),
    goalGovernanceValidate: path.join(projectRoot, "skills/tech-planner/scripts/goal_governance_validate.sh"),
    changeImpactGate: path.join(projectRoot, "skills/tech-planner/scripts/change_impact_gate.sh"),
    dagCompile: path.join(projectRoot, "skills/tech-developer/scripts/dag_compile.sh"),
  };

  const scenarioDir = args.scenarioDir || `${runtimeRoot}/dag/scenarios`;
  const outFile = args.outFile || `${runtimeRoot}/dag/pipelines/default.pipeline.yml`;

  let scenarioDirAbs = resolvePath(projectRoot, scenarioDir);
  const sourceScenarioDirAbs = resolvePath(projectRoot, args.sourceScenarioDir);
  const outFileAbs = resolvePath(projectRoot, outFile);
  const runtimeScenarioDefaultAbs = resolvePath(projectRoot, `${runtimeRoot}/dag/scenarios`);
  let validationScenarioDir = scenarioDirAbs;

  if (args.syntheticNodes === 0 && args.compileMode !== "off" && scenarioDirAbs === runtimeScenarioDefaultAbs) {
    if (!(await pathExists(scriptPaths.dagCompile))) {
      fail(`dag compiler not executable: ${scriptPaths.dagCompile}`);
    }
    if (!(await pathExists(sourceScenarioDirAbs))) {
      fail(`UX scenario source directory not found: ${sourceScenarioDirAbs}`);
    }

    await runCommandOrThrow("bash", [
      scriptPaths.dagCompile,
      "--project-root",
      projectRoot,
      "--source",
      sourceScenarioDirAbs,
      "--out",
      runtimeScenarioDefaultAbs,
    ], {
      cwd: projectRoot,
      env: {
        ...process.env,
        SIGEE_RUNTIME_ROOT: runtimeRoot,
      },
    });

    scenarioDirAbs = runtimeScenarioDefaultAbs;
    validationScenarioDir = sourceScenarioDirAbs;
  }

  if (args.syntheticNodes !== 0) {
    if (!Number.isInteger(args.syntheticNodes) || args.syntheticNodes < 1) {
      fail(`--synthetic-nodes must be an integer >= 1 (got: ${args.syntheticNodes})`);
    }

    const lines = [];
    lines.push("version: 1");
    lines.push(`pipeline_id: synthetic-${args.syntheticNodes}`);
    lines.push("description: Generated synthetic DAG pipeline for scale validation");
    lines.push("nodes:");
    lines.push("  - id: synthetic_preflight");
    lines.push("    type: utility");
    lines.push("    deps: \"\"");
    lines.push("    changed_paths: \"synthetic/**\"");
    lines.push("    run: \"echo synthetic-preflight\"");
    lines.push("    verify: \"echo synthetic-preflight-verify\"");

    for (let n = 1; n <= args.syntheticNodes; n += 1) {
      const nodeId = `synthetic_node_${n}`;
      const deps = n === 1 ? "synthetic_preflight" : `synthetic_node_${n - 1}`;
      lines.push(`  - id: ${nodeId}`);
      lines.push("    type: synthetic");
      lines.push(`    deps: "${deps}"`);
      lines.push("    changed_paths: \"synthetic/**\"");
      lines.push(`    run: "echo run-${nodeId}"`);
      lines.push(`    verify: "echo verify-${nodeId}"`);
    }

    lines.push("  - id: synthetic_smoke_gate");
    lines.push("    type: smoke");
    lines.push(`    deps: "synthetic_node_${args.syntheticNodes}"`);
    lines.push("    changed_paths: \"synthetic/**\"");
    lines.push("    run: \"echo synthetic-smoke\"");
    lines.push("    verify: \"echo synthetic-smoke-verify\"");

    lines.push("  - id: synthetic_e2e_gate");
    lines.push("    type: e2e");
    lines.push("    deps: \"synthetic_smoke_gate\"");
    lines.push("    changed_paths: \"synthetic/**\"");
    lines.push("    run: \"echo synthetic-e2e\"");
    lines.push("    verify: \"echo synthetic-e2e-verify\"");

    const content = `${lines.join("\n")}\n`;
    if (args.dryRun) {
      process.stdout.write(content);
      return;
    }

    await mkdir(path.dirname(outFileAbs), { recursive: true });
    await writeFile(outFileAbs, content, "utf8");
    process.stdout.write(`Synthetic pipeline generated: ${outFileAbs} (nodes=${args.syntheticNodes})\n`);
    return;
  }

  if (!(await pathExists(scenarioDirAbs))) {
    fail(`scenario directory not found: ${scenarioDirAbs}`);
  }

  if (!(await pathExists(scriptPaths.productTruthValidate))) {
    fail(`product-truth validator not executable: ${scriptPaths.productTruthValidate}`);
  }

  await runCommandOrThrow("bash", [
    scriptPaths.productTruthValidate,
    "--project-root",
    projectRoot,
    "--scenario-dir",
    validationScenarioDir,
    "--require-scenarios",
  ], {
    cwd: projectRoot,
    env: {
      ...process.env,
      SIGEE_RUNTIME_ROOT: runtimeRoot,
    },
  });

  if (!(await pathExists(scriptPaths.goalGovernanceValidate))) {
    fail(`goal governance validator not executable: ${scriptPaths.goalGovernanceValidate}`);
  }

  await runCommandOrThrow("bash", [
    scriptPaths.goalGovernanceValidate,
    "--project-root",
    projectRoot,
    "--scenario-dir",
    validationScenarioDir,
    "--require-scenarios",
    "--strict",
  ], {
    cwd: projectRoot,
    env: {
      ...process.env,
      SIGEE_RUNTIME_ROOT: runtimeRoot,
    },
  });

  if (args.enforceLayerGuard) {
    if (!(await pathExists(scriptPaths.changeImpactGate))) {
      fail(`change impact gate script not executable: ${scriptPaths.changeImpactGate}`);
    }

    const gateArgs = [
      scriptPaths.changeImpactGate,
      "--project-root",
      projectRoot,
      "--format",
      "text",
      "--enforce-layer-guard",
    ];
    for (const changed of args.changedFiles) {
      gateArgs.push("--changed-file", changed);
    }

    await runCommandOrThrow("bash", gateArgs, {
      cwd: projectRoot,
      env: {
        ...process.env,
        SIGEE_RUNTIME_ROOT: runtimeRoot,
      },
    });
  }

  const scenarioEntries = await readdir(scenarioDirAbs, { withFileTypes: true });
  const scenarioFiles = scenarioEntries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".scenario.yml"))
    .map((entry) => path.join(scenarioDirAbs, entry.name))
    .sort((a, b) => a.localeCompare(b));

  if (scenarioFiles.length === 0) {
    fail(`no scenario files found in ${scenarioDirAbs} (hard TDD mode requires at least one .scenario.yml).`);
  }

  const scenarioIds = [];
  const scenarioById = new Map();

  for (const file of scenarioFiles) {
    const content = await readFile(file, "utf8");
    const fields = parseScenarioContent(content);
    const scenarioId = trim(normalize(fields.get("id") || ""));
    if (!scenarioId) {
      fail(`missing id in scenario file: ${file}`);
    }
    if (scenarioById.has(scenarioId)) {
      fail(`duplicate scenario id '${scenarioId}' in scenario file: ${file}`);
    }
    scenarioIds.push(scenarioId);
    scenarioById.set(scenarioId, { file, fields });
  }

  function scenarioIdExists(id) {
    return scenarioById.has(id);
  }

  const lines = [];
  lines.push("version: 1");
  lines.push("pipeline_id: default");
  lines.push("description: Generated from scenario catalog");
  lines.push("nodes:");
  lines.push("  - id: preflight");
  lines.push("    type: utility");
  lines.push("    deps: \"\"");
  lines.push("    changed_paths: \".sigee/dag/**,.sigee/product-truth/**,skills/tech-developer/scripts/dag_build.sh,skills/tech-developer/scripts/dag_run.sh\"");
  lines.push("    run: \"bash -n skills/tech-developer/scripts/dag_build.sh skills/tech-developer/scripts/dag_run.sh skills/tech-developer/scripts/test_smoke.sh skills/tech-developer/scripts/test_e2e.sh\"");
  lines.push("    verify: \"true\"");

  const scenarioSmokeIds = [];

  for (const scenarioId of scenarioIds) {
    const { file, fields } = scenarioById.get(scenarioId);

    const outcomeId = trim(normalize(fields.get("outcome_id") || ""));
    const capabilityId = trim(normalize(fields.get("capability_id") || ""));
    const stabilityLayer = trim(normalize(fields.get("stability_layer") || ""));
    const dependsOnRaw = trim(normalize(fields.get("depends_on") || ""));
    const linkedNodesRaw = trim(normalize(fields.get("linked_nodes") || ""));
    const changedPaths = trim(normalize(fields.get("changed_paths") || ""));
    const redRun = trim(normalize(fields.get("red_run") || ""));
    const implRun = trim(normalize(fields.get("impl_run") || ""));
    const greenRun = trim(normalize(fields.get("green_run") || ""));
    const verifyCmd = trim(normalize(fields.get("verify") || ""));
    const unitNormalRaw = trim(normalize(fields.get("unit_normal_tests") || ""));
    const unitBoundaryRaw = trim(normalize(fields.get("unit_boundary_tests") || ""));
    const unitFailureRaw = trim(normalize(fields.get("unit_failure_tests") || ""));
    const boundarySmokeRaw = trim(normalize(fields.get("boundary_smoke_tests") || ""));

    if (!outcomeId) fail(`missing outcome_id in scenario file: ${file}`);
    if (!capabilityId) fail(`missing capability_id in scenario file: ${file}`);
    if (!stabilityLayer) fail(`missing stability_layer in scenario file: ${file}`);
    validateLayer(stabilityLayer, file);
    if (!linkedNodesRaw) {
      fail(`missing linked_nodes in scenario file: ${file} (must reference at least one bug-prone linked scenario id)`);
    }
    if (!changedPaths) fail(`missing changed_paths in scenario file: ${file}`);
    if (!redRun) fail(`missing red_run in scenario file: ${file}`);
    if (!implRun) fail(`missing impl_run in scenario file: ${file}`);
    if (!greenRun) fail(`missing green_run in scenario file: ${file}`);
    if (!verifyCmd) fail(`missing verify in scenario file: ${file}`);

    validateCommand(redRun, "red_run", file);
    validateCommand(implRun, "impl_run", file);
    validateCommand(greenRun, "green_run", file);
    validateCommand(verifyCmd, "verify", file);

    const unitNormal = splitBundle(unitNormalRaw);
    ensureBundleCount("unit_normal_tests", file, unitNormal, 2);
    validateUniqueCommands("unit_normal_tests", file, unitNormal);
    for (const cmd of unitNormal) validateCommand(cmd, "unit_normal_tests", file);

    const unitBoundary = splitBundle(unitBoundaryRaw);
    ensureBundleCount("unit_boundary_tests", file, unitBoundary, 2);
    validateUniqueCommands("unit_boundary_tests", file, unitBoundary);
    for (const cmd of unitBoundary) validateCommand(cmd, "unit_boundary_tests", file);

    const unitFailure = splitBundle(unitFailureRaw);
    ensureBundleCount("unit_failure_tests", file, unitFailure, 2);
    validateUniqueCommands("unit_failure_tests", file, unitFailure);
    for (const cmd of unitFailure) validateCommand(cmd, "unit_failure_tests", file);

    const boundarySmoke = splitBundle(boundarySmokeRaw);
    ensureBundleCount("boundary_smoke_tests", file, boundarySmoke, 5);
    validateUniqueCommands("boundary_smoke_tests", file, boundarySmoke);
    for (const cmd of boundarySmoke) validateCommand(cmd, "boundary_smoke_tests", file);

    const depIds = [];
    for (const dep of splitCsv(dependsOnRaw)) {
      if (dep === scenarioId) {
        fail(`depends_on must not include self ('${scenarioId}') in scenario file: ${file}`);
      }
      if (!scenarioIdExists(dep)) {
        fail(`depends_on references unknown scenario id '${dep}' in scenario file: ${file}`);
      }
      depIds.push(dep);
    }

    const linkedIds = [];
    for (const linked of splitCsv(linkedNodesRaw)) {
      if (linked === scenarioId) {
        fail(`linked_nodes must not include self ('${scenarioId}') in scenario file: ${file}`);
      }
      if (!scenarioIdExists(linked)) {
        fail(`linked_nodes references unknown scenario id '${linked}' in scenario file: ${file}`);
      }
      linkedIds.push(linked);
    }

    if (linkedIds.length === 0) {
      fail(`linked_nodes must contain at least one scenario id in scenario file: ${file}`);
    }

    const redId = `${scenarioId}_red`;
    const implId = `${scenarioId}_impl`;
    const greenId = `${scenarioId}_green`;

    const redDeps = ["preflight", ...depIds.map((dep) => `${dep}_green`)];

    lines.push(`  - id: ${redId}`);
    lines.push("    type: tdd_red");
    lines.push(`    deps: "${yamlQuote(joinCsv(redDeps))}"`);
    lines.push(`    changed_paths: "${yamlQuote(changedPaths)}"`);
    lines.push(`    run: "${yamlQuote(redRun)}"`);
    lines.push(`    verify: "${yamlQuote(verifyCmd)}"`);

    lines.push(`  - id: ${implId}`);
    lines.push("    type: impl");
    lines.push(`    deps: "${redId}"`);
    lines.push(`    changed_paths: "${yamlQuote(changedPaths)}"`);
    lines.push(`    run: "${yamlQuote(implRun)}"`);
    lines.push(`    verify: "${yamlQuote(verifyCmd)}"`);

    const unitNodeIds = [];

    for (let i = 0; i < unitNormal.length; i += 1) {
      const idx = i + 1;
      const nodeId = `${scenarioId}_unit_normal_${idx}`;
      unitNodeIds.push(nodeId);
      lines.push(`  - id: ${nodeId}`);
      lines.push("    type: unit_normal");
      lines.push(`    deps: "${implId}"`);
      lines.push(`    changed_paths: "${yamlQuote(changedPaths)}"`);
      lines.push(`    run: "${yamlQuote(unitNormal[i])}"`);
      lines.push("    verify: \"true\"");
    }

    for (let i = 0; i < unitBoundary.length; i += 1) {
      const idx = i + 1;
      const nodeId = `${scenarioId}_unit_boundary_${idx}`;
      unitNodeIds.push(nodeId);
      lines.push(`  - id: ${nodeId}`);
      lines.push("    type: unit_boundary");
      lines.push(`    deps: "${implId}"`);
      lines.push(`    changed_paths: "${yamlQuote(changedPaths)}"`);
      lines.push(`    run: "${yamlQuote(unitBoundary[i])}"`);
      lines.push("    verify: \"true\"");
    }

    for (let i = 0; i < unitFailure.length; i += 1) {
      const idx = i + 1;
      const nodeId = `${scenarioId}_unit_failure_${idx}`;
      unitNodeIds.push(nodeId);
      lines.push(`  - id: ${nodeId}`);
      lines.push("    type: unit_failure");
      lines.push(`    deps: "${implId}"`);
      lines.push(`    changed_paths: "${yamlQuote(changedPaths)}"`);
      lines.push(`    run: "${yamlQuote(unitFailure[i])}"`);
      lines.push("    verify: \"true\"");
    }

    const greenDeps = [implId, ...unitNodeIds];
    lines.push(`  - id: ${greenId}`);
    lines.push("    type: tdd_green");
    lines.push(`    deps: "${yamlQuote(joinCsv(greenDeps))}"`);
    lines.push(`    changed_paths: "${yamlQuote(changedPaths)}"`);
    lines.push(`    run: "${yamlQuote(greenRun)}"`);
    lines.push(`    verify: "${yamlQuote(verifyCmd)}"`);

    const smokeDeps = [greenId, ...linkedIds.map((linked) => `${linked}_green`)];
    const smokeDepsCsv = joinCsv(smokeDeps);

    for (let i = 0; i < boundarySmoke.length; i += 1) {
      const idx = i + 1;
      const smokeId = `${scenarioId}_smoke_boundary_${idx}`;
      scenarioSmokeIds.push(smokeId);
      lines.push(`  - id: ${smokeId}`);
      lines.push("    type: smoke_boundary");
      lines.push(`    deps: "${yamlQuote(smokeDepsCsv)}"`);
      lines.push(`    changed_paths: "${yamlQuote(changedPaths)}"`);
      lines.push(`    run: "${yamlQuote(boundarySmoke[i])}"`);
      lines.push("    verify: \"true\"");
    }
  }

  lines.push("  - id: smoke_gate");
  lines.push("    type: smoke");
  lines.push(`    deps: "${yamlQuote(joinCsv(scenarioSmokeIds))}"`);
  lines.push("    changed_paths: \".sigee/dag/pipelines/**,.sigee/dag/scenarios/**\"");
  lines.push("    run: \"skills/tech-developer/scripts/test_smoke.sh\"");
  lines.push("    verify: \"true\"");

  lines.push("  - id: e2e_gate");
  lines.push("    type: e2e");
  lines.push("    deps: \"smoke_gate\"");
  lines.push("    changed_paths: \".sigee/dag/pipelines/**,.sigee/dag/scenarios/**\"");
  lines.push("    run: \"skills/tech-developer/scripts/test_e2e.sh\"");
  lines.push("    verify: \"true\"");

  const output = `${lines.join("\n")}\n`;

  if (args.dryRun) {
    process.stdout.write(output);
    return;
  }

  await mkdir(path.dirname(outFileAbs), { recursive: true });
  await writeFile(outFileAbs, output, "utf8");
  process.stdout.write(`Pipeline generated: ${outFileAbs}\n`);
}

main().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exit(1);
});
