#!/usr/bin/env node

import { cp, mkdir, rm, stat } from "node:fs/promises";

export async function pathExists(targetPath) {
  try {
    await stat(targetPath);
    return true;
  } catch {
    return false;
  }
}

export async function ensureDir(dirPath) {
  await mkdir(dirPath, { recursive: true });
}

export async function syncDirectory(sourceDir, destinationDir, options = {}) {
  const {
    dryRun = false,
    deleteTarget = true,
    logger = (line) => process.stdout.write(`${line}\n`),
  } = options;

  if (dryRun) {
    logger(`DRY-RUN: sync "${sourceDir}/" -> "${destinationDir}/"`);
    return;
  }

  if (deleteTarget && (await pathExists(destinationDir))) {
    await rm(destinationDir, { recursive: true, force: true });
  }
  await mkdir(destinationDir, { recursive: true });
  await cp(sourceDir, destinationDir, { recursive: true, force: true });
}
