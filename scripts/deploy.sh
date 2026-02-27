#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_SCRIPT="$SCRIPT_DIR/node/skillpack-cli.mjs"
NODE_BIN="${NODE_BIN:-node}"

if ! command -v "$NODE_BIN" >/dev/null 2>&1; then
  echo "ERROR: Node.js is required. Install Node.js 20+ and retry." >&2
  exit 1
fi

exec "$NODE_BIN" "$CLI_SCRIPT" deploy "$@"
