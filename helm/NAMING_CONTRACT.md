# Naming contract across vizor-* Helm charts

All vizor-* charts use these **fixed names** for cross-referencing so resources work regardless of Argo app/release name.

| Resource | Fixed name | Used by |
|----------|------------|---------|
| Secret | `vizor-secrets` | vizor-secrets chart creates it; foundation, data-init, identity, apps reference it |
| ServiceAccount | `vizor-runtime` (or `{namespace}-runtime`) | Set via Argo param `serviceAccount.name`; foundation creates it |
| SQL Server service | `sql-server-service` | data-init creates it; identity (Keycloak, mssql-init-job) uses it |
| Migrations Job | `vizor-migrations` | data-init creates it; vizor-apps PreSync waits for it |
| Keycloak deployment/service | `keycloak` | identity chart |
| Keycloak API service | `vizor-keycloak-api-service` | identity chart |
| Core service | `vizor-core-service` | apps chart; Caddy (platform-support) and Ingress reference it |
| Engagement service | `vizor-engagement-service` | apps chart |
| Interaction service | `vizor-interaction-service` | apps chart |
| API proxy (Caddy) | `api-proxy` | platform-support chart |
| Redis service | `vizor-redis-master` | vizor-0-redis app (OCI chart) |

Each chart's `values.yaml` includes a `global` section with these names so templates reference `global.secretName`, `global.serviceAccountName`, etc., instead of `.Chart.Name` or `.Release.Name` for cross-chart resources.
