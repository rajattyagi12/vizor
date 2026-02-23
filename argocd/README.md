# Vizor ArgoCD App-of-Apps (Multi-Environment)

Each environment root is now a Helm chart that renders one `ApplicationSet`.
This removes hardcoded child-app source/destination values and lets the root ArgoCD Application owner set them via Helm values/parameters.

## Root Paths

Point each environment's existing ArgoCD root Application to one path:

- Dev: `argocd/root/dev`
- UAT: `argocd/root/uat`
- Prod: `argocd/root/prod`

Each root chart generates seven child apps with fixed wave ordering:

1. `vizor-secrets` (`-2`) — creates the Secret `vizor-secrets`; chart path `helm/vizor-secrets`
2. `vizor-foundation` (`-2`)
3. `vizor-data-init` (`-1`)
4. `vizor-identity` (`0`)
5. `vizor-platform-support` (`1`) — api-proxy (Caddy), optional mailhog, optional sftpgo (supporting platform; not core app workloads)
6. `vizor-apps` (`2`) — core, engagement, interaction, frontend (core developer components)
7. `vizor-traffic-autoscale` (`3`)

Secret content (SQL, Keycloak, Dapr keys) is owned by the **vizor-secrets** chart and its value files (`values-env/*/secrets.yaml`), not by foundation.

**Cross-app ordering:** vizor-apps uses a PreSync hook (`wait-for-migrations`) that blocks until the vizor-data-init migrations Job (`vizor-migrations`) has completed, so app Deployments only sync after DB migrations are done. Foundation must create the `job-reader` Role/RoleBinding so the wait job can query Job status.

## User-Configurable Inputs

Set these through root app Helm values (file or ArgoCD Helm parameters):

- `env.repoURL`
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
