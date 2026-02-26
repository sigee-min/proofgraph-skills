---
name: coolify-cli-infra-manager
description: Manage Coolify infrastructure with the official `coolify` CLI plus synced API/CLI documentation snapshots. Use when tasks involve provisioning, updating, validating, deploying, or deleting Coolify resources (contexts, servers, projects, applications, databases, services, environment variables, deployments, private keys, GitHub apps), or when command and endpoint lookup is required.
---

# Coolify CLI Infra Manager

## Overview
Use this skill to operate Coolify infrastructure with reproducible documentation snapshots from official sources.
Prefer the `coolify` CLI for supported operations, and use API references when CLI coverage is missing or request/response schema details are needed.

## Workflow
1. Sync docs at least once (and again when freshness matters).
2. Confirm target context and auth.
3. Discover resources in read-only mode.
4. Execute scoped changes.
5. Verify state after each change.
6. Report exact commands and endpoints used.

### 1) Sync references
Run:

```bash
scripts/sync_upstream_docs.sh
```

The script updates:
- `references/upstream/*` raw snapshots (llms docs, OpenAPI, CLI README)
- `references/api-reference.md`
- `references/cli-reference.md`
- `references/sources.md`

### 2) Load only the references you need
- CLI syntax and command coverage: `references/cli-reference.md`
- API auth and endpoint index: `references/api-reference.md`
- Full OpenAPI schema: `references/upstream/coolify-openapi.json`
- Full Coolify docs snapshot: `references/upstream/coolify-docs-llms-full.txt`
- Source provenance and sync timestamp: `references/sources.md`

## Safety Rules
- Verify context before mutation:

```bash
coolify context list
coolify context verify
coolify context version
```

- Run `list` or `get` before `create`, `update`, `delete`, `start`, `stop`, or deploy commands.
- Treat `delete`, `remove`, `stop`, and forced deploys as destructive, and run them only when user intent is explicit.
- Never invent UUIDs; resolve resource IDs from command output first.
- Prefer minimally scoped changes before bulk operations.
- After mutation, run a matching `get` or `list` to verify final state.

## Execution Patterns
### Context and routing
Cloud:

```bash
coolify context set-token cloud <token>
```

Self-hosted:

```bash
coolify context add -d <context_name> <url> <token>
```

### Read-first inventory

```bash
coolify server list
coolify projects list
coolify app list
coolify database list
coolify service list
coolify resources list
```

### Deploy and logs

```bash
coolify deploy list
coolify deploy uuid <resource_uuid>
coolify app deployments logs <app_uuid> --lines 200
```

### API fallback for uncovered CLI cases
- Identify method/path/operationId from `references/api-reference.md`.
- Pull payload/schema details from `references/upstream/coolify-openapi.json`.
- Use bearer auth and base route guidance from `references/upstream/coolify-api-authorization.md`.
- Keep requests idempotent where possible and verify with a follow-up GET.

## Output Expectations
When using this skill, always return:
- selected context
- exact commands and API endpoints executed
- changed resources (name + UUID)
- verification result
- rollback or follow-up command when relevant
