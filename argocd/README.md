# Vizor ArgoCD App-of-Apps (Multi-Environment)

Each environment root is now a Helm chart that renders one `ApplicationSet`.
This removes hardcoded child-app source/destination values and lets the root ArgoCD Application owner set them via Helm values/parameters.

## Root Paths

Point each environment's existing ArgoCD root Application to one path:

- Dev: `argocd/root/dev`
- UAT: `argocd/root/uat`
- Prod: `argocd/root/prod`

Each root chart generates the same five child apps with fixed wave ordering:

1. `vizor-foundation` (`-2`)
2. `vizor-data-init` (`-1`)
3. `vizor-identity` (`0`)
4. `vizor-apps` (`1`)
5. `vizor-traffic-autoscale` (`2`)

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

Generated child apps deploy `helm/vizor` with:

- `values.yaml`
- one env file:
  - dev: `values-dev.yaml`
  - uat: `values-uat.yaml`
  - prod: `values-prod.yaml`
- one layer file from `helm/vizor/values-layers/`

## Transition Notes

- `argocd/root/applications.yaml` remains as deprecated fallback during migration.
- Static child app manifests under `argocd/apps/` were removed to prevent drift.

## Non-Secret Policy

- Keep root/env config files non-secret.
- Continue providing secrets via Helm parameter overrides or external secret mechanism.
