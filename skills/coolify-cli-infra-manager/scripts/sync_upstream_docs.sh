#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REF_DIR="${SKILL_DIR}/references"
UPSTREAM_DIR="${REF_DIR}/upstream"

mkdir -p "${UPSTREAM_DIR}"

require_bin() {
  local bin="$1"
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "Missing required binary: ${bin}" >&2
    exit 1
  fi
}

require_bin curl
require_bin jq
require_bin awk
require_bin sed
require_bin rg

fetch() {
  local url="$1"
  local output="$2"

  echo "Fetching ${url}"
  curl -fsSL "${url}" -o "${output}"

  if [[ ! -s "${output}" ]]; then
    echo "Downloaded file is empty: ${output}" >&2
    exit 1
  fi
}

fetch "https://coolify.io/docs/llms.txt" "${UPSTREAM_DIR}/coolify-docs-llms.txt"
fetch "https://coolify.io/docs/llms-full.txt" "${UPSTREAM_DIR}/coolify-docs-llms-full.txt"
fetch "https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/authorization.md" "${UPSTREAM_DIR}/coolify-api-authorization.md"
fetch "https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/.vitepress/theme/openapi.json" "${UPSTREAM_DIR}/coolify-openapi.json"
fetch "https://raw.githubusercontent.com/coollabsio/coolify-cli/v4.x/README.md" "${UPSTREAM_DIR}/coolify-cli-readme.md"
fetch "https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/api/index.md" "${UPSTREAM_DIR}/coolify-api-index.md"
fetch "https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/api/operations/%5Boperation%5D.md" "${UPSTREAM_DIR}/coolify-api-operation-template.md"
fetch "https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/api/operations/%5Boperation%5D.paths.ts" "${UPSTREAM_DIR}/coolify-api-operation-paths.ts"

fetched_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

jq -n \
  --arg fetched_at "${fetched_at}" \
  '{
    fetched_at_utc: $fetched_at,
    sources: [
      {url: "https://coolify.io/docs/llms.txt", file: "coolify-docs-llms.txt"},
      {url: "https://coolify.io/docs/llms-full.txt", file: "coolify-docs-llms-full.txt"},
      {url: "https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/authorization.md", file: "coolify-api-authorization.md"},
      {url: "https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/.vitepress/theme/openapi.json", file: "coolify-openapi.json"},
      {url: "https://raw.githubusercontent.com/coollabsio/coolify-cli/v4.x/README.md", file: "coolify-cli-readme.md"},
      {url: "https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/api/index.md", file: "coolify-api-index.md"},
      {url: "https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/api/operations/%5Boperation%5D.md", file: "coolify-api-operation-template.md"},
      {url: "https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/api/operations/%5Boperation%5D.paths.ts", file: "coolify-api-operation-paths.ts"}
    ]
  }' > "${UPSTREAM_DIR}/sources.json"

