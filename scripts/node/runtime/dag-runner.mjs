#!/usr/bin/env node

import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { runCommand, runCommandOrThrow } from "./command-runner.mjs";

function usage() {
  return `Usage:
  dag-runner.mjs <pipeline-file> [--dry-run] [--changed-only] [--changed-file <path>] [--include-global-gates] [--only <node-id>]
`;
}

function fail(message) {
  throw new Error(message);
}

function nowUtcIso() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function localRunId() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

function jsonEscape(value) {
  return String(value ?? "")
    .replaceAll("\\", "\\\\")
    .replaceAll("\"", "\\\"")
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\r")
    .replaceAll("\t", "\\t");
}

function trim(value) {
  return String(value ?? "").trim();
}

function unquote(value) {
  let out = String(value ?? "");
  if (out.length >= 2 && ((out.startsWith("\"") && out.endsWith("\"")) || (out.startsWith("'") && out.endsWith("'")))) {
    out = out.slice(1, -1);
  }
  return out.replaceAll("\\\"", "\"");
}

function parseArgs(argv) {
  const args = {
    pipelineFile: "",
    dryRun: false,
    changedOnly: false,
    includeGlobalGates: false,
    onlyNode: "",
    changedFiles: [],
  };
  if (argv.length < 1) {
    return args;
  }
  args.pipelineFile = argv[0] || "";
  for (let i = 1; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--dry-run") {
      args.dryRun = true;
      continue;
    }
    if (token === "--changed-only") {
      args.changedOnly = true;
      continue;
    }
    if (token === "--include-global-gates") {
      args.includeGlobalGates = true;
      continue;
    }
    if (token === "--only") {
      const value = argv[i + 1];
      if (!value) fail("--only requires a value");
      args.onlyNode = value;
      i += 1;
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

function requireSafeRuntimeRoot(runtimeRoot) {
  if (!runtimeRoot || runtimeRoot === "." || runtimeRoot === ".." || runtimeRoot.startsWith("/") || runtimeRoot.includes("..")) {
    fail("SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)");
  }
}

async function fileExists(filePath) {
  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}

function parsePipeline(text) {
  const lines = text.split(/\r?\n/);
  let pipelineId = "";
  const nodes = [];
  let current = null;

  function flushNode() {
    if (!current) return;
    if (!current.run || !current.verify) {
      fail(`node '${current.id}' missing run or verify`);
    }
    if (!current.changed_paths) {
      current.changed_paths = "*";
    }
    current.type = current.type || "";
    current.deps = current.deps || "";
    nodes.push(current);
    current = null;
  }

  for (const line of lines) {
    const pipelineMatch = line.match(/^pipeline_id:\s*([A-Za-z0-9._-]+)\s*$/);
    if (pipelineMatch) {
      pipelineId = pipelineMatch[1];
    }
    const nodeStart = line.match(/^\s*-\s*id:\s*(.*)$/);
    if (nodeStart) {
      flushNode();
      current = {
        id: unquote(trim(nodeStart[1])),
      };
      continue;
    }
    const fieldMatch = line.match(/^\s+([a-z_]+):\s*(.*)$/);
    if (current && fieldMatch) {
      const key = fieldMatch[1];
      const val = unquote(trim(fieldMatch[2]));
      if (["type", "deps", "changed_paths", "run", "verify"].includes(key)) {
        current[key] = val;
      }
    }
  }
  flushNode();

  if (!pipelineId) {
    pipelineId = "default";
  }
  if (nodes.length === 0) {
    fail("no nodes parsed from pipeline");
  }
  return { pipelineId, nodes };
}

function splitCsv(raw) {
  return String(raw ?? "")
    .split(",")
    .map((value) => trim(value))
    .filter((value) => value.length > 0);
}

function globToRegExp(pattern) {
  let out = "^";
  for (let i = 0; i < pattern.length; i += 1) {
    const ch = pattern[i];
    if (ch === "*") {
      out += ".*";
    } else if (ch === "?") {
      out += ".";
    } else {
      out += ch.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
    }
  }
  out += "$";
  return new RegExp(out);
}

function matchChanged(patternCsv, filePath) {
  const patterns = splitCsv(patternCsv);
  for (const pattern of patterns) {
    if (pattern === "*") {
      return true;
    }
    if (globToRegExp(pattern).test(filePath)) {
      return true;
    }
  }
  return false;
}

function indexById(nodes) {
  const idx = new Map();
  for (let i = 0; i < nodes.length; i += 1) {
    idx.set(nodes[i].id, i);
  }
  return idx;
}

function isGlobalGate(node) {
  return (node.type === "smoke" && node.id === "smoke_gate") || (node.type === "e2e" && node.id === "e2e_gate");
}

async function repoRootFrom(projectRoot) {
  const result = await runCommand("git", ["-C", projectRoot, "rev-parse", "--show-toplevel"], {
    allowNonZero: true,
  });
  if (result.code === 0) {
    return trim(result.stdout);
  }
  return projectRoot;
}

async function changedFilesFromGit(repoRoot) {
  const result = await runCommand("git", ["-C", repoRoot, "status", "--porcelain"], {
    allowNonZero: true,
  });
  if (result.code !== 0) {
    return [];
  }
  return result.stdout
    .split(/\r?\n/)
    .map((line) => line.slice(3))
    .map((line) => trim(line))
    .filter((line) => line.length > 0);
}

async function verifyRuntimeDagIntegrity({ pipelineId, projectRoot, runtimeRoot }) {
  if (pipelineId.startsWith("synthetic-")) {
    return;
  }
  const scenarioDir = path.join(projectRoot, runtimeRoot, "dag", "scenarios");
  if (!(await fileExists(scenarioDir))) {
    return;
  }
  const entries = await readdir(scenarioDir);
  const scenarioCount = entries.filter((entry) => entry.endsWith(".scenario.yml")).length;
  if (scenarioCount === 0) {
    return;
  }

  const sourceDir = path.join(projectRoot, ".sigee", "dag", "scenarios");
  const dagCompileScript = path.join(projectRoot, "skills", "tech-developer", "scripts", "dag_compile.sh");
  if (!(await fileExists(dagCompileScript))) {
    fail(`dag compile verifier not found: ${dagCompileScript}`);
  }
  if (!(await fileExists(sourceDir))) {
    fail(`UX DAG source directory missing: ${sourceDir}`);
  }

  await runCommandOrThrow("bash", [
    dagCompileScript,
    "--project-root",
    projectRoot,
    "--source",
    sourceDir,
    "--out",
    scenarioDir,
    "--check-only",
  ], {
    cwd: projectRoot,
  });
}

async function runNodeCommand(command, cwd, logFile) {
  const result = await runCommand("bash", ["-lc", command], {
    cwd,
    allowNonZero: true,
  });
  const body = `+ ${command}\n${result.stdout}${result.stderr}`;
  await writeFile(logFile, body, "utf8");
  return result.code;
}

async function main() {
  const rawArgv = process.argv.slice(2);
  if (rawArgv.length === 0) {
    process.stderr.write(usage());
    process.exit(1);
  }
  if (rawArgv[0] === "--help" || rawArgv[0] === "-h") {
    process.stdout.write(usage());
    process.exit(0);
  }

  const args = parseArgs(rawArgv);
  const runtimeRoot = process.env.SIGEE_RUNTIME_ROOT || ".sigee/.runtime";
  requireSafeRuntimeRoot(runtimeRoot);
  if (!(await fileExists(args.pipelineFile))) {
    fail(`pipeline file not found: ${args.pipelineFile}`);
  }

  const absPipeline = path.resolve(args.pipelineFile);
  const normalizedPipeline = absPipeline.split(path.sep).join("/");
  const runtimeRootNorm = runtimeRoot.split(path.sep).join("/");
  const markerNorm = `/${runtimeRootNorm}/dag/pipelines/`;
  if (!normalizedPipeline.includes(markerNorm) || !normalizedPipeline.endsWith(".yml")) {
    fail(`pipeline path must be under ${runtimeRoot}/dag/pipelines and end with .yml`);
  }

  let projectRoot = normalizedPipeline.split(markerNorm)[0];
  if (!projectRoot || projectRoot === normalizedPipeline) {
    projectRoot = path.resolve(path.dirname(absPipeline), "../../..");
  }
  projectRoot = path.normalize(projectRoot);
  const repoRoot = await repoRootFrom(projectRoot);

  const evidenceRoot = path.join(projectRoot, runtimeRoot, "evidence", "dag");
  const stateFile = path.join(projectRoot, runtimeRoot, "dag", "state", "last-run.json");
  await mkdir(evidenceRoot, { recursive: true });
  await mkdir(path.dirname(stateFile), { recursive: true });

  const startEpochSeconds = Math.floor(Date.now() / 1000);
  const pipelineText = await readFile(absPipeline, "utf8");
  const { pipelineId, nodes } = parsePipeline(pipelineText);
  await verifyRuntimeDagIntegrity({ pipelineId, projectRoot, runtimeRoot });

  const idxById = indexById(nodes);
  for (const node of nodes) {
    for (const dep of splitCsv(node.deps)) {
      if (!idxById.has(dep)) {
        fail(`node '${node.id}' references unknown dep '${dep}'`);
      }
    }
  }

  const selected = Array.from({ length: nodes.length }).map(() => 0);

  if (args.onlyNode) {
    if (!idxById.has(args.onlyNode)) {
      fail(`--only node not found: ${args.onlyNode}`);
    }
    selected[idxById.get(args.onlyNode)] = 1;
  } else if (args.changedOnly) {
    let changedFiles = args.changedFiles.slice();
    if (changedFiles.length === 0) {
      changedFiles = await changedFilesFromGit(repoRoot);
    }
    if (changedFiles.length === 0) {
      process.stdout.write("No changed files detected. --changed-only exits without execution.\n");
      process.exit(0);
    }
    for (let i = 0; i < nodes.length; i += 1) {
      if (changedFiles.some((filePath) => matchChanged(nodes[i].changed_paths, filePath))) {
        selected[i] = 1;
      }
    }
  } else {
    for (let i = 0; i < nodes.length; i += 1) {
      selected[i] = 1;
    }
  }

  let changed = true;
  while (changed) {
    changed = false;
    for (let i = 0; i < nodes.length; i += 1) {
      if (selected[i] === 1) continue;
      const deps = splitCsv(nodes[i].deps);
      for (const dep of deps) {
        const depIdx = idxById.get(dep);
        if (depIdx === undefined) continue;
        if (selected[depIdx] === 1) {
          if (args.changedOnly && !args.includeGlobalGates && isGlobalGate(nodes[i])) {
            continue;
          }
          selected[i] = 1;
          changed = true;
          break;
        }
      }
    }
  }

  changed = true;
  while (changed) {
    changed = false;
    for (let i = 0; i < nodes.length; i += 1) {
      if (selected[i] === 0) continue;
      for (const dep of splitCsv(nodes[i].deps)) {
        const depIdx = idxById.get(dep);
        if (depIdx === undefined) continue;
        if (selected[depIdx] === 0) {
          selected[depIdx] = 1;
          changed = true;
        }
      }
    }
  }

  const selectedCount = selected.reduce((acc, value) => acc + (value === 1 ? 1 : 0), 0);
  if (selectedCount === 0) {
    process.stdout.write("No nodes selected for execution.\n");
    process.exit(0);
  }

  const indegree = Array.from({ length: nodes.length }).map(() => 0);
  const processed = Array.from({ length: nodes.length }).map(() => 0);
  for (let i = 0; i < nodes.length; i += 1) {
    if (selected[i] === 0) continue;
    for (const dep of splitCsv(nodes[i].deps)) {
      const depIdx = idxById.get(dep);
      if (depIdx === undefined || selected[depIdx] === 0) continue;
      indegree[i] += 1;
    }
  }

  const runId = localRunId();
  const runDir = path.join(evidenceRoot, `${pipelineId}-${runId}`);
  await mkdir(runDir, { recursive: true });
  const runSummaryFile = path.join(runDir, "run-summary.json");
  const traceFile = path.join(runDir, "trace.jsonl");
  const mermaidFile = path.join(runDir, "dag.mmd");

  const order = [];
  let status = "PASS";
  let failedNode = "";
  let failedStage = "";
  let failedDeps = "";

  async function traceEvent(event, node = "", stage = "", result = "", message = "") {
    const line = `{"ts":"${nowUtcIso()}","event":"${jsonEscape(event)}","node":"${jsonEscape(node)}","stage":"${jsonEscape(stage)}","result":"${jsonEscape(result)}","message":"${jsonEscape(message)}"}\n`;
    await writeFile(traceFile, line, { encoding: "utf8", flag: "a" });
  }

  await traceEvent("run_start", "", "pipeline", "info", `pipeline=${pipelineId} dry_run=${args.dryRun ? 1 : 0} changed_only=${args.changedOnly ? 1 : 0} only_node=${args.onlyNode}`);

  let processedCount = 0;
  outer: while (processedCount < selectedCount) {
    let progress = false;

    for (let i = 0; i < nodes.length; i += 1) {
      if (selected[i] === 0 || processed[i] === 1 || indegree[i] !== 0) {
        continue;
      }

      progress = true;
      processed[i] = 1;
      processedCount += 1;

      const node = nodes[i];
      order.push(node.id);

      if (args.dryRun) {
        process.stdout.write(`[DRY-RUN] node=${node.id} type=${node.type} deps=${node.deps}\n`);
        process.stdout.write(`  run: ${node.run}\n`);
        process.stdout.write(`  verify: ${node.verify}\n`);
        await traceEvent("node_dry_run", node.id, "dry_run", "pass", `deps=${node.deps}`);
      } else {
        const runLog = path.join(runDir, `${node.id}-run.log`);
        const verifyLog = path.join(runDir, `${node.id}-verify.log`);

        process.stdout.write(`Running node: ${node.id} (${node.type})\n`);
        await traceEvent("node_start", node.id, "run", "info", `deps=${node.deps}`);

        const runCode = await runNodeCommand(node.run, repoRoot, runLog);
        if (runCode !== 0) {
          status = "FAIL";
          failedNode = node.id;
          failedStage = "run";
          failedDeps = node.deps;
          await traceEvent("node_fail", node.id, "run", "fail", `log=${runLog}`);
          process.stdout.write(`FAILED NODE: ${node.id}\n`);
          process.stdout.write(`Dependency context: deps=${node.deps}\n`);
          process.stdout.write(`Rerun command: skills/tech-developer/scripts/dag_run.sh ${args.pipelineFile} --only ${node.id}\n`);
          break outer;
        }
        await traceEvent("node_pass", node.id, "run", "pass", `log=${runLog}`);

        const verifyCode = await runNodeCommand(node.verify, repoRoot, verifyLog);
        if (verifyCode !== 0) {
          status = "FAIL";
          failedNode = node.id;
          failedStage = "verify";
          failedDeps = node.deps;
          await traceEvent("node_fail", node.id, "verify", "fail", `log=${verifyLog}`);
          process.stdout.write(`FAILED NODE: ${node.id}\n`);
          process.stdout.write(`Dependency context: deps=${node.deps}\n`);
          process.stdout.write(`Rerun command: skills/tech-developer/scripts/dag_run.sh ${args.pipelineFile} --only ${node.id}\n`);
          break outer;
        }
        await traceEvent("node_pass", node.id, "verify", "pass", `log=${verifyLog}`);
      }

      for (let j = 0; j < nodes.length; j += 1) {
        if (selected[j] === 0 || processed[j] === 1) continue;
        if (splitCsv(nodes[j].deps).includes(node.id)) {
          indegree[j] -= 1;
        }
      }
    }

    if (status === "FAIL") {
      break;
    }
    if (!progress) {
      status = "FAIL";
      failedNode = "cycle_or_unresolved";
      failedStage = "topology";
      failedDeps = "unresolved indegree";
      await traceEvent("run_fail", "cycle_or_unresolved", "topology", "fail", "cycle or unresolved dependency in selected subgraph");
      process.stderr.write("ERROR: cycle or unresolved dependency in selected subgraph\n");
      break;
    }
  }

  const mermaidLines = ["graph TD"];
  for (let i = 0; i < nodes.length; i += 1) {
    if (selected[i] === 0) continue;
    const label = `${nodes[i].id} (${nodes[i].type})`.replaceAll("\"", "\\\"");
    mermaidLines.push(`  n${i}["${label}"]`);
  }
  for (let i = 0; i < nodes.length; i += 1) {
    if (selected[i] === 0) continue;
    for (const dep of splitCsv(nodes[i].deps)) {
      const depIdx = idxById.get(dep);
      if (depIdx === undefined || selected[depIdx] === 0) continue;
      mermaidLines.push(`  n${depIdx} --> n${i}`);
    }
  }
  await writeFile(mermaidFile, `${mermaidLines.join("\n")}\n`, "utf8");

  const endEpochSeconds = Math.floor(Date.now() / 1000);
  const durationSeconds = endEpochSeconds - startEpochSeconds;
  await traceEvent("run_end", "", "pipeline", status, `duration_seconds=${durationSeconds} selected=${selectedCount} processed=${processedCount}`);

  const runSummary = {
    pipeline_id: pipelineId,
    run_id: runId,
    status,
    start_epoch_seconds: startEpochSeconds,
    end_epoch_seconds: endEpochSeconds,
    duration_seconds: durationSeconds,
    dry_run: args.dryRun ? 1 : 0,
    changed_only: args.changedOnly ? 1 : 0,
    only_node: args.onlyNode,
    selected_node_count: selectedCount,
    processed_node_count: processedCount,
    failed_node: failedNode,
    failed_stage: failedStage,
    failed_deps: failedDeps,
    trace_file: traceFile,
    mermaid_file: mermaidFile,
  };
  await writeFile(runSummaryFile, `${JSON.stringify(runSummary, null, 2)}\n`, "utf8");

  const state = {
    pipeline_id: pipelineId,
    pipeline_file: args.pipelineFile,
    status,
    dry_run: args.dryRun ? 1 : 0,
    changed_only: args.changedOnly ? 1 : 0,
    only_node: args.onlyNode,
    failed_node: failedNode,
    failed_stage: failedStage,
    failed_deps: failedDeps,
    run_id: runId,
    run_summary_file: runSummaryFile,
    trace_file: traceFile,
    mermaid_file: mermaidFile,
    duration_seconds: durationSeconds,
    selected_node_count: selectedCount,
    processed_node_count: processedCount,
    evidence_dir: runDir,
    execution_order: order,
  };
  await writeFile(stateFile, `${JSON.stringify(state, null, 2)}\n`, "utf8");

  if (status === "FAIL") {
    process.exit(1);
  }

  process.stdout.write(`DAG run completed: pipeline=${pipelineId} status=${status}\n`);
  process.stdout.write(`State file: ${stateFile}\n`);
  process.stdout.write(`Run summary: ${runSummaryFile}\n`);
  if (!args.dryRun) {
    process.stdout.write(`Evidence dir: ${runDir}\n`);
  }
  process.stdout.write(`Trace file: ${traceFile}\n`);
  process.stdout.write(`Mermaid DAG: ${mermaidFile}\n`);
}

main().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exit(1);
});
