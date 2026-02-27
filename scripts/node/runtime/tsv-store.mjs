#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

export function sanitizeField(value) {
  return String(value ?? "").replace(/[\t\r\n]/g, " ");
}

export function parseTsv(text) {
  const lines = text
    .split(/\r?\n/)
    .filter((line) => line.length > 0);
  if (lines.length === 0) {
    return { header: [], rows: [] };
  }

  const header = lines[0].split("\t");
  const rows = lines.slice(1).map((line) => {
    const cols = line.split("\t");
    while (cols.length < header.length) {
      cols.push("");
    }
    const row = {};
    for (let i = 0; i < header.length; i += 1) {
      row[header[i]] = cols[i] ?? "";
    }
    return row;
  });
  return { header, rows };
}

export function serializeTsv(header, rows) {
  const lines = [];
  lines.push(header.map((key) => sanitizeField(key)).join("\t"));
  for (const row of rows) {
    lines.push(header.map((key) => sanitizeField(row[key] ?? "")).join("\t"));
  }
  return `${lines.join("\n")}\n`;
}

export async function loadTsv(filePath) {
  const content = await readFile(filePath, "utf8");
  return parseTsv(content);
}

export async function saveTsv(filePath, header, rows) {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, serializeTsv(header, rows), "utf8");
}