jq -r '
  .paths
  | to_entries[]
  | .key as $path
  | .value
  | to_entries[]
  | [(.value.tags[0] // "Untagged"), (.key | ascii_upcase), $path, (.value.operationId // "-"), (.value.summary // "-")]
  | @tsv
' "${UPSTREAM_DIR}/coolify-openapi.json" \
  | sort -t$'\t' -k1,1 -k2,2 -k3,3 \
  > "${UPSTREAM_DIR}/coolify-api-operations.tsv"

{
  echo -e "tag\toperation_count"
  cut -f1 "${UPSTREAM_DIR}/coolify-api-operations.tsv" \
    | sort \
    | uniq -c \
    | sed -E 's/^[[:space:]]*([0-9]+)[[:space:]]+(.+)$/\2\t\1/'
} > "${UPSTREAM_DIR}/coolify-api-tags.tsv"

awk '
  /^## Currently Supported Commands/ { in_section=1; next }
  /^## Global Flags/ { in_section=0 }
  in_section && /^- `coolify/ { print }
' "${UPSTREAM_DIR}/coolify-cli-readme.md" > "${UPSTREAM_DIR}/coolify-cli-commands.txt"

awk '
  /^## Global Flags/ { in_section=1; next }
  /^## Examples/ { in_section=0 }
  in_section && /^- `--/ { print }
' "${UPSTREAM_DIR}/coolify-cli-readme.md" > "${UPSTREAM_DIR}/coolify-cli-global-flags.txt"

sed -E 's/^- `([^`]+)` - (.*)$/\1\t\2/' \
  "${UPSTREAM_DIR}/coolify-cli-commands.txt" > "${UPSTREAM_DIR}/coolify-cli-commands.tsv"

sed -E 's/^- `([^`]+)` - (.*)$/\1\t\2/' \
  "${UPSTREAM_DIR}/coolify-cli-global-flags.txt" > "${UPSTREAM_DIR}/coolify-cli-global-flags.tsv"

api_openapi_version="$(jq -r '.openapi' "${UPSTREAM_DIR}/coolify-openapi.json")"
api_title="$(jq -r '.info.title' "${UPSTREAM_DIR}/coolify-openapi.json")"
api_info_version="$(jq -r '.info.version' "${UPSTREAM_DIR}/coolify-openapi.json")"
api_path_count="$(jq '.paths | length' "${UPSTREAM_DIR}/coolify-openapi.json")"
api_operation_count="$(wc -l < "${UPSTREAM_DIR}/coolify-api-operations.tsv" | tr -d ' ')"

{
  echo "# Coolify API Reference (Snapshot)"
  echo
  echo "Generated from official Coolify docs and OpenAPI on ${fetched_at}."
  echo
  echo "## Spec Summary"
  echo
  echo "- Title: \`${api_title}\`"
  echo "- OpenAPI version: \`${api_openapi_version}\`"
  echo "- API info.version: \`${api_info_version}\`"
  echo "- Path count: \`${api_path_count}\`"
  echo "- Operation count: \`${api_operation_count}\`"
  echo
  echo "## Authentication and Base URL"
  echo
  echo "- Authorization header: \`Authorization: Bearer <token>\`"
  echo "- Base route: \`http://<ip>:8000/api\`"
  echo "- Versioned route: \`http://<ip>:8000/api/v1\` (except \`/health\` and \`/feedback\`)"
  echo "- Token scope: Team-scoped API token"
  echo "- Permission levels: \`read-only\`, \`read:sensitive\`, \`view:sensitive\`, \`*\`"
  echo
  echo "## Operations By Tag"
  echo
  echo "| Tag | Count |"
  echo "| --- | --- |"
  awk -F $'\t' 'NR > 1 { printf("| %s | %s |\n", $1, $2) }' "${UPSTREAM_DIR}/coolify-api-tags.tsv"
  echo
  echo "## Full Operation Index"
  echo
  echo "| Tag | Method | Path | Operation ID | Summary |"
  echo "| --- | --- | --- | --- | --- |"
  awk -F $'\t' '
    {
      summary=$5
      gsub(/\|/, "\\\\|", summary)
      printf("| %s | %s | `%s` | `%s` | %s |\n", $1, $2, $3, $4, summary)
    }
  ' "${UPSTREAM_DIR}/coolify-api-operations.tsv"
  echo
  echo "## Source Files"
  echo
  echo "- \`references/upstream/coolify-openapi.json\`"
  echo "- \`references/upstream/coolify-api-authorization.md\`"
  echo "- \`references/upstream/coolify-api-index.md\`"
  echo "- \`references/upstream/coolify-api-operation-template.md\`"
  echo "- \`references/upstream/coolify-api-operation-paths.ts\`"
} > "${REF_DIR}/api-reference.md"

cli_command_count="$(wc -l < "${UPSTREAM_DIR}/coolify-cli-commands.tsv" | tr -d ' ')"
cli_flag_count="$(wc -l < "${UPSTREAM_DIR}/coolify-cli-global-flags.tsv" | tr -d ' ')"

{
  echo "# Coolify CLI Reference (Snapshot)"
  echo
  echo "Generated from the official \`coollabsio/coolify-cli\` README on ${fetched_at}."
  echo
  echo "## Setup"
  echo
  echo "- Install script (Linux/macOS):"
  echo '  - `curl -fsSL https://raw.githubusercontent.com/coollabsio/coolify-cli/main/scripts/install.sh | bash`'
  echo "- Configure context (Cloud): \`coolify context set-token cloud <token>\`"
  echo "- Configure context (Self-hosted): \`coolify context add -d <context_name> <url> <token>\`"
  echo
  echo "## Scope"
  echo
  echo "- Parsed command entries: \`${cli_command_count}\`"
  echo "- Global flags: \`${cli_flag_count}\`"
  echo
  echo "## Command Index"
  echo
  echo "| Command | Description |"
  echo "| --- | --- |"
  awk -F $'\t' '{ printf("| `%s` | %s |\n", $1, $2) }' "${UPSTREAM_DIR}/coolify-cli-commands.tsv"
  echo
  echo "## Global Flags"
  echo
  echo "| Flag | Description |"
  echo "| --- | --- |"
  awk -F $'\t' '{ printf("| `%s` | %s |\n", $1, $2) }' "${UPSTREAM_DIR}/coolify-cli-global-flags.tsv"
  echo
  echo "## Source Files"
  echo
  echo "- \`references/upstream/coolify-cli-readme.md\`"
  echo "- \`references/upstream/coolify-cli-commands.tsv\`"
  echo "- \`references/upstream/coolify-cli-global-flags.tsv\`"
} > "${REF_DIR}/cli-reference.md"

{
  echo "# Coolify Source Manifest"
  echo
  echo "- Last synced (UTC): \`${fetched_at}\`"
  echo
  echo "## URLs"
  echo
  echo "- https://coolify.io/docs/llms.txt"
  echo "- https://coolify.io/docs/llms-full.txt"
  echo "- https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/authorization.md"
  echo "- https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/.vitepress/theme/openapi.json"
  echo "- https://raw.githubusercontent.com/coollabsio/coolify-cli/v4.x/README.md"
  echo "- https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/api/index.md"
  echo "- https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/api/operations/%5Boperation%5D.md"
  echo "- https://raw.githubusercontent.com/coollabsio/coolify-docs/v4.x/docs/api-reference/api/operations/%5Boperation%5D.paths.ts"
  echo
  echo "## Local Files"
  echo
  echo "- \`references/upstream/\` (raw snapshots + parsed TSVs + metadata)"
  echo "- \`references/api-reference.md\`"
  echo "- \`references/cli-reference.md\`"
} > "${REF_DIR}/sources.md"

echo "Sync complete. Updated references in ${REF_DIR}."
