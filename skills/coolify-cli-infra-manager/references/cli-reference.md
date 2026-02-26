# Coolify CLI Reference (Snapshot)

Generated from the official `coollabsio/coolify-cli` README on 2026-02-24T09:31:31Z.

## Setup

- Install script (Linux/macOS):
  - `curl -fsSL https://raw.githubusercontent.com/coollabsio/coolify-cli/main/scripts/install.sh | bash`
- Configure context (Cloud): `coolify context set-token cloud <token>`
- Configure context (Self-hosted): `coolify context add -d <context_name> <url> <token>`

## Scope

- Parsed command entries: `85`
- Global flags: `5`

## Command Index

| Command | Description |
| --- | --- |
| `coolify update` | Update the CLI to the latest version |
| `coolify config` | Show configuration file location |
| `coolify completion <shell>` | Generate shell completion script |
| `coolify context list` | List all configured contexts |
| `coolify context add <context_name> <url> <token>` | Add a new context |
| `coolify context delete <context_name>` | Delete a context |
| `coolify context get <context_name>` | Get details of a specific context |
| `coolify context set-token <context_name> <token>` | Update the API token for a context |
| `coolify context set-default <context_name>` | Set a context as the default |
| `coolify context update <context_name>` | Update a context's properties |
| `coolify context use <context_name>` | Switch to a different context (set as default) |
| `coolify context verify` | Verify current context connection and authentication |
| `coolify context version` | Get the Coolify API version of the current context |
| `coolify server list` | List all servers |
| `coolify server get <uuid>` | Get a server by UUID |
| `coolify server add <name> <ip> <private_key_uuid>` | Add a new server |
| `coolify server remove <uuid>` | Remove a server |
| `coolify server validate <uuid>` | Validate a server connection |
| `coolify server domains <uuid>` | Get server domains by UUID |
| `coolify projects list` | List all projects |
| `coolify projects get <uuid>` | Get project environments |
| `coolify resources list` | List all resources |
| `coolify app list` | List all applications |
| `coolify app get <uuid>` | Get application details |
| `coolify app update <uuid>` | Update application configuration |
| `coolify app delete <uuid>` | Delete an application |
| `coolify app start <uuid>` | Start an application |
| `coolify app stop <uuid>` | Stop an application |
| `coolify app restart <uuid>` | Restart an application |
| `coolify app logs <uuid>` | Get application logs |
| `coolify app env list <app_uuid>` | List all environment variables |
| `coolify app env get <app_uuid> <env_uuid_or_key>` | Get a specific environment variable |
| `coolify app env create <app_uuid>` | Create a new environment variable |
| `coolify app env update <app_uuid> <env_uuid>` | Update an environment variable |
| `coolify app env delete <app_uuid> <env_uuid>` | Delete an environment variable |
| `coolify app env sync <app_uuid>` | Sync environment variables from a .env file |
| `coolify app deployments list <app-uuid>` | List all deployments for an application |
| `coolify app deployments logs <app-uuid> [deployment-uuid]` | Get deployment logs (formatted as human-readable text) |
| `coolify database list` | List all databases |
| `coolify database get <uuid>` | Get database details |
| `coolify database create <type>` | Create a new database |
| `coolify database update <uuid>` | Update database configuration |
| `coolify database delete <uuid>` | Delete a database |
| `coolify database start <uuid>` | Start a database |
| `coolify database stop <uuid>` | Stop a database |
| `coolify database restart <uuid>` | Restart a database |
| `coolify database backup list <database_uuid>` | List all backup configurations |
| `coolify database backup create <database_uuid>` | Create a new backup configuration |
| `coolify database backup update <database_uuid> <backup_uuid>` | Update a backup configuration |
| `coolify database backup delete <database_uuid> <backup_uuid>` | Delete a backup configuration |
| `coolify database backup trigger <database_uuid> <backup_uuid>` | Trigger an immediate backup |
| `coolify database backup executions <database_uuid> <backup_uuid>` | List backup executions |
| `coolify database backup delete-execution <database_uuid> <backup_uuid> <execution_uuid>` | Delete a backup execution |
| `coolify service list` | List all services |
| `coolify service get <uuid>` | Get service details |
| `coolify service start <uuid>` | Start a service |
| `coolify service stop <uuid>` | Stop a service |
| `coolify service restart <uuid>` | Restart a service |
| `coolify service delete <uuid>` | Delete a service |
| `coolify service env list <service_uuid>` | List all environment variables |
| `coolify service env get <service_uuid> <env_uuid_or_key>` | Get a specific environment variable |
| `coolify service env create <service_uuid>` | Create a new environment variable |
| `coolify service env update <service_uuid> <env_uuid>` | Update an environment variable |
| `coolify service env delete <service_uuid> <env_uuid>` | Delete an environment variable |
| `coolify service env sync <service_uuid>` | Sync environment variables from a .env file |
| `coolify deploy uuid <uuid>` | Deploy a resource by UUID |
| `coolify deploy name <name>` | Deploy a resource by name |
| `coolify deploy batch <name1,name2,...>` | Deploy multiple resources at once |
| `coolify deploy list` | List all deployments |
| `coolify deploy get <uuid>` | Get deployment details |
| `coolify deploy cancel <uuid>` | Cancel a deployment |
| `coolify github list` | List all GitHub App integrations |
| `coolify github get <app_uuid>` | Get GitHub App details |
| `coolify github create` | Create a new GitHub App integration |
| `coolify github update <app_uuid>` | Update a GitHub App |
| `coolify github delete <app_uuid>` | Delete a GitHub App |
| `coolify github repos <app_uuid>` | List repositories accessible by a GitHub App |
| `coolify github branches <app_uuid> <owner/repo>` | List branches for a repository |
| `coolify team list` | List all teams |
| `coolify team get <team_id>` | Get team details |
| `coolify team current` | Get current team |
| `coolify team members list [team_id]` | List team members |
| `coolify private-key list` | List all private keys |
| `coolify private-key add <key_name> <private-key>` | Add a new private key |
| `coolify private-key remove <uuid>` | Remove a private key |

## Global Flags

| Flag | Description |
| --- | --- |
| `--context <name>` | Use a specific context instead of default |
| `--host <fqdn>` | Override the Coolify instance hostname |
| `--token <token>` | Override the authentication token |
| `--format <format>` | Output format: `table` (default), `json`, or `pretty` |
| `--debug` | Enable debug mode |

## Source Files

- `references/upstream/coolify-cli-readme.md`
- `references/upstream/coolify-cli-commands.tsv`
- `references/upstream/coolify-cli-global-flags.tsv`
