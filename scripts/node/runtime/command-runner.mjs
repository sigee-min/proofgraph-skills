#!/usr/bin/env node

import { spawn } from "node:child_process";

export async function runCommand(command, args = [], options = {}) {
  const {
    cwd = process.cwd(),
    env = process.env,
    input = "",
    allowNonZero = false,
    shell = false,
  } = options;

  return await new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env,
      shell,
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    child.on("error", reject);
    child.on("close", (code) => {
      const result = { code: code ?? 1, stdout, stderr };
      if (!allowNonZero && result.code !== 0) {
        const message = stderr.trim() || stdout.trim() || `Command failed: ${command}`;
        const err = new Error(message);
        err.result = result;
        reject(err);
        return;
      }
      resolve(result);
    });

    if (input) {
      child.stdin.write(input);
    }
    child.stdin.end();
  });
}

export async function runCommandOrThrow(command, args = [], options = {}) {
  return await runCommand(command, args, { ...options, allowNonZero: false });
}
