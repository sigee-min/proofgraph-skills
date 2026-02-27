#!/usr/bin/env node

import { access, constants, readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { runCommandOrThrow } from "./command-runner.mjs";

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const options = {};
  for (let i = 0; i < rest.length; i += 1) {
    const key = rest[i];
    if (!key.startsWith("--")) {
      throw new Error(`Unknown option: ${key}`);
    }
    const name = key.slice(2);
    const value = rest[i + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`Missing value for --${name}`);
    }
    options[name] = value;
    i += 1;
  }
  return { command: command || "", options };
}

function isMeaningfulValue(raw) {
  const value = String(raw ?? "").trim().toLowerCase();
  return !["", "none", "n/a", "na", "-", "tbd", "todo"].includes(value);
}

function resolveEvidencePath(projectRoot, token) {
  const trimmed = String(token ?? "").trim();
  if (!trimmed) return "";
  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) return "";
  if (path.isAbsolute(trimmed)) return trimmed;
  return path.join(projectRoot, trimmed);
}

async function canRead(target) {
  try {
    await access(target, constants.R_OK);
    return true;
  } catch {
    return false;
  }
}

async function verifyResultsFilePass(resultsFile) {
  if (!(await canRead(resultsFile))) return false;
  const content = await readFile(resultsFile, "utf8");
  const lines = content.split(/\r?\n/).filter((line) => line.length > 0);
  let rows = 0;
  let pass = 0;
  let fail = 0;
  for (let i = 1; i < lines.length; i += 1) {
    const cols = lines[i].split("\t");
    rows += 1;
    if (cols[3] === "PASS") pass += 1;
    if (cols[3] === "FAIL") fail += 1;
  }
  return rows > 0 && pass > 0 && fail === 0;
}

async function verifyDagStatePass(stateFile) {
  if (!(await canRead(stateFile))) return false;
  try {
    const doc = JSON.parse(await readFile(stateFile, "utf8"));
    if (doc.status !== "PASS") return false;
    if (!doc.evidence_dir || typeof doc.evidence_dir !== "string") return false;
    const s = await stat(doc.evidence_dir);
    return s.isDirectory();
  } catch {
    return false;
  }
}

function validatePhaseTransition(fromPhase, toPhase, fromQueue, toQueue, toStatus) {
  if (fromPhase === toPhase) return;

  if (
    fromPhase === "evidence_collected" &&
    toPhase === "done" &&
    toQueue === "done" &&
    toStatus === "done"
  ) {
    return;
  }

  const allowed = new Set([
    "planned:ready",
    "planned:running",
    "ready:running",
    "running:evidence_collected",
    "running:ready",
    "evidence_collected:verified",
    "evidence_collected:ready",
    "verified:done",
    "verified:ready",
  ]);
  if (allowed.has(`${fromPhase}:${toPhase}`)) return;

  if (toQueue === "blocked") {
    if (["planned", "ready", "running", "evidence_collected", "verified"].includes(toPhase)) return;
  }

  if (fromQueue === "blocked" && toQueue !== "done") {
    if (["ready", "running"].includes(toPhase)) return;
  }

  throw new Error(
    `invalid lifecycle transition '${fromPhase}' -> '${toPhase}' for move ${fromQueue} -> ${toQueue} (status=${toStatus}).`,
  );
}

async function hasScenarioCatalog(scenarioDir) {
  try {
    const entries = await readdir(scenarioDir);
    return entries.some((name) => name.endsWith(".scenario.yml"));
  } catch {
    return false;
  }
}

async function validateDoneGate(options) {
  const projectRoot = path.resolve(options["project-root"] || ".");
  const ticketId = String(options["ticket-id"] || "");
  const evidenceLinks = String(options["evidence-links"] || "");
  const runtimeRoot = String(options["runtime-root"] || ".sigee/.runtime");
  const productTruthValidateScript = String(options["product-truth-validate-script"] || "");
  const goalGovValidateScript = String(options["goal-governance-validate-script"] || "");

  if (!isMeaningfulValue(evidenceLinks)) {
    throw new Error(`move to 'done' requires non-empty evidence links for ticket '${ticketId}'.`);
  }

  let hasGatePass = false;
  const tokens = evidenceLinks
    .split(/[;,|]/g)
    .map((token) => token.trim())
    .filter((token) => token.length > 0);

  for (const token of tokens) {
    const resolved = resolveEvidencePath(projectRoot, token);
    if (!resolved) continue;
    if (resolved.endsWith(".tsv") && (await verifyResultsFilePass(resolved))) {
      hasGatePass = true;
    }
    if (resolved.includes(`${path.sep}dag${path.sep}state${path.sep}`) && resolved.endsWith(".json")) {
      if (await verifyDagStatePass(resolved)) hasGatePass = true;
    }
  }

  if (!hasGatePass) {
    const fallbackState = path.join(projectRoot, runtimeRoot, "dag", "state", "last-run.json");
    if (await verifyDagStatePass(fallbackState)) hasGatePass = true;
  }

  if (!hasGatePass) {
    throw new Error(
      "move to 'done' requires passing verification evidence (PASS-only verification-results.tsv or PASS dag/state/last-run.json).",
    );
  }

  const sourceScenarioDir = path.join(projectRoot, ".sigee", "dag", "scenarios");
  const runtimeScenarioDir = path.join(projectRoot, runtimeRoot, "dag", "scenarios");
  const hasSourceCatalog = await hasScenarioCatalog(sourceScenarioDir);
  const hasRuntimeCatalog = await hasScenarioCatalog(runtimeScenarioDir);

  if (!hasSourceCatalog && hasRuntimeCatalog) {
    throw new Error(
      "runtime scenario catalog exists without source catalog (.sigee/dag/scenarios); restore source-of-truth scenarios before done transition.",
    );
  }

  if (hasSourceCatalog) {
    if (!productTruthValidateScript) {
      throw new Error("missing executable validator for done gate: product_truth_validate.sh");
    }
    if (!goalGovValidateScript) {
      throw new Error("missing executable goal-governance validator for done gate: goal_governance_validate.sh");
    }

    await runCommandOrThrow(productTruthValidateScript, [
      "--project-root",
      projectRoot,
      "--scenario-dir",
      sourceScenarioDir,
      "--require-scenarios",
    ]);
    await runCommandOrThrow(goalGovValidateScript, [
      "--project-root",
      projectRoot,
      "--scenario-dir",
      sourceScenarioDir,
      "--require-scenarios",
      "--strict",
    ]);
  }
}

async function main() {
  const { command, options } = parseArgs(process.argv.slice(2));
  if (!command) {
    throw new Error(
      "Usage: orchestration-queue.mjs <validate-phase-transition|validate-done-gate> [--key value ...]",
    );
  }

  if (command === "validate-phase-transition") {
    validatePhaseTransition(
      options["from-phase"] || "",
      options["to-phase"] || "",
      options["from-queue"] || "",
      options["to-queue"] || "",
      options["to-status"] || "",
    );
    return;
  }

  if (command === "validate-done-gate") {
    await validateDoneGate(options);
    return;
  }

  throw new Error(`Unknown command: ${command}`);
}

const isMainModule = (() => {
  if (!process.argv[1]) return false;
  const currentFile = fileURLToPath(import.meta.url);
  return path.resolve(process.argv[1]) === path.resolve(currentFile);
})();

if (isMainModule) {
  main().catch((error) => {
    process.stderr.write(`ERROR: ${error.message}\n`);
    process.exit(1);
  });
}
