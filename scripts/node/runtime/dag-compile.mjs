#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { runCommand } from "./command-runner.mjs";

function usage() {
  return `Usage:
  dag-compile.mjs [--project-root <path>] [--source <ux-scenario-dir>] [--out <runtime-scenario-dir>] [--check-only]

Examples:
  SIGEE_RUNTIME_ROOT=.sigee/.runtime node scripts/node/runtime/dag-compile.mjs
  SIGEE_RUNTIME_ROOT=.sigee/.runtime node scripts/node/runtime/dag-compile.mjs --source .sigee/dag/scenarios --out .sigee/.runtime/dag/scenarios
  SIGEE_RUNTIME_ROOT=.sigee/.runtime node scripts/node/runtime/dag-compile.mjs --check-only
`;
}

function fail(message) {
  throw new Error(message);
}

function trim(value) {
  return String(value ?? "").trim();
}

function utcIsoNoMs() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function posixPath(value) {
  return value.split(path.sep).join("/");
}

function toRepoRel(abs, projectRoot) {
  const normalized = path.resolve(abs);
  const normalizedRoot = path.resolve(projectRoot);
  if (normalized === normalizedRoot) {
    return ".";
  }
  if (normalized.startsWith(`${normalizedRoot}${path.sep}`)) {
    return posixPath(normalized.slice(normalizedRoot.length + 1));
  }
  return posixPath(normalized);
}

