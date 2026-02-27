#!/usr/bin/env node

import { access, copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { runCommand, runCommandOrThrow } from "./command-runner.mjs";
import { sanitizeField } from "./tsv-store.mjs";

function usage() {
  return `Usage:
  plan_run.sh <plan-file> [--mode strict] [--resume] [--write-report]
`;
}

function fail(message) {
  throw new Error(message);
}

function trim(value) {
  return String(value ?? "").trim();
}

function nowStamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

function normalizePath(value) {
  return String(value ?? "").split(path.sep).join("/");
}

function requireSafeRuntimeRoot(runtimeRoot) {
  if (
    !runtimeRoot ||
    runtimeRoot === "." ||
    runtimeRoot === ".." ||
    runtimeRoot.startsWith("/") ||
    runtimeRoot.includes("..")
  ) {
    fail("SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)");
  }
}

function parseArgs(argv) {
  if (argv.length < 1) {
    fail(usage().trim());
  }
  const args = {
    planFile: argv[0],
    mode: "strict",
    writeReport: false,
    resume: false,
  };
  for (let i = 1; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--no-report") {
      args.writeReport = false;
      continue;
    }
    if (token === "--mode") {
      const value = argv[i + 1];
      if (!value) fail("Missing value for --mode");
      args.mode = value;
      i += 1;
      continue;
    }
    if (token === "--write-report") {
      args.writeReport = true;
      continue;
    }
    if (token === "--resume") {
      args.resume = true;
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

async function fileExists(filePath) {
  try {
    await access(filePath, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function ensureExecutable(filePath, label) {
  if (!(await fileExists(filePath))) {
    fail(`Missing executable ${label}: ${filePath}`);
  }
  try {
    await access(filePath, constants.X_OK);
  } catch {
    fail(`Missing executable ${label}: ${filePath}`);
  }
}

async function resolveRepoRoot(projectRoot) {
  const result = await runCommand("git", ["-C", projectRoot, "rev-parse", "--show-toplevel"], {
    allowNonZero: true,
  });
  if (result.code === 0) {
    return trim(result.stdout);
  }
  return projectRoot;
}

function extractPlanId(planText, planFile) {
  const match = planText.match(/^id:[ \t]*([a-zA-Z0-9._-]+)[ \t]*$/m);
  if (match?.[1]) return match[1];
  return path.basename(planFile, ".md");
}

function parseUncheckedTasks(planText) {
  const lines = planText.split(/\r?\n/);
  const tasks = [];
  for (let i = 0; i < lines.length; i += 1) {
    if (/^- \[ \]/.test(lines[i])) {
      const title = lines[i].replace(/^- \[ \][ \t]*/, "");
      tasks.push({ lineNo: i + 1, title });
    }
  }
  return { lines, tasks };
}

function extractFieldCommand(block, field) {
  const escaped = field.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`^[ \\t]*- ${escaped}[ \\t]*\`(.*)\`[ \\t]*$`, "m");
  const match = block.match(re);
  return match?.[1] ?? "";
}

async function markTaskDone(planFile, lineNo) {
  const text = await readFile(planFile, "utf8");
  const lines = text.split(/\r?\n/);
  const idx = lineNo - 1;
  if (idx < 0 || idx >= lines.length) {
    fail(`mark_task_done target line out of range: ${lineNo}`);
  }
  lines[idx] = lines[idx].replace(/^- \[ \]/, "- [x]");
  await writeFile(planFile, `${lines.join("\n")}\n`, "utf8");
}

async function appendResultsRow(resultsFile, fields) {
  const row = fields.map((value) => sanitizeField(value)).join("\t");
  await writeFile(resultsFile, `${row}\n`, { encoding: "utf8", flag: "a" });
}

async function runCommandWithLog(commandText, repoRoot, logPath) {
  const result = await runCommand("bash", ["-lc", commandText], {
    cwd: repoRoot,
    allowNonZero: true,
  });
  const body = `+ ${commandText}\n${result.stdout}${result.stderr}`;
  await writeFile(logPath, body, "utf8");
  return result.code;
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0) {
    process.stderr.write(usage());
    process.exit(1);
  }
  if (argv[0] === "--help" || argv[0] === "-h") {
    process.stdout.write(usage());
    process.exit(0);
  }

  const args = parseArgs(argv);
  const runtimeRoot = process.env.SIGEE_RUNTIME_ROOT || ".sigee/.runtime";
  requireSafeRuntimeRoot(runtimeRoot);

  if (args.mode !== "strict") {
    fail("--mode must be 'strict' (hard TDD enforcement)");
  }

  const absPlan = path.resolve(args.planFile);
  if (!(await fileExists(absPlan))) {
    fail(`Plan file not found: ${args.planFile}`);
  }

  const normalizedPlan = normalizePath(absPlan);
  const runtimeNorm = normalizePath(runtimeRoot);
  const marker = `/${runtimeNorm}/plans/`;
  if (!normalizedPlan.includes(marker) || !normalizedPlan.endsWith(".md")) {
    fail(`Plan path must be under ${runtimeRoot}/plans and end with .md`);
  }

  let projectRoot = normalizedPlan.split(marker)[0];
  if (!projectRoot || projectRoot === normalizedPlan) {
    projectRoot = path.resolve(path.dirname(absPlan), "../..");
  }
  projectRoot = path.normalize(projectRoot);
  const repoRoot = await resolveRepoRoot(projectRoot);

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const plannerDir = path.resolve(scriptDir, "../../../skills/tech-planner/scripts");
  const developerDir = path.resolve(scriptDir, "../../../skills/tech-developer/scripts");
  const gitignoreGuardScript = path.join(plannerDir, "sigee_gitignore_guard.sh");
  const plannerEntryGuardScript = path.join(plannerDir, "planner_entry_guard.sh");
  const reportScript = path.join(developerDir, "report_generate.sh");

  await ensureExecutable(gitignoreGuardScript, "gitignore guard");
  await ensureExecutable(plannerEntryGuardScript, "planner entry guard");
  if (args.writeReport) {
    await ensureExecutable(reportScript, "report generator");
  }

  const planText = await readFile(absPlan, "utf8");
  const planId = extractPlanId(planText, absPlan);
  const evidenceDir = path.join(projectRoot, runtimeRoot, "evidence", planId);
  const resultsFile = path.join(evidenceDir, "verification-results.tsv");
  await mkdir(evidenceDir, { recursive: true });

  await runCommandOrThrow("bash", [gitignoreGuardScript, projectRoot], {
    cwd: repoRoot,
    env: { ...process.env, SIGEE_RUNTIME_ROOT: runtimeRoot },
  });
  await runCommandOrThrow(
    "bash",
    [plannerEntryGuardScript, "--project-root", projectRoot, "--worker", "tech-developer", "--plan-file", absPlan],
    {
      cwd: repoRoot,
      env: { ...process.env, SIGEE_RUNTIME_ROOT: runtimeRoot },
    },
  );

  let prevTitle = "";
  if (args.resume && (await fileExists(resultsFile))) {
    const prev = await readFile(resultsFile, "utf8");
    const rows = prev.split(/\r?\n/).filter((line) => line.length > 0);
    for (let i = 1; i < rows.length; i += 1) {
      const cols = rows[i].split("\t");
      if (cols[3] === "FAIL") {
        prevTitle = cols[1] ?? "";
      }
    }
    if (prevTitle) {
      process.stdout.write(`Resume context detected from previous run:\n`);
      process.stdout.write(`- task: ${prevTitle}\n`);
    } else {
      process.stdout.write("Resume requested, but no previous FAIL record was found.\n");
    }
    const archiveResults = path.join(evidenceDir, `verification-results-${nowStamp()}.tsv`);
    await copyFile(resultsFile, archiveResults);
    process.stdout.write(`Archived previous verification results: ${archiveResults}\n`);
  }

  await writeFile(resultsFile, "task_no\ttitle\tkind\tstatus\tlog_path\tcommand\n", "utf8");

  const { lines, tasks } = parseUncheckedTasks(planText);
  if (tasks.length === 0) {
    process.stdout.write(`No unchecked tasks found: ${absPlan}\n`);
    return;
  }

  let startTaskIndex = 0;
  if (args.resume && prevTitle) {
    for (let i = 0; i < tasks.length; i += 1) {
      if (tasks[i].title === prevTitle) {
        startTaskIndex = i;
        break;
      }
    }
    if (startTaskIndex > 0) {
      process.stdout.write(`Resuming from task index ${startTaskIndex + 1}/${tasks.length}: ${prevTitle}\n`);
    }
  }

  for (let i = startTaskIndex; i < tasks.length; i += 1) {
    const taskIndex = i - startTaskIndex + 1;
    const displayIndex = i + 1;
    const lineNo = tasks[i].lineNo;
    const title = tasks[i].title;
    const taskSlugRaw = title.replace(/[^A-Za-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
    const taskSlug = (taskSlugRaw || `task_${taskIndex}`).slice(0, 48);

    const endLineExclusive = i < tasks.length - 1 ? tasks[i + 1].lineNo - 1 : lines.length;
    const block = lines.slice(lineNo, endLineExclusive).join("\n");
    const executeCommand = extractFieldCommand(block, "Execute:");
    const verifyCommand = extractFieldCommand(block, "Verification:");

    if (!executeCommand) fail(`Task '${title}' has no Execute command in hard TDD mode.`);
    if (!verifyCommand) fail(`Task '${title}' has no Verification command in hard TDD mode.`);
    if (executeCommand === "true" || executeCommand === ":") {
      fail(`Task '${title}' has no-op Execute command ('${executeCommand}') in hard TDD mode.`);
    }
    if (verifyCommand === "true" || verifyCommand === ":") {
      fail(`Task '${title}' has no-op Verification command ('${verifyCommand}') in hard TDD mode.`);
    }

    process.stdout.write(`[${displayIndex}/${tasks.length}] ${title}\n`);

    const executeLog = path.join(evidenceDir, `${taskIndex}-${taskSlug}-execute.log`);
    const executeCode = await runCommandWithLog(executeCommand, repoRoot, executeLog);
    if (executeCode === 0) {
      await appendResultsRow(resultsFile, [taskIndex, title, "execute", "PASS", executeLog, executeCommand]);
    } else {
      await appendResultsRow(resultsFile, [taskIndex, title, "execute", "FAIL", executeLog, executeCommand]);
      fail(`FAILED: Execute command for task '${title}'. See: ${executeLog}`);
    }

    const verifyLog = path.join(evidenceDir, `${taskIndex}-${taskSlug}-verify.log`);
    const verifyCode = await runCommandWithLog(verifyCommand, repoRoot, verifyLog);
    if (verifyCode === 0) {
      await appendResultsRow(resultsFile, [taskIndex, title, "verify", "PASS", verifyLog, verifyCommand]);
      await markTaskDone(absPlan, lineNo);
    } else {
      await appendResultsRow(resultsFile, [taskIndex, title, "verify", "FAIL", verifyLog, verifyCommand]);
      fail(`FAILED: Verification command for task '${title}'. See: ${verifyLog}`);
    }
  }

  if (args.writeReport) {
    await runCommandOrThrow("bash", [reportScript, absPlan], {
      cwd: repoRoot,
      env: { ...process.env, SIGEE_RUNTIME_ROOT: runtimeRoot },
    });
  }
}

main().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exit(1);
});

