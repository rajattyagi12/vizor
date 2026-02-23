# Separate Helm Charts (vizor-*)

Each vizor layer is now a **separate Helm chart** with **independent values**. This removes the previous "one chart, many value layers" fragility (nil dereferences when the wrong layer was active).

## Charts

| Chart | Path | Contents |
|-------|------|----------|
| vizor-secrets | `helm/vizor-secrets` | Secret `vizor-secrets` (unchanged) |
| vizor-foundation | `helm/vizor-foundation` | ServiceAccount, Dapr components (secretstore, state, pubsub), RBAC (secret-reader, job-reader), PVCs, local-path-provisioner |
| vizor-data-init | `helm/vizor-data-init` | SQL Server deployment + service, migrations Job (`vizor-migrations`) |
| vizor-identity | `helm/vizor-identity` | Keycloak (ConfigMap, Deployment, Service), mssql-init-job, keycloak-realm-job, keycloak-user-sync-job, rust-keycloak-api |
| vizor-mailhog | `helm/vizor-mailhog` | Standalone Mailhog (Deployment + Service + Ingress); no dependencies; wave -2 (like Redis) |
| vizor-platform-support | `helm/vizor-platform-support` | Caddy (api-proxy), optional SFTPGo + Dapr binding (Mailhog moved to vizor-mailhog) |
| vizor-apps | `helm/vizor-apps` | PreSync wait-for-migrations, frontend, core-service, engagement-service, interaction-service + Services |
| vizor-traffic | `helm/vizor-traffic` | Ingress, HPA, optional observability (Loki, Grafana, Promtail) |

## Naming contract

Cross-chart resource names are fixed so Ingress, Caddy, and HPA reference the same services. See [NAMING_CONTRACT.md](NAMING_CONTRACT.md).

## Argo CD

- **Dev:** ApplicationSet points each app to its chart path (`helm/vizor-foundation`, etc.) and passes env overrides from `../vizor/values-env/dev/*.yaml` where used.
- **UAT/Prod:** Same chart paths; `appEnvValuesFile` is empty for most apps (chart defaults only), with platform-support and traffic using env overrides as before.

## Env overrides

Env-specific overrides (dev/uat/prod) remain under `helm/vizor/values-env/{env}/` and are referenced by Argo as `../vizor/values-env/{env}/<app>.yaml`. Each separate chart’s `values.yaml` is self-contained; overlay only what you need per env.

## Validation

See [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md) for `helm template` commands, value coverage, Argo checks, and naming/namespace notes.

## Running

1. Ensure `vizor-secrets`, `vizor-redis` (if used), and `vizor-mailhog` (standalone, wave -2) are deployed. Mailhog has no dependencies.
2. Sync order is unchanged: secrets (-2), foundation (-2), data-init (-1), identity (0), platform-support (1), apps (2), traffic (3).
3. **vizor-foundation subchart:** Run `helm dependency update` in `helm/vizor-foundation` to fetch the local-path-provisioner subchart (requires network). To test without it: use the monolith `helm/vizor` with foundation layer, or run `helm dependency update` then `helm template vizor-foundation helm/vizor-foundation -n vizor`.
