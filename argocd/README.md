# Vizor ArgoCD App-of-Apps

This directory contains the in-place app-of-apps conversion for Vizor.

## Root app

Update the existing ArgoCD `vizor-deploy` application source path to:

- `argocd/root`

The root path renders only child `Application` resources.

## Child applications and order

Application sync-wave order:

1. `vizor-foundation` (`-2`)
2. `vizor-data-init` (`-1`)
3. `vizor-identity` (`0`)
4. `vizor-apps` (`1`)
5. `vizor-traffic-autoscale` (`2`)

## Layered Helm values

Each child app deploys the same chart (`helm/vizor`) with a layer file under `helm/vizor/values-layers/`:

- `values-foundation.yaml`
- `values-data-init.yaml`
- `values-identity.yaml`
- `values-apps.yaml`
- `values-traffic-autoscale.yaml`

Current child manifests use `values-dev.yaml` as the environment override to match the current deployment behavior.
For production, replace `values-dev.yaml` with `values-prod.yaml` in the child app manifests.

## Dependency contract

- Foundation deploys ServiceAccount, RBAC, secret material, secret-store components, and shared prerequisites.
- Data init deploys SQL init and migrations.
- Identity deploys Keycloak, realm initialization, and user sync.
- Apps deploy runtime services (`core`, `interaction`, `engagement`, `frontend`, `api-proxy`) and dev-only optional apps.
- Traffic/autoscale deploys ingress, HPA, and optional observability stack.

This ordering prevents HPA-before-deployment and migrations-before-service race conditions.
