#!/usr/bin/env node

import { access, constants, mkdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { runCommand } from "./command-runner.mjs";
import { loadTsv } from "./tsv-store.mjs";

function usage() {
  return `Usage:
  orchestration_autoloop.sh [--project-root <path>] [--max-cycles <n>] [--no-progress-limit <n>]
`;
}

function fail(message) {
  throw new Error(message);
}

function trim(value) {
  return String(value ?? "").trim();
}

function nowStampUtc() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
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
  const args = {
    projectRoot: "",
    maxCycles: 30,
    noProgressLimit: 2,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--project-root") {
      const value = argv[i + 1];
      if (!value) fail("Missing value for --project-root");
      args.projectRoot = value;
      i += 1;
      continue;
    }
    if (token === "--max-cycles") {
      const value = Number(argv[i + 1]);
      if (!Number.isInteger(value) || value < 1) fail("--max-cycles must be integer >= 1");
      args.maxCycles = value;
      i += 1;
      continue;
    }
    if (token === "--no-progress-limit") {
      const value = Number(argv[i + 1]);
      if (!Number.isInteger(value) || value < 1) fail("--no-progress-limit must be integer >= 1");
      args.noProgressLimit = value;
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

async function fileExists(target) {
  try {
    await access(target, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function ensureExecutable(target, label) {
  if (!(await fileExists(target))) {
    fail(`missing executable ${label}: ${target}`);
  }
  try {
    await access(target, constants.X_OK);
  } catch {
    fail(`missing executable ${label}: ${target}`);
  }
}

async function resolveProjectRoot(candidate) {
  const base = path.resolve(candidate || process.cwd());
  let info;
  try {
    info = await stat(base);
  } catch {
    fail(`project root not found: ${candidate}`);
  }
  if (!info.isDirectory()) {
    fail(`project root not found: ${candidate}`);
  }
  const git = await runCommand("git", ["-C", base, "rev-parse", "--show-toplevel"], { allowNonZero: true });
  if (git.code === 0) {
    return trim(git.stdout);
  }
  return base;
}

function queuePath(projectRoot, runtimeRoot, queueName) {
  return path.join(projectRoot, runtimeRoot, "orchestration", "queues", `${queueName}.tsv`);
}

function appendUniqueCsvValue(csv, value) {
  const normalized = trim(value);
  if (!normalized) return csv;
  if (!csv) return normalized;
  const parts = csv.split(",").map((part) => trim(part));
  if (parts.includes(normalized)) return csv;
  return `${csv},${normalized}`;
}

async function runQueue({ queueScript, projectRoot, runtimeRoot, args, allowNonZero = false }) {
  return await runCommand("bash", [queueScript, ...args, "--project-root", projectRoot], {
    cwd: projectRoot,
    env: { ...process.env, SIGEE_RUNTIME_ROOT: runtimeRoot },
    allowNonZero,
  });
}

async function runQueueOrThrow(context) {
  const result = await runQueue(context);
  if (result.code !== 0) {
    const detail = trim(`${result.stderr}\n${result.stdout}`) || "queue command failed";
    fail(detail);
  }
  return result;
}

function parseLoopStatus(output) {
  for (const line of output.split(/\r?\n/)) {
    if (line.startsWith("LOOP_STATUS:")) {
      return trim(line.slice("LOOP_STATUS:".length));
    }
  }
  return "";
}

async function firstRowByPredicate(queueFile, predicateFn) {
  if (!(await fileExists(queueFile))) return null;
  const { rows } = await loadTsv(queueFile);
  for (const row of rows) {
    if (predicateFn(row)) return row;
  }
  return null;
}

async function hasNonPlanPendingInbox(projectRoot, runtimeRoot) {
  const inboxFile = queuePath(projectRoot, runtimeRoot, "planner-inbox");
  const { rows } = await loadTsv(inboxFile);
  return rows.some((row) => row.status === "pending" && !String(row.source ?? "").startsWith("plan:"));
}

async function promoteOnePlanFromInbox(context) {
  const inboxFile = queuePath(context.projectRoot, context.runtimeRoot, "planner-inbox");
  const row = await firstRowByPredicate(inboxFile, (r) => r.status === "pending" && String(r.source ?? "").startsWith("plan:"));
  if (!row) return false;

  await runQueueOrThrow({
    ...context,
    args: [
      "move",
      "--id",
      row.id,
      "--from",
      "planner-inbox",
      "--to",
      "developer-todo",
      "--status",
      "pending",
      "--worker",
      "tech-developer",
      "--error-class",
      "none",
      "--note",
      "autoloop route: plan-backed inbox item promoted to developer queue",
      "--next-action",
      "execute plan in strict mode and return to planner-review",
      "--actor",
      "tech-planner",
    ],
  });

  return true;
}

function parseClaimedRow(output) {
  const lines = output.split(/\r?\n/);
  for (const line of lines) {
    if (line.includes("\t")) {
      const cols = line.split("\t");
      if (cols.length >= 14) {
        return {
          id: cols[0] ?? "",
          status: cols[1] ?? "",
          worker: cols[2] ?? "",
          title: cols[3] ?? "",
          source: cols[4] ?? "",
          updated_at: cols[5] ?? "",
          note: cols[6] ?? "",
          next_action: cols[7] ?? "",
          lease: cols[8] ?? "",
          evidence_links: cols[9] ?? "",
          phase: cols[10] ?? "",
          error_class: cols[11] ?? "",
          attempt_count: cols[12] ?? "",
          retry_budget: cols[13] ?? "",
        };
      }
    }
  }
  return null;
}

async function claimOneDeveloperTicket(context) {
  const result = await runQueue({
    ...context,
    args: ["claim", "--queue", "developer-todo", "--worker", "tech-developer", "--actor", "tech-developer"],
    allowNonZero: true,
  });
  if (result.code !== 0) {
    const detail = trim(`${result.stderr}\n${result.stdout}`) || "claim failed";
    fail(detail);
  }
  if (result.stdout.includes("NO_PENDING:developer-todo") || result.stdout.includes("NO_RETRY_BUDGET:developer-todo")) {
    return null;
  }
  return parseClaimedRow(result.stdout);
}

async function runPlanStrict({ projectRoot, runtimeRoot, planRunnerNodeScript, fallbackPlanRunScript, planFile }) {
  if (await fileExists(planRunnerNodeScript)) {
    return await runCommand("node", [planRunnerNodeScript, planFile, "--mode", "strict"], {
      cwd: projectRoot,
      env: { ...process.env, SIGEE_RUNTIME_ROOT: runtimeRoot },
      allowNonZero: true,
    });
  }
  return await runCommand("bash", [fallbackPlanRunScript, planFile, "--mode", "strict"], {
    cwd: projectRoot,
    env: { ...process.env, SIGEE_RUNTIME_ROOT: runtimeRoot },
    allowNonZero: true,
  });
}

async function executeOneDeveloperTicket(context) {
  const row = await claimOneDeveloperTicket(context);
  if (!row) return false;

  const id = row.id;
  const source = row.source;

  if (!source.startsWith("plan:")) {
    await runQueueOrThrow({
      ...context,
      args: [
        "move",
        "--id",
        id,
        "--from",
        "developer-todo",
        "--to",
        "blocked",
        "--status",
        "blocked",
        "--worker",
        "tech-developer",
        "--error-class",
        "dependency_blocked",
        "--note",
        "autoloop blocked: developer ticket is not plan-backed source",
        "--next-action",
        "planner triage required: convert to plan-backed execution or reroute",
        "--actor",
        "tech-planner",
      ],
    });
    process.stdout.write(`AUTOLOOP_BLOCKED:${id}:non-plan-source\n`);
    return true;
  }

  const planId = source.slice("plan:".length);
  const planFile = path.join(context.projectRoot, context.runtimeRoot, "plans", `${planId}.md`);
  if (!(await fileExists(planFile))) {
    await runQueueOrThrow({
      ...context,
      args: [
        "move",
        "--id",
        id,
        "--from",
        "developer-todo",
        "--to",
        "blocked",
        "--status",
        "blocked",
        "--worker",
        "tech-developer",
        "--error-class",
        "dependency_blocked",
        "--note",
        `autoloop blocked: plan file not found for source '${source}'`,
        "--next-action",
        "planner triage required: restore plan file or reroute task",
        "--actor",
        "tech-planner",
      ],
    });
    process.stdout.write(`AUTOLOOP_BLOCKED:${id}:missing-plan-file\n`);
    return true;
  }

  const historyDir = path.join(context.projectRoot, context.runtimeRoot, "orchestration", "history");
  await mkdir(historyDir, { recursive: true });
  const runLog = path.join(historyDir, `autoloop-developer-${id}-${nowStampUtc()}.log`);

  const runResult = await runPlanStrict({
    projectRoot: context.projectRoot,
    runtimeRoot: context.runtimeRoot,
    planRunnerNodeScript: context.planRunnerNodeScript,
    fallbackPlanRunScript: context.fallbackPlanRunScript,
    planFile,
  });
  await writeFile(runLog, `${runResult.stdout}${runResult.stderr}`, "utf8");

  let evidenceLinks = "";
  evidenceLinks = appendUniqueCsvValue(evidenceLinks, `${context.runtimeRoot}/evidence/${planId}/verification-results.tsv`);
  const dagState = path.join(context.projectRoot, context.runtimeRoot, "dag", "state", "last-run.json");
  if (await fileExists(dagState)) {
    evidenceLinks = appendUniqueCsvValue(evidenceLinks, `${context.runtimeRoot}/dag/state/last-run.json`);
  }
  evidenceLinks = appendUniqueCsvValue(evidenceLinks, runLog);

  if (runResult.code === 0) {
    await runQueueOrThrow({
      ...context,
      args: [
        "move",
        "--id",
        id,
        "--from",
        "developer-todo",
        "--to",
        "planner-review",
        "--status",
        "review",
        "--worker",
        "tech-developer",
        "--phase",
        "evidence_collected",
        "--error-class",
        "none",
        "--note",
        "autoloop execute pass: strict plan_run completed",
        "--next-action",
        "planner review: approve done or request rework",
        "--evidence",
        evidenceLinks,
        "--actor",
        "tech-developer",
      ],
    });
    process.stdout.write(`AUTOLOOP_EXECUTE_PASS:${id}:${planId}\n`);
    return true;
  }

  await runQueueOrThrow({
    ...context,
    args: [
      "move",
      "--id",
      id,
      "--from",
      "developer-todo",
      "--to",
      "blocked",
      "--status",
      "blocked",
      "--worker",
      "tech-developer",
      "--error-class",
      "hard_fail",
      "--note",
      "autoloop execute fail: strict plan_run failed (see log)",
      "--next-action",
      "planner triage required: fix failing plan commands/tests or scope down",
      "--evidence",
      evidenceLinks,
      "--actor",
      "tech-planner",
    ],
  });
  process.stdout.write(`AUTOLOOP_EXECUTE_FAIL:${id}:${planId}\n`);
  return true;
}

async function reviewOneTicket(context) {
  const reviewFile = queuePath(context.projectRoot, context.runtimeRoot, "planner-review");
  const row = await firstRowByPredicate(reviewFile, (r) => r.status === "review");
  if (!row) return false;

  const id = row.id;
  const evidence = row.evidence_links ?? "";
  const doneResult = await runQueue({
    ...context,
    args: [
      "move",
      "--id",
      id,
      "--from",
      "planner-review",
      "--to",
      "done",
      "--status",
      "done",
      "--worker",
      "tech-planner",
      "--actor",
      "tech-planner",
      "--evidence",
      evidence,
    ],
    allowNonZero: true,
  });

  if (doneResult.code === 0) {
    process.stdout.write(`AUTOLOOP_REVIEW_PASS:${id}\n`);
    return true;
  }

  const merged = `${doneResult.stdout}\n${doneResult.stderr}`.replace(/\s+/g, " ").trim().slice(0, 300);
  await runQueueOrThrow({
    ...context,
    args: [
      "move",
      "--id",
      id,
      "--from",
      "planner-review",
      "--to",
      "developer-todo",
      "--status",
      "pending",
      "--worker",
      "tech-developer",
      "--error-class",
      "soft_fail",
      "--note",
      `autoloop review reject: ${merged}`,
      "--next-action",
      "rework implementation and return to planner-review with passing evidence",
      "--actor",
      "tech-planner",
    ],
  });
  process.stdout.write(`AUTOLOOP_REVIEW_REQUEUE:${id}\n`);
  return true;
}

async function main() {
  const runtimeRoot = process.env.SIGEE_RUNTIME_ROOT || ".sigee/.runtime";
  requireSafeRuntimeRoot(runtimeRoot);
  const args = parseArgs(process.argv.slice(2));
  const projectRoot = await resolveProjectRoot(args.projectRoot);

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const queueScript =
    process.env.SIGEE_ORCH_QUEUE_SCRIPT ||
    path.resolve(scriptDir, "../../../skills/tech-planner/scripts/orchestration_queue.sh");
  const fallbackPlanRunScript =
    process.env.SIGEE_PLAN_RUN_SCRIPT ||
    path.resolve(scriptDir, "../../../skills/tech-developer/scripts/plan_run.sh");
  const planRunnerNodeScript =
    process.env.SIGEE_PLAN_RUNNER_NODE_SCRIPT || path.resolve(scriptDir, "./plan-runner.mjs");

  await ensureExecutable(queueScript, "queue helper");
  await ensureExecutable(fallbackPlanRunScript, "developer runner");

  const context = {
    queueScript,
    fallbackPlanRunScript,
    planRunnerNodeScript,
    projectRoot,
    runtimeRoot,
  };

  await runQueueOrThrow({ ...context, args: ["init"] });

  let cycle = 0;
  let noProgress = 0;
  let terminalStatus = "";

  while (cycle < args.maxCycles) {
    cycle += 1;
    let progress = false;
    process.stdout.write(`AUTOLOOP_CYCLE:${cycle}\n`);

    while (await promoteOnePlanFromInbox(context)) {
      progress = true;
    }

    while (await reviewOneTicket(context)) {
      progress = true;
    }

    if (await executeOneDeveloperTicket(context)) {
      progress = true;
      while (await reviewOneTicket(context)) {
        progress = true;
      }
    }

    const loopStatusResult = await runQueueOrThrow({ ...context, args: ["loop-status"] });
    const loopStatus = parseLoopStatus(loopStatusResult.stdout);
    if (loopStatus === "STOP_DONE" || loopStatus === "STOP_USER_CONFIRMATION") {
      terminalStatus = loopStatus;
      break;
    }

    if (await hasNonPlanPendingInbox(projectRoot, runtimeRoot)) {
      terminalStatus = "STOP_USER_CONFIRMATION";
      break;
    }

    if (progress) {
      noProgress = 0;
    } else {
      noProgress += 1;
    }
    if (noProgress >= args.noProgressLimit) {
      terminalStatus = "STOP_NO_PROGRESS";
      break;
    }
  }

  if (!terminalStatus) {
    if (cycle >= args.maxCycles) {
      terminalStatus = "STOP_MAX_CYCLES";
    } else {
      const loopStatusResult = await runQueueOrThrow({ ...context, args: ["loop-status"] });
      terminalStatus = parseLoopStatus(loopStatusResult.stdout);
    }
  }

  process.stdout.write(`AUTOLOOP_TERMINAL_STATUS:${terminalStatus}\n`);
  process.stdout.write(`AUTOLOOP_TOTAL_CYCLES:${cycle}\n`);
  process.stdout.write(`AUTOLOOP_NO_PROGRESS_COUNT:${noProgress}\n`);

  const nextPrompt = await runQueueOrThrow({ ...context, args: ["next-prompt", "--user-facing"] });
  process.stdout.write(nextPrompt.stdout);
}

main().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exit(1);
});
