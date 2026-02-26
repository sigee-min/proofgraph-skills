# Coolify API Reference (Snapshot)

Generated from official Coolify docs and OpenAPI on 2026-02-24T09:31:31Z.

## Spec Summary

- Title: `Coolify`
- OpenAPI version: `3.1.0`
- API info.version: `0.1`
- Path count: `79`
- Operation count: `107`

## Authentication and Base URL

- Authorization header: `Authorization: Bearer <token>`
- Base route: `http://<ip>:8000/api`
- Versioned route: `http://<ip>:8000/api/v1` (except `/health` and `/feedback`)
- Token scope: Team-scoped API token
- Permission levels: `read-only`, `read:sensitive`, `view:sensitive`, `*`

## Operations By Tag

| Tag | Count |
| --- | --- |
| Applications | 19 |
| Cloud Tokens | 6 |
| Databases | 21 |
| Deployments | 5 |
| GitHub Apps | 6 |
| Hetzner | 5 |
| Private Keys | 5 |
| Projects | 9 |
| Resources | 1 |
| Servers | 8 |
| Services | 13 |
| Teams | 5 |
| Untagged | 4 |

## Full Operation Index

| Tag | Method | Path | Operation ID | Summary |
| --- | --- | --- | --- | --- |
| Applications | DELETE | `/applications/{uuid}` | `delete-application-by-uuid` | Delete |
| Applications | DELETE | `/applications/{uuid}/envs/{env_uuid}` | `delete-env-by-application-uuid` | Delete Env |
| Applications | GET | `/applications` | `list-applications` | List |
| Applications | GET | `/applications/{uuid}` | `get-application-by-uuid` | Get |
| Applications | GET | `/applications/{uuid}/envs` | `list-envs-by-application-uuid` | List Envs |
| Applications | GET | `/applications/{uuid}/logs` | `get-application-logs-by-uuid` | Get application logs. |
| Applications | GET | `/applications/{uuid}/restart` | `restart-application-by-uuid` | Restart |
| Applications | GET | `/applications/{uuid}/start` | `start-application-by-uuid` | Start |
| Applications | GET | `/applications/{uuid}/stop` | `stop-application-by-uuid` | Stop |
| Applications | PATCH | `/applications/{uuid}` | `update-application-by-uuid` | Update |
| Applications | PATCH | `/applications/{uuid}/envs` | `update-env-by-application-uuid` | Update Env |
| Applications | PATCH | `/applications/{uuid}/envs/bulk` | `update-envs-by-application-uuid` | Update Envs (Bulk) |
| Applications | POST | `/applications/dockercompose` | `create-dockercompose-application` | Create (Docker Compose) |
| Applications | POST | `/applications/dockerfile` | `create-dockerfile-application` | Create (Dockerfile without git) |
| Applications | POST | `/applications/dockerimage` | `create-dockerimage-application` | Create (Docker Image without git) |
| Applications | POST | `/applications/private-deploy-key` | `create-private-deploy-key-application` | Create (Private - Deploy Key) |
| Applications | POST | `/applications/private-github-app` | `create-private-github-app-application` | Create (Private - GH App) |
| Applications | POST | `/applications/public` | `create-public-application` | Create (Public) |
| Applications | POST | `/applications/{uuid}/envs` | `create-env-by-application-uuid` | Create Env |
| Cloud Tokens | DELETE | `/cloud-tokens/{uuid}` | `delete-cloud-token-by-uuid` | Delete Cloud Provider Token |
| Cloud Tokens | GET | `/cloud-tokens` | `list-cloud-tokens` | List Cloud Provider Tokens |
| Cloud Tokens | GET | `/cloud-tokens/{uuid}` | `get-cloud-token-by-uuid` | Get Cloud Provider Token |
| Cloud Tokens | PATCH | `/cloud-tokens/{uuid}` | `update-cloud-token-by-uuid` | Update Cloud Provider Token |
| Cloud Tokens | POST | `/cloud-tokens` | `create-cloud-token` | Create Cloud Provider Token |
| Cloud Tokens | POST | `/cloud-tokens/{uuid}/validate` | `validate-cloud-token-by-uuid` | Validate Cloud Provider Token |
| Databases | DELETE | `/databases/{uuid}` | `delete-database-by-uuid` | Delete |
| Databases | DELETE | `/databases/{uuid}/backups/{scheduled_backup_uuid}` | `delete-backup-configuration-by-uuid` | Delete backup configuration |
| Databases | DELETE | `/databases/{uuid}/backups/{scheduled_backup_uuid}/executions/{execution_uuid}` | `delete-backup-execution-by-uuid` | Delete backup execution |
| Databases | GET | `/databases` | `list-databases` | List |
| Databases | GET | `/databases/{uuid}` | `get-database-by-uuid` | Get |
| Databases | GET | `/databases/{uuid}/backups` | `get-database-backups-by-uuid` | Get |
| Databases | GET | `/databases/{uuid}/backups/{scheduled_backup_uuid}/executions` | `list-backup-executions` | List backup executions |
| Databases | GET | `/databases/{uuid}/restart` | `restart-database-by-uuid` | Restart |
| Databases | GET | `/databases/{uuid}/start` | `start-database-by-uuid` | Start |
| Databases | GET | `/databases/{uuid}/stop` | `stop-database-by-uuid` | Stop |
| Databases | PATCH | `/databases/{uuid}` | `update-database-by-uuid` | Update |
| Databases | PATCH | `/databases/{uuid}/backups/{scheduled_backup_uuid}` | `update-database-backup` | Update |
| Databases | POST | `/databases/clickhouse` | `create-database-clickhouse` | Create (Clickhouse) |
| Databases | POST | `/databases/dragonfly` | `create-database-dragonfly` | Create (DragonFly) |
| Databases | POST | `/databases/keydb` | `create-database-keydb` | Create (KeyDB) |
| Databases | POST | `/databases/mariadb` | `create-database-mariadb` | Create (MariaDB) |
| Databases | POST | `/databases/mongodb` | `create-database-mongodb` | Create (MongoDB) |
| Databases | POST | `/databases/mysql` | `create-database-mysql` | Create (MySQL) |
| Databases | POST | `/databases/postgresql` | `create-database-postgresql` | Create (PostgreSQL) |
| Databases | POST | `/databases/redis` | `create-database-redis` | Create (Redis) |
| Databases | POST | `/databases/{uuid}/backups` | `create-database-backup` | Create Backup |
| Deployments | GET | `/deploy` | `deploy-by-tag-or-uuid` | Deploy |
| Deployments | GET | `/deployments` | `list-deployments` | List |
| Deployments | GET | `/deployments/applications/{uuid}` | `list-deployments-by-app-uuid` | List application deployments |
| Deployments | GET | `/deployments/{uuid}` | `get-deployment-by-uuid` | Get |
| Deployments | POST | `/deployments/{uuid}/cancel` | `cancel-deployment-by-uuid` | Cancel |
| GitHub Apps | DELETE | `/github-apps/{github_app_id}` | `deleteGithubApp` | Delete GitHub App |
| GitHub Apps | GET | `/github-apps` | `list-github-apps` | List |
| GitHub Apps | GET | `/github-apps/{github_app_id}/repositories` | `load-repositories` | Load Repositories for a GitHub App |
| GitHub Apps | GET | `/github-apps/{github_app_id}/repositories/{owner}/{repo}/branches` | `load-branches` | Load Branches for a GitHub Repository |
| GitHub Apps | PATCH | `/github-apps/{github_app_id}` | `updateGithubApp` | Update GitHub App |
| GitHub Apps | POST | `/github-apps` | `create-github-app` | Create GitHub App |
| Hetzner | GET | `/hetzner/images` | `get-hetzner-images` | Get Hetzner Images |
| Hetzner | GET | `/hetzner/locations` | `get-hetzner-locations` | Get Hetzner Locations |
| Hetzner | GET | `/hetzner/server-types` | `get-hetzner-server-types` | Get Hetzner Server Types |
| Hetzner | GET | `/hetzner/ssh-keys` | `get-hetzner-ssh-keys` | Get Hetzner SSH Keys |
| Hetzner | POST | `/servers/hetzner` | `create-hetzner-server` | Create Hetzner Server |
| Private Keys | DELETE | `/security/keys/{uuid}` | `delete-private-key-by-uuid` | Delete |
| Private Keys | GET | `/security/keys` | `list-private-keys` | List |
| Private Keys | GET | `/security/keys/{uuid}` | `get-private-key-by-uuid` | Get |
| Private Keys | PATCH | `/security/keys` | `update-private-key` | Update |
| Private Keys | POST | `/security/keys` | `create-private-key` | Create |
| Projects | DELETE | `/projects/{uuid}` | `delete-project-by-uuid` | Delete |
| Projects | DELETE | `/projects/{uuid}/environments/{environment_name_or_uuid}` | `delete-environment` | Delete Environment |
| Projects | GET | `/projects` | `list-projects` | List |
| Projects | GET | `/projects/{uuid}` | `get-project-by-uuid` | Get |
| Projects | GET | `/projects/{uuid}/environments` | `get-environments` | List Environments |
| Projects | GET | `/projects/{uuid}/{environment_name_or_uuid}` | `get-environment-by-name-or-uuid` | Environment |
| Projects | PATCH | `/projects/{uuid}` | `update-project-by-uuid` | Update |
| Projects | POST | `/projects` | `create-project` | Create |
| Projects | POST | `/projects/{uuid}/environments` | `create-environment` | Create Environment |
| Resources | GET | `/resources` | `list-resources` | List |
| Servers | DELETE | `/servers/{uuid}` | `delete-server-by-uuid` | Delete |
| Servers | GET | `/servers` | `list-servers` | List |
| Servers | GET | `/servers/{uuid}` | `get-server-by-uuid` | Get |
| Servers | GET | `/servers/{uuid}/domains` | `get-domains-by-server-uuid` | Domains |
| Servers | GET | `/servers/{uuid}/resources` | `get-resources-by-server-uuid` | Resources |
| Servers | GET | `/servers/{uuid}/validate` | `validate-server-by-uuid` | Validate |
| Servers | PATCH | `/servers/{uuid}` | `update-server-by-uuid` | Update |
| Servers | POST | `/servers` | `create-server` | Create |
| Services | DELETE | `/services/{uuid}` | `delete-service-by-uuid` | Delete |
| Services | DELETE | `/services/{uuid}/envs/{env_uuid}` | `delete-env-by-service-uuid` | Delete Env |
| Services | GET | `/services` | `list-services` | List |
| Services | GET | `/services/{uuid}` | `get-service-by-uuid` | Get |
| Services | GET | `/services/{uuid}/envs` | `list-envs-by-service-uuid` | List Envs |
| Services | GET | `/services/{uuid}/restart` | `restart-service-by-uuid` | Restart |
| Services | GET | `/services/{uuid}/start` | `start-service-by-uuid` | Start |
| Services | GET | `/services/{uuid}/stop` | `stop-service-by-uuid` | Stop |
| Services | PATCH | `/services/{uuid}` | `update-service-by-uuid` | Update |
| Services | PATCH | `/services/{uuid}/envs` | `update-env-by-service-uuid` | Update Env |
| Services | PATCH | `/services/{uuid}/envs/bulk` | `update-envs-by-service-uuid` | Update Envs (Bulk) |
| Services | POST | `/services` | `create-service` | Create service |
| Services | POST | `/services/{uuid}/envs` | `create-env-by-service-uuid` | Create Env |
| Teams | GET | `/teams` | `list-teams` | List |
| Teams | GET | `/teams/current` | `get-current-team` | Authenticated Team |
| Teams | GET | `/teams/current/members` | `get-current-team-members` | Authenticated Team Members |
| Teams | GET | `/teams/{id}` | `get-team-by-id` | Get |
| Teams | GET | `/teams/{id}/members` | `get-members-by-team-id` | Members |
| Untagged | GET | `/disable` | `disable-api` | Disable API |
| Untagged | GET | `/enable` | `enable-api` | Enable API |
| Untagged | GET | `/health` | `healthcheck` | Healthcheck |
| Untagged | GET | `/version` | `version` | Version |

## Source Files

- `references/upstream/coolify-openapi.json`
- `references/upstream/coolify-api-authorization.md`
- `references/upstream/coolify-api-index.md`
- `references/upstream/coolify-api-operation-template.md`
- `references/upstream/coolify-api-operation-paths.ts`
