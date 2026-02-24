# Vizor ArgoCD App-of-Apps (Multi-Environment)

Each environment root is now a Helm chart that renders one `ApplicationSet`.
This removes hardcoded child-app source/destination values and lets the root ArgoCD Application owner set them via Helm values/parameters.

## Root Paths

Point each environment's existing ArgoCD root Application to one path:

- Dev: `argocd/root/dev`
- UAT: `argocd/root/uat`
- Prod: `argocd/root/prod`

Each root chart generates eight child apps with fixed wave ordering:

1. `vizor-redis` (`-3`) — Redis (CloudPirates OSS, OCI); service `vizor-redis-master` for Dapr/SignalR
2. `vizor-secrets` (`-2`) — creates the Secret `vizor-secrets`; chart path `helm/vizor-secrets`
3. `vizor-foundation` (`-2`)
4. `vizor-data-init` (`-1`)
5. `vizor-identity` (`0`)
6. `vizor-platform-support` (`1`) — api-proxy (Caddy), optional mailhog, optional sftpgo (supporting platform; not core app workloads)
7. `vizor-apps` (`2`) — core, engagement, interaction, frontend (core developer components)
8. `vizor-traffic-autoscale` (`3`)

Secret content (SQL, Keycloak, Dapr keys) is owned by the **vizor-secrets** chart and its value files (`values-env/*/secrets.yaml`), not by foundation.

**Cross-app ordering:** vizor-apps uses a PreSync hook (`wait-for-migrations`) that blocks until the vizor-data-init migrations Job (`vizor-migrations`) has completed, so app Deployments only sync after DB migrations are done. Foundation must create the `job-reader` Role/RoleBinding so the wait job can query Job status.

**Prerequisites (external to this repo):** **Dapr control plane** must be available. **Redis** is deployed by the standalone **vizor-redis** Application (wave -3, CloudPirates OSS chart from OCI) in the same namespace with service name `vizor-redis-master`. No Chart.lock or vizor chart dependency needed. See [docs/RCA-api-proxy-dapr-redis-init-failure.md](docs/RCA-api-proxy-dapr-redis-init-failure.md) if api-proxy fails with "lookup vizor-redis-master ... no such host".

## User-Configurable Inputs

Set these through root app Helm values (file or ArgoCD Helm parameters):

- `env.repoURL` — **Required for UAT/prod.** Argo CD does not pass the root Application's `source.repoURL` into the chart. You must set `env.repoURL` via Helm parameters on the root Application (use the same URL as the root's `source.repoURL`) so child apps get the correct repo. If unset or `#CHANGEME`, the chart will fail render with an error.
- `env.targetRevision`
- `env.destinationNamespace`
- `env.ingress.className`
- `env.ingress.host`
- `env.ingress.certName`
- `env.ingress.certIssuer`

This allows branch-based testing without changing repo files (for example `env.targetRevision=codex/<branch>`).

ServiceAccount naming is derived automatically for all child apps as:

- `<env.destinationNamespace>-runtime`

Example: destination namespace `vizor-apps` => service account `vizor-apps-runtime`.

Example files you can copy from:

- `/Users/pritam/x/Vizor/deploy/argocd/root/dev/values.example.yaml`
- `/Users/pritam/x/Vizor/deploy/argocd/root/uat/values.example.yaml`
- `/Users/pritam/x/Vizor/deploy/argocd/root/prod/values.example.yaml`

When creating the root Application (e.g. Vizor UAT Root), pass `env.repoURL` (and optionally `env.targetRevision`, `env.destinationNamespace`) as Helm parameters so they propagate to child apps. Use the same URL as the root's `source.repoURL`:

```yaml
helm:
  parameters:
    - name: env.repoURL
      value: "https://gitlab.com/group/vizor/deploy.git"   # same as source.repoURL
    - name: env.targetRevision
      value: "uat"
    - name: env.destinationNamespace
      value: "vizor-uat"
```

## Child App Value Files

Generated child apps deploy either `helm/vizor` or `helm/vizor-secrets` (vizor-secrets app only) with:

- `values.yaml`
- one environment file
- one layer file from `helm/vizor/values-layers/`

Current mapping:

- dev: split per child app under `helm/vizor/values-env/dev/`
  - `secrets.yaml` (vizor-secrets app only)
  - `foundation.yaml`
  - `data-init.yaml`
  - `identity.yaml`
  - `platform-support.yaml` (api-proxy; mailhog and sftpgo optional via `mailhog.enabled` / `sftpgo.enabled`)
  - `apps.yaml`
  - `traffic-autoscale.yaml`
- uat: shared `values-uat.yaml` (not split yet)
- prod: shared `values-prod.yaml` (not split yet)

## Transition Notes

- `argocd/root/applications.yaml` remains as deprecated fallback during migration.
- Static child app manifests under `argocd/apps/` were removed to prevent drift.

## Non-Secret Policy

- Keep root/env config files non-secret.
- Continue providing secrets via Helm parameter overrides or external secret mechanism.
