#!/usr/bin/env node

import { mkdir, readdir, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import readline from "node:readline";
import { fileURLToPath } from "node:url";
import { syncDirectory } from "./runtime/fs-sync.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PACK_ROOT = path.resolve(__dirname, "..", "..");
const SKILL_ROOT = path.join(PACK_ROOT, "skills");

function usage() {
  return `Usage:
  skillpack-cli.mjs <command> [options]

Commands:
  deploy [--skill <name>] [--all] [--target <path>] [--dry-run]
  install [--skill <name>] [--all] [--target <path>] [--dry-run] [--yes] [--platform-hint <name>]

Options:
  --skill <name>         Deploy/install one skill (repeatable)
  --all                  Deploy/install all skills (default)
  --target <path>        Override install target path (default: $CODEX_HOME/skills or ~/.codex/skills)
  --dry-run              Show planned actions without writing files
  --yes                  Skip interactive confirmation for install
  --platform-hint <name> Optional display hint (for wrapper scripts)
  --help                 Show this message
`;
}

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const options = {
    skills: [],
    all: false,
    target: "",
    dryRun: false,
    yes: false,
    platformHint: "",
    help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "--skill":
        if (!argv[i + 1]) {
          fail("--skill requires a value");
        }
        options.skills.push(argv[i + 1]);
        i += 1;
        break;
      case "--all":
        options.all = true;
        break;
      case "--target":
        if (!argv[i + 1]) {
          fail("--target requires a value");
        }
        options.target = argv[i + 1];
        i += 1;
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--yes":
        options.yes = true;
        break;
      case "--platform-hint":
        if (!argv[i + 1]) {
          fail("--platform-hint requires a value");
        }
        options.platformHint = argv[i + 1].toLowerCase();
        i += 1;
        break;
      case "--help":
        options.help = true;
        break;
      default:
        fail(`Unknown option: ${arg}`);
    }
  }

  return options;
}

function checkNodeVersion() {
  const major = Number.parseInt(process.versions.node.split(".")[0], 10);
  if (!Number.isFinite(major) || major < 20) {
    fail(`Node.js 20+ is required (current: ${process.versions.node}).`);
  }
}

async function pathExists(targetPath) {
  try {
    await stat(targetPath);
    return true;
  } catch {
    return false;
  }
}

function resolveTargetRoot(requestedTarget) {
  if (requestedTarget && requestedTarget.trim()) {
    return path.resolve(requestedTarget.trim());
  }
  if (process.env.CODEX_HOME && process.env.CODEX_HOME.trim()) {
    return path.join(process.env.CODEX_HOME.trim(), "skills");
  }
  return path.join(os.homedir(), ".codex", "skills");
}

async function listAvailableSkills() {
  const entries = await readdir(SKILL_ROOT, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b));
}

async function resolveSkillSelection(options) {
  const availableSkills = await listAvailableSkills();
  if (availableSkills.length === 0) {
    fail(`No skills found under ${SKILL_ROOT}`);
  }

  const selected = options.skills.length > 0
    ? Array.from(new Set(options.skills))
    : availableSkills;

  for (const skill of selected) {
    if (!availableSkills.includes(skill)) {
      fail(`Skill not found: ${skill}`);
    }
  }
  return selected;
}

async function runDeploy(options) {
  checkNodeVersion();
  const targetRoot = resolveTargetRoot(options.target);
  const selectedSkills = await resolveSkillSelection(options);

  if (!options.dryRun) {
    await mkdir(targetRoot, { recursive: true });
  }

  for (const skill of selectedSkills) {
    const sourceDir = path.join(SKILL_ROOT, skill);
    const destinationDir = path.join(targetRoot, skill);
    await syncDirectory(sourceDir, destinationDir, {
      dryRun: options.dryRun,
      deleteTarget: true,
      logger: (line) => process.stdout.write(`${line}\n`),
    });
    if (!options.dryRun) {
      process.stdout.write(`Deployed: ${skill} -> ${destinationDir}\n`);
    }
  }

  process.stdout.write(`\nDeployment complete. Target: ${targetRoot}\n`);
  return { targetRoot, selectedSkills };
}

async function askConfirmation(promptText) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    fail("Install requires interactive terminal or --yes.");
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const answer = await new Promise((resolve) => {
    rl.question(promptText, (value) => resolve(value));
  });
  rl.close();

  return /^(y|yes)$/i.test(String(answer).trim());
}

async function runInstall(options) {
  checkNodeVersion();
  const targetRoot = resolveTargetRoot(options.target);

  process.stdout.write(`Install root: ${PACK_ROOT}\n`);
  process.stdout.write(`Target path: ${targetRoot}\n`);

  if (!options.dryRun && !options.yes) {
    const confirmed = await askConfirmation("Proceed with installation on this machine? [y/N] ");
    if (!confirmed) {
      process.stdout.write("Installation cancelled.\n");
      return;
    }
  }

  const result = await runDeploy(options);

  if (options.dryRun) {
    process.stdout.write("\nDry-run completed.\n");
    return;
  }

  process.stdout.write(`\nInstalled skills under: ${result.targetRoot}\n`);
  for (const skill of result.selectedSkills) {
    process.stdout.write(`- ${skill}\n`);
  }

  const platform = options.platformHint || process.platform;
  if (platform === "windows" || platform === "win32") {
    process.stdout.write("\nRuntime note:\n");
    process.stdout.write(
      "Current Windows support is Tier 1: install/deploy is native, while runtime workflows require a WSL2-compatible shell path.\n",
    );
  }
}

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  if (!command || command === "--help" || command === "-h") {
    process.stdout.write(usage());
    process.exit(0);
  }

  const options = parseArgs(rest);
  if (options.help) {
    process.stdout.write(usage());
    process.exit(0);
  }

  if (!(await pathExists(SKILL_ROOT))) {
    fail(`Skill root not found: ${SKILL_ROOT}`);
  }

  if (command === "deploy") {
    await runDeploy(options);
    return;
  }
  if (command === "install") {
    await runInstall(options);
    return;
  }

  fail(`Unknown command: ${command}`);
}

main().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exit(1);
});
