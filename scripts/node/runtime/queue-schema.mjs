#!/usr/bin/env node

import path from "node:path";
import { loadTsv, saveTsv } from "./tsv-store.mjs";

const QUEUE_HEADER = [
  "id",
  "status",
  "worker",
  "title",
  "source",
  "updated_at",
  "note",
  "next_action",
  "lease",
  "evidence_links",
  "phase",
  "error_class",
  "attempt_count",
  "retry_budget",
];
const ARCHIVE_HEADER = [
  ...QUEUE_HEADER,
  "archived_at",
  "archived_by",
];
const RETRY_HEADER = [
  "ts_utc",
  "event_type",
  "id",
  "from_queue",
  "to_queue",
  "status",
  "error_class",
  "attempt_count",
  "retry_budget",
  "priority",
  "actor",
  "note",
];

function isNonNegativeInt(value) {
  return /^[0-9]+$/.test(String(value));
}

function normalizeQueuePhase(status, queueName) {
  if (status === "done") return "done";
  if (status === "review") return "evidence_collected";
  if (status === "in_progress") return "running";
  if (status === "blocked") return "running";
  if (status === "pending" && queueName === "planner-inbox") return "planned";
  if (status === "pending") return "ready";
  return "ready";
}

function normalizeQueueRows(rows, queueName) {
  return rows.map((row) => {
    const out = {};
    for (const key of QUEUE_HEADER) {
      out[key] = String(row[key] ?? "");
    }

    if (!out.phase) out.phase = normalizeQueuePhase(out.status, queueName);
    if (!out.error_class) out.error_class = out.status === "blocked" ? "soft_fail" : "none";
    if (!isNonNegativeInt(out.attempt_count)) out.attempt_count = "0";
    if (!isNonNegativeInt(out.retry_budget) || Number(out.retry_budget) < 1) out.retry_budget = "3";
    return out;
  });
}

function normalizeArchiveRows(rows) {
  return rows.map((row) => {
    const out = {};
    for (const key of ARCHIVE_HEADER) {
      out[key] = String(row[key] ?? "");
    }
    if (!out.phase) out.phase = normalizeQueuePhase(out.status, "unknown");
    if (!out.error_class) out.error_class = out.status === "blocked" ? "soft_fail" : "none";
    if (!isNonNegativeInt(out.attempt_count)) out.attempt_count = "0";
    if (!isNonNegativeInt(out.retry_budget) || Number(out.retry_budget) < 1) out.retry_budget = "3";
    return out;
  });
}

function normalizeRetryRows(rows) {
  return rows.map((row) => {
    const out = {};
    for (const key of RETRY_HEADER) {
      out[key] = String(row[key] ?? "");
    }
    if (!out.ts_utc) out.ts_utc = "1970-01-01T00:00:00Z";
    if (!out.event_type) out.event_type = "retry_event";
    if (!out.status) out.status = "blocked";
    if (!out.error_class) out.error_class = "dependency_blocked";
    if (!isNonNegativeInt(out.attempt_count)) out.attempt_count = "0";
    if (!isNonNegativeInt(out.retry_budget) || Number(out.retry_budget) < 1) out.retry_budget = "3";
    if (!out.priority) out.priority = "P2";
    if (!out.actor) out.actor = "planner";
    return out;
  });
}

async function normalizeFile(kind, filePath) {
  const parsed = await loadTsv(filePath);
  if (kind === "queue") {
    const queueName = path.basename(filePath, ".tsv");
    await saveTsv(filePath, QUEUE_HEADER, normalizeQueueRows(parsed.rows, queueName));
    return;
  }
  if (kind === "archive") {
    await saveTsv(filePath, ARCHIVE_HEADER, normalizeArchiveRows(parsed.rows));
    return;
  }
  if (kind === "retry-history") {
    await saveTsv(filePath, RETRY_HEADER, normalizeRetryRows(parsed.rows));
    return;
  }
  throw new Error(`Unsupported kind: ${kind}`);
}

function parseArgs(argv) {
  const out = {
    command: "",
    kind: "",
    file: "",
  };
  const [command, ...rest] = argv;
  out.command = command || "";
  for (let i = 0; i < rest.length; i += 1) {
    const token = rest[i];
    if (token === "--kind") {
      out.kind = rest[++i] || "";
      continue;
    }
    if (token === "--file") {
      out.file = rest[++i] || "";
      continue;
    }
    throw new Error(`Unknown option: ${token}`);
  }
  return out;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.command !== "normalize") {
    throw new Error("Usage: queue-schema.mjs normalize --kind <queue|archive|retry-history> --file <path>");
  }
  if (!args.kind || !args.file) {
    throw new Error("--kind and --file are required");
  }
  await normalizeFile(args.kind, path.resolve(args.file));
}

main().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exit(1);
});
