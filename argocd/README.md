# Vizor ArgoCD App-of-Apps (Multi-Environment)

This repo now supports environment-specific App-of-Apps roots using `ApplicationSet`.

## Root Paths

Point each environment's existing ArgoCD root Application to exactly one path:

- Dev: `argocd/root/dev`
- UAT: `argocd/root/uat`
- Prod: `argocd/root/prod`

Each root path contains one `ApplicationSet` that generates the same five child apps with fixed ordering:

1. `vizor-foundation` (`-2`)
2. `vizor-data-init` (`-1`)
3. `vizor-identity` (`0`)
4. `vizor-apps` (`1`)
5. `vizor-traffic-autoscale` (`2`)

## Environment Parameters

Per environment, the `ApplicationSet` defines:

- `repoURL`
- `targetRevision`
- `namespace`
- environment values file (`values-dev.yaml` / `values-uat.yaml` / `values-prod.yaml`)
- ingress Helm parameters:
  - `ingress.className`
  - `ingress.host`
  - `ingress.certName`
  - `ingress.certIssuer`

Ingress values are injected via ArgoCD Helm parameters (not secrets and not chart defaults).

## Helm Layering

All child apps deploy `helm/vizor` with:

- `values.yaml`
- one environment file
- one layer file from `helm/vizor/values-layers/`

Layer files:

- `values-foundation.yaml`
- `values-data-init.yaml`
- `values-identity.yaml`
- `values-apps.yaml`
- `values-traffic-autoscale.yaml`

## Transition Notes

- `argocd/root/applications.yaml` is retained temporarily as deprecated fallback for transition.
- Static child app manifests under `argocd/apps/` were removed to avoid drift with ApplicationSet generation.

## Non-Secret Policy

- Keep environment config files non-secret.
- Continue injecting real secrets via Helm parameter overrides or your external secret flow.
