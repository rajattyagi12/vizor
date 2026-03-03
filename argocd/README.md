# Vizor ArgoCD App-of-Apps (Multi-Environment)

Each environment root is now a Helm chart that renders one `ApplicationSet`.
This removes hardcoded child-app source/destination values and lets the root ArgoCD Application owner set them via Helm values/parameters.

## Root Paths

Point each environment's existing ArgoCD root Application to one path:

- Dev: `argocd/root/dev`
- UAT: `argocd/root/uat`
- Prod: `argocd/root/prod`

Each root chart renders **standalone Applications** (same level as the ApplicationSet) plus one **ApplicationSet** that generates the remaining child apps. Standalone app **names are env- and order-prefixed** (e.g. `vizor-uat-0-redis`, `vizor-uat-2-mailhog`, `vizor-uat-3-sftpgo`) so multiple envs can coexist in the same Argo CD instance.

1. **vizor-{env}-0-redis** (`-3`) — Standalone. Redis (CloudPirates OSS, OCI); service `vizor-redis-master` for Dapr/SignalR.
2. **vizor-{env}-2-mailhog** (`-2`) — **Optional.** Standalone Mailhog (SMTP capture + Web UI). Set `mailhog.enabled: false` in root values to omit (e.g. UAT/prod); default when unset is to include.
3. **vizor-{env}-3-sftpgo** (wave `1`) — Standalone SFTPGo when used for that env. It expects the `vizor-secrets` Secret to exist in the destination namespace (managed by Kubespray). Rendered only when `sftpgo.enabled: true` in root values.
4. **ApplicationSet** generates (names: vizor-{env}-{order}-{app}): **vizor-{env}-4-foundation** (`-2`), **vizor-{env}-5-data-init** (`-1`), **vizor-{env}-6-identity** (`0`), **vizor-{env}-7-platform-support** (`1`), **vizor-{env}-8-apps** (`2`), **vizor-{env}-9-traffic-autoscale** (`3`)

Secret content (SQL, Keycloak, Dapr keys) is owned by Kubespray-managed `vizor-secrets` in the project namespace (`vizor-{env}`).

**SFTP / Dapr binding:** The application uses a Dapr SFTP binding (`sftpgo-binding`) to talk to an SFTP server. Dev machines may not have native SFTP, so in **dev** the binding targets in-cluster **SFTPGo** (vizor-sftpgo) at `vizor-sftpgo:2022`. In **prod** (and UAT when using external SFTP) the binding targets an **external SFTP server**; set `daprComponents.sftp.address`, `username`, and `password` in the Kubespray-managed `vizor-secrets` inputs.

**Cross-app ordering:** vizor-apps uses a PreSync hook (`wait-for-migrations`) that blocks until the vizor-data-init migrations Job (`vizor-migrations`) has completed, so app Deployments only sync after DB migrations are done. Foundation must create the `job-reader` Role/RoleBinding so the wait job can query Job status.

**Prerequisites (external to this repo):** **Dapr control plane** must be available. **Redis** is deployed by the standalone **vizor-redis** Application (wave -3, CloudPirates OSS chart from OCI) in the same namespace; service name is `env.redisServiceName` (default `vizor-redis-master`). Dapr state/pubsub host is derived from that app as `<redisServiceName>:6379`. No Chart.lock or vizor chart dependency needed. See [docs/RCA-api-proxy-dapr-redis-init-failure.md](docs/RCA-api-proxy-dapr-redis-init-failure.md) if api-proxy fails with "lookup vizor-redis-master ... no such host".

## User-Configurable Inputs

Set these through root app Helm values (file or ArgoCD Helm parameters):