async function pathExists(targetPath) {
  try {
    await stat(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function sha256Of(filePath) {
  const data = await readFile(filePath);
  return createHash("sha256").update(data).digest("hex");
}

async function resolveProjectRoot(explicitRoot) {
  if (explicitRoot) {
    return path.resolve(explicitRoot);
  }
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

function extractScenarioId(content) {
  const match = content.match(/(?:^|\n)id:\s*"?([A-Za-z0-9._-]+)"?\s*(?:\n|$)/m);
  return match ? trim(match[1]) : "";
}

function parseArgs(argv) {
  const args = {
    projectRoot: "",
    sourceDir: ".sigee/dag/scenarios",
    outDir: "",
    checkOnly: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--project-root") {
      const value = argv[i + 1];
      if (!value) fail("--project-root requires a value");
      args.projectRoot = value;
      i += 1;
      continue;
    }
    if (token === "--source") {
      const value = argv[i + 1];
      if (!value) fail("--source requires a value");
      args.sourceDir = value;
      i += 1;
      continue;
    }
    if (token === "--out") {
      const value = argv[i + 1];
      if (!value) fail("--out requires a value");
      args.outDir = value;
      i += 1;
      continue;
    }
    if (token === "--check-only") {
      args.checkOnly = true;
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

async function runCheck(projectRoot, sourceDirAbs, outDirAbs, manifestFile) {
  if (!(await pathExists(manifestFile))) {
    fail(`compiled manifest not found: ${manifestFile}`);
  }

  const outEntries = await readdir(outDirAbs, { withFileTypes: true });
  const runtimeCount = outEntries.filter((entry) => entry.isFile() && entry.name.endsWith(".scenario.yml")).length;

  const manifestContent = await readFile(manifestFile, "utf8");
  const lines = manifestContent.split(/\r?\n/);

  let rowCount = 0;
  for (const line of lines) {
    if (!line) continue;
    const cols = line.split("\t");
    const [id, sourceRel, sourceSha, runtimeRel, runtimeSha] = cols;
    if (id === "id") {
      continue;
    }
    if (!id) {
      continue;
    }
    rowCount += 1;

    const sourcePath = path.join(projectRoot, sourceRel);
    const runtimePath = path.join(projectRoot, runtimeRel);

    if (!(await pathExists(sourcePath))) {
      fail(`source scenario missing for compiled row '${id}': ${sourcePath}`);
    }
    if (!(await pathExists(runtimePath))) {
      fail(`runtime scenario missing for compiled row '${id}': ${runtimePath}`);
    }

    const sourceActual = await sha256Of(sourcePath);
    const runtimeActual = await sha256Of(runtimePath);

    if (sourceActual !== sourceSha) {
      fail(`source scenario changed after compile for '${id}'. Rebuild DAG pipeline first.`);
    }
    if (runtimeActual !== runtimeSha) {
      fail(`runtime scenario drift detected for '${id}' (manual edit suspected): ${runtimePath}`);
    }

    const runtimeContent = await readFile(runtimePath, "utf8");
    const header = runtimeContent.split(/\r?\n/, 1)[0] ?? "";
    if (header !== `# GENERATED_FROM: ${sourceRel}`) {
      fail(`generated header mismatch for '${id}': ${runtimePath}`);
    }
  }

  if (rowCount !== runtimeCount) {
    fail(`compiled manifest/runtime file count mismatch (manifest=${rowCount} runtime=${runtimeCount})`);
  }

  process.stdout.write(`DAG compile check passed: source=${sourceDirAbs} runtime=${outDirAbs} files=${rowCount}\n`);
}

async function main() {
  const runtimeRoot = process.env.SIGEE_RUNTIME_ROOT || ".sigee/.runtime";
  if (!runtimeRoot || runtimeRoot === "." || runtimeRoot === ".." || runtimeRoot.startsWith("/") || runtimeRoot.includes("..")) {
    fail("SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)");
  }

  const args = parseArgs(process.argv.slice(2));
  const projectRoot = await resolveProjectRoot(args.projectRoot);
  const sourceDirAbs = resolvePath(projectRoot, args.sourceDir);
  const outDirAbs = resolvePath(projectRoot, args.outDir || `${runtimeRoot}/dag/scenarios`);
  const manifestFile = path.join(outDirAbs, ".compiled-manifest.tsv");

  if (args.checkOnly) {
    await runCheck(projectRoot, sourceDirAbs, outDirAbs, manifestFile);
    return;
  }

  if (!(await pathExists(sourceDirAbs))) {
    fail(`source scenario directory not found: ${sourceDirAbs}`);
  }

  const sourceEntries = await readdir(sourceDirAbs, { withFileTypes: true });
  const scenarioFiles = sourceEntries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".scenario.yml"))
    .map((entry) => path.join(sourceDirAbs, entry.name))
    .sort((a, b) => a.localeCompare(b));

  if (scenarioFiles.length === 0) {
    fail(`no source scenarios found in ${sourceDirAbs}`);
  }

  await mkdir(outDirAbs, { recursive: true });

  const outEntries = await readdir(outDirAbs, { withFileTypes: true });
  for (const entry of outEntries) {
    if (entry.isFile() && entry.name.endsWith(".scenario.yml")) {
      await rm(path.join(outDirAbs, entry.name), { force: true });
    }
  }

  const seen = new Set();
  const manifestLines = ["id\tsource_rel\tsource_sha256\truntime_rel\truntime_sha256\tcompiled_at"];

  for (const sourceFile of scenarioFiles) {
    const sourceContent = await readFile(sourceFile, "utf8");
    const scenarioId = extractScenarioId(sourceContent);

    if (!scenarioId) {
      fail(`missing scenario id in source file: ${sourceFile}`);
    }
    if (seen.has(scenarioId)) {
      fail(`duplicate scenario id in source catalog: ${scenarioId}`);
    }
    seen.add(scenarioId);

    const sourceRel = toRepoRel(sourceFile, projectRoot);
    const sourceSha = await sha256Of(sourceFile);
    const runtimeFile = path.join(outDirAbs, `${scenarioId}.scenario.yml`);
    const runtimeRel = toRepoRel(runtimeFile, projectRoot);
    const compiledAt = utcIsoNoMs();

    const generated = [
      `# GENERATED_FROM: ${sourceRel}`,
      `# SOURCE_SHA256: ${sourceSha}`,
      `# GENERATED_AT: ${compiledAt}`,
      sourceContent,
    ].join("\n");

    await writeFile(runtimeFile, generated, "utf8");

    const runtimeSha = await sha256Of(runtimeFile);
    manifestLines.push(`${scenarioId}\t${sourceRel}\t${sourceSha}\t${runtimeRel}\t${runtimeSha}\t${compiledAt}`);
  }

  await writeFile(manifestFile, `${manifestLines.join("\n")}\n`, "utf8");

  await runCheck(projectRoot, sourceDirAbs, outDirAbs, manifestFile);
  process.stdout.write(`DAG scenarios compiled: source=${sourceDirAbs} runtime=${outDirAbs}\n`);
}

main().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exit(1);
});