- `env.repoURL` — **Required for UAT/prod.** Argo CD does not pass the root Application's `source.repoURL` into the chart. You must set `env.repoURL` via Helm parameters on the root Application (use the same URL as the root's `source.repoURL`) so child apps get the correct repo. If unset or `#CHANGEME`, the chart will fail render with an error.
- `env.targetRevision`
- `env.destinationNamespace`
- `env.redisServiceName` — **Optional.** Service name of the Redis deployed by the root’s vizor-redis Application (default `vizor-redis-master`). The Dapr Redis host is **derived** from this: vizor-foundation receives `daprComponents.state.redisHost` and `daprComponents.pubsub.redisHost` as `<redisServiceName>:6379`, so it always matches the Redis app (same namespace).
- `env.ingress.className`
- `env.ingress.host`
- **Gateway API:** When the root app receives a `gateway` block (e.g. from Kubespray `argocd_vizor` role with `gateway.name`, `gateway.namespace`, `gateway.listeners.http` / `gateway.listeners.https`), the ApplicationSet passes these as Helm parameters to **vizor-traffic-autoscale** and **vizor-platform-support**. Those charts then render **HTTPRoute** resources (Gateway API) instead of **Ingress**. If `gateway.name` is empty (e.g. root deployed without Kubespray), child charts fall back to Ingress. TLS is handled at the Gateway (e.g. Traefik `websecure` listener); no change to cert-manager.
- `env.extraValuesFile` — **Optional.** Path to a values file in the repo (e.g. `helm/vizor/values-env/preprod.yaml`) merged into all child apps after their normal value files.
- `mailhog.enabled` — **Optional.** Set to `false` in root values to omit the standalone Mailhog Application (e.g. in UAT/prod). When unset, the Mailhog app is included.
- `sftpgo.enabled` — **Optional.** Set to `true` to render the standalone SFTPGo Application. Keep `false` in UAT/prod when using external SFTP.
This allows branch-based testing via non-secret inputs (for example `env.targetRevision=codex/<branch>`) without storing credentials in this repo.

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
      value: "https://gitlab.com/group/vizor/deploy.git"   # same as source.repoURL; must be non-empty
    - name: env.targetRevision
      value: "uat"
    - name: env.destinationNamespace
      value: "vizor-uat"
```

**Troubleshooting "env.repoURL must be set on the root Application"**

If sync fails with that error, the chart received an empty or `#CHANGEME` `env.repoURL`. Fix it by:

1. Opening the root Application (e.g. Vizor UAT Root) in Argo CD.
2. Ensuring **Source** → **Helm** → **Parameters** includes an entry with **name** `env.repoURL` and **value** set to the full repo URL (the same URL as the Application's **Source** → **Repository URL**). The value must be non-empty.
3. If using YAML/CLI, the Application must have `spec.source.helm.parameters` with `name: env.repoURL` and `value: "https://..."` or `value: "ssh://git@..."` (same as `spec.source.repoURL`).

**Troubleshooting "Unable to save changes... ssh: handshake failed" (child apps)**

When you edit a child app in the Argo CD UI and click **Save**, Argo validates the app by asking the **repo server** to generate manifests from that app’s repo URL. The error means the repo server could not authenticate to the Git repo via SSH for that URL.

1. **Register the repo with SSH credentials in Argo CD**  
   Go to **Settings → Repositories** (or your project’s **Repositories**) and add the deploy repo URL (same as the root app’s **Source → Repository URL**, e.g. `git@git.nbt.local:vizor/deploy.git`). Configure **SSH private key** (and optional **Insecure ignore host key** for self-signed). The repo server uses this to fetch for *any* Application that uses this URL, including child apps.

2. **Ensure the child app uses the same repo URL**  
   Child app **Source → Repository URL** should match the root. It is set by the ApplicationSet from `env.repoURL`. If it was changed manually in the UI, sync the **root** app again so the ApplicationSet reapplies the correct spec, or set `env.repoURL` on the root and let the generator overwrite the child.

3. **Prefer changing values via the root, not the child**  
   To avoid validation errors when saving, drive config from the **root** Application (Helm parameters or value files in repo) rather than editing the child app’s Helm parameters in the UI. Child app source (repo, path, value files) is owned by the ApplicationSet; edits there can be overwritten on next root sync.

## Child App Value Files

ApplicationSet-generated child apps deploy `helm/vizor-*` charts with:

- `values.yaml`
- one environment file
- one layer file from `helm/vizor/values-layers/`

Current mapping:

- dev: split per child app under `helm/vizor/values-env/dev/`
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
- Runtime credentials must come from Kubespray-managed `vizor-secrets`; do not commit or pass credentials via root Helm parameters/values.
