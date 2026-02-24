# Dev to prod carry-over checklist

This document lists what must be aligned or added so **production** (and UAT) match the **dev** setup that is now running with separate Helm charts and Argo CD.

---

## 1. Argo CD ApplicationSet: align prod/uat with dev structure

**Current state**

- **Dev:** Every ApplicationSet app has an explicit `appEnvValuesFile` pointing to `../vizor/values-env/dev/<app>.yaml` (secrets, foundation, data-init, identity, platform-support, apps, traffic-autoscale).
- **Prod / UAT:** Only **secrets** and **platform-support** have `appEnvValuesFile` set. The other apps use `appEnvValuesFile: ""` and the template uses `or .appEnvValuesFile .envValuesFile`, so the second valueFile becomes `values-prod.yaml` / `values-uat.yaml` **relative to the chart path** (e.g. `helm/vizor-foundation/values-prod.yaml`). Those files do **not** exist in the separate charts, so prod/uat can fail or fall back to chart defaults only.

**Required change**

- **Prod and UAT ApplicationSet:** Use the same pattern as dev: set an explicit `appEnvValuesFile` for **every** app, pointing at the env-specific file under `../vizor/values-env/<env>/`:
  - **foundation:** `../vizor/values-env/prod/foundation.yaml` (and uat equivalent)
  - **data-init:** `../vizor/values-env/prod/data-init.yaml`
  - **identity:** `../vizor/values-env/prod/identity.yaml`
  - **apps:** `../vizor/values-env/prod/apps.yaml`
  - **traffic-autoscale:** `../vizor/values-env/prod/traffic-autoscale.yaml`
- **Create the missing env value files** under `helm/vizor/values-env/prod/` and `helm/vizor/values-env/uat/` for: `foundation.yaml`, `data-init.yaml`, `identity.yaml`, `apps.yaml`, `traffic-autoscale.yaml`. They can be minimal (empty or comments) or contain prod/uat overrides; they must exist so the valueFiles list is valid.
- **Optional:** Remove `envValuesFile` from the list generator and from `argocd/root/prod/values.yaml` and `argocd/root/uat/values.yaml` so prod/uat rely only on per-app `appEnvValuesFile` (same as dev). If you keep `envValuesFile`, ensure the template does not require a per-chart `values-prod.yaml` (e.g. do not use it in valueFiles for apps that use separate charts).

**Exact ApplicationSet changes (prod)**

In `argocd/root/prod/templates/applicationset.yaml`, replace the empty `appEnvValuesFile: ""` with:

| App | Replace | With |
|-----|---------|------|
| vizor-foundation | `appEnvValuesFile: ""` | `appEnvValuesFile: ../vizor/values-env/prod/foundation.yaml` |
| vizor-data-init | `appEnvValuesFile: ""` | `appEnvValuesFile: ../vizor/values-env/prod/data-init.yaml` |
| vizor-identity | `appEnvValuesFile: ""` | `appEnvValuesFile: ../vizor/values-env/prod/identity.yaml` |
| vizor-apps | `appEnvValuesFile: ""` | `appEnvValuesFile: ../vizor/values-env/prod/apps.yaml` |
| vizor-traffic-autoscale | `appEnvValuesFile: ""` | `appEnvValuesFile: ../vizor/values-env/prod/traffic-autoscale.yaml` |

(Secrets and platform-support already have prod appEnvValuesFile.) After this, you can remove `envValuesFile` from the prod list generator and from the template’s valueFiles if you want prod to match dev (no shared envValuesFile).

**Files to touch**

- `argocd/root/prod/templates/applicationset.yaml` – set `appEnvValuesFile` as in the table above; optionally drop `envValuesFile` from the generator and from the valueFiles line.
- `argocd/root/uat/templates/applicationset.yaml` – same for `../vizor/values-env/uat/<app>.yaml`.
- Add: `helm/vizor/values-env/prod/foundation.yaml`, `data-init.yaml`, `identity.yaml`, `apps.yaml`, `traffic-autoscale.yaml`.
- Add: `helm/vizor/values-env/uat/foundation.yaml`, `data-init.yaml`, `identity.yaml`, `apps.yaml`, `traffic-autoscale.yaml` (if UAT should mirror dev structure).

---

## 2. Argo CD root values (prod/uat)

**argocd/root/prod/values.yaml** (and uat)

- **env.repoURL:** Replace `"#CHANGEME"` with the real prod (and uat) Git repo URL.
- **env.targetRevision:** Prod uses `main`; confirm this is the correct branch/tag for prod.
- **env.destinationNamespace:** Already `vizor`; no change unless prod uses a different namespace.
- **env.ingress.host:** Set to the prod (and uat) hostname, e.g. `vizor.example.com`.
- **env.ingress.certName / certIssuer:** Set to the real TLS cert name and issuer (e.g. cert-manager) for prod/uat.
- **env.envValuesFile:** If you remove it when aligning ApplicationSet (see above), delete it from prod/uat values.

---

## 3. values-env/prod (and uat) – content to carry or override

These are the **thematic** overrides to carry from dev → prod (or define for prod). Implement them in the new `values-env/prod/*.yaml` (and uat) files where applicable.

| Area | Dev | Prod carry-over |
|------|-----|------------------|
| **Secrets** | `values-env/dev/secrets.yaml` – dev passwords and keys | **Already have** `values-env/prod/secrets.yaml` with `#CHANGEME` placeholders. **Action:** Replace with real prod secrets via Argo CD parameters, External Secrets, or a secured overlay; never commit real prod credentials. |
| **Foundation** | Dev foundation.yaml is mostly a comment | Prod: use chart defaults or add overrides (e.g. `local-path-provisioner.enabled: false` if prod has its own storage). |
| **Data-init** | Dev: `sqlServer.enabled: true`, dev password | Prod: typically `sqlServer.enabled: false` and use **external SQL**; connection string and SA_PASSWORD come from vizor-secrets. If prod runs in-cluster SQL, set `sqlServer.enabled: true` and provide secret via secrets.yaml. |
| **Identity** | Dev: `keycloak.startMode: start-dev`, dev passwords, dev realm URLs | Prod: `keycloak.startMode: start`, production Keycloak URLs, hostname, and secrets from vizor-secrets. Pin image tag. |
| **Platform-support** | Dev: optional mailhog/sftpgo enabled in platform-support layer | **Already have** `values-env/prod/platform-support.yaml` with mailhog/sftpgo disabled. Caddy (api-proxy) only is correct for prod. |
| **Apps** | Dev: image tag latest, dev auth/client settings, optional features | Prod: **pin image tag** (e.g. release version), set `auth.clientId` and any prod URLs; increase replicas/resources if needed. |
| **Traffic** | Dev: mailhog ingress enabled, observability disabled | Prod: **ingress** – set className, host, certName, certIssuer via root values (templatePatch). **Observability:** Enable in prod if desired (`observability.enabled: true`). **Mailhog:** Disabled (handled by standalone app or disabled there). |

---

## 4. Standalone applications (redis, mailhog, sftpgo)

- **Templates:** `application-redis.yaml`, `application-mailhog.yaml`, `application-sftpgo.yaml` are **identical** across dev/uat/prod; they use `.Values.env.*` (repoURL, targetRevision, destinationNamespace). No structural change needed.
- **Prod/uat values:** Ensure `argocd/root/prod/values.yaml` and uat have correct `env.repoURL` and `env.targetRevision` so these apps point at the right repo and branch.
- **Mailhog in prod:** If prod should **not** run Mailhog, either:
  - **Option A:** Do not deploy the vizor-mailhog Application in prod (remove or don’t apply `application-mailhog.yaml` for prod root), or
  - **Option B:** Add a value file for the mailhog app in prod that sets `enabled: false` (would require adding `valueFiles` to the standalone application-mailhog template when env is prod, or a separate prod-only Application that points to the same chart with a prod value file that disables it).
- **SFTPGo in prod:** Same as Mailhog – disable via `enabled: false` in a prod value file for vizor-sftpgo, or omit the vizor-sftpgo Application in prod if you use external SFTP.

---

## 5. Chart-specific prod overrides (summary)

- **vizor-secrets:** Prod secret content must come from a secure source (Argo params, External Secrets, or a non-committed overlay). `values-env/prod/secrets.yaml` keeps placeholders; replace at deploy time.
- **vizor-foundation:** Prod often uses existing storage; set `persistence.enabled: false` and/or `local-path-provisioner.enabled: false` if applicable. Dapr component Redis host stays `vizor-redis-master:6379` if Redis is in the same namespace.
- **vizor-data-init:** If using external SQL, disable in-cluster SQL (`sqlServer.enabled: false`) and ensure vizor-secrets has the external connection string and SA_PASSWORD (or equivalent) for the apps that need it. Migrations job still needs connectionString from the secret.
- **vizor-identity:** Prod: Keycloak `startMode: start`, hostname set, production realm URLs and secrets; pin Keycloak image tag.
- **vizor-platform-support:** Prod: Caddy only (no Mailhog/SFTPGo in this chart); already reflected in `values-env/prod/platform-support.yaml`.
- **vizor-apps:** Prod: pin image tag, set `auth.clientId`, replicas/resources as needed. No mailhog/sftpgo keys in this chart (they’re standalone).
- **vizor-traffic:** Prod: ingress host/cert from root values (templatePatch); enable observability if desired; HPA/autoscaling already in chart.
- **vizor-mailhog / vizor-sftpgo:** Disable in prod via `enabled: false` in a prod-only value file, or by not deploying their Applications in prod.

---

## 6. Image tags and pull policy

- **Dev:** Often `tag: latest` and `pullPolicy: Always`.
- **Prod:** Pin to a release tag or digest in the relevant `values-env/prod/*.yaml` (e.g. identity, apps, data-init) and use `pullPolicy: IfNotPresent` or `Always` as per policy.

---

## 7. Optional: single envValuesFile for prod/uat

If you prefer a **single** prod overlay (e.g. `values-prod.yaml`) instead of per-app files:

- That file would need to live in a place Argo can use. With **separate charts**, each application has a different `path` (e.g. `helm/vizor-foundation`). So a single `values-prod.yaml` would have to be either:
  - In each chart directory (e.g. `helm/vizor-foundation/values-prod.yaml`), or
  - A shared file referenced by path relative to repo root (e.g. `../vizor/values-env/prod/values-prod.yaml`) and included in **every** app’s valueFiles.

The recommended approach is the **per-app** env files (as in dev) so each chart gets only the overrides it needs and the structure is the same across dev/uat/prod.

---

## 8. Checklist summary

| # | Task | Owner |
|---|------|--------|
| 1 | Align prod ApplicationSet with dev: set `appEnvValuesFile` for foundation, data-init, identity, apps, traffic-autoscale to `../vizor/values-env/prod/<app>.yaml`. | |
| 2 | Same for UAT ApplicationSet with `../vizor/values-env/uat/<app>.yaml`. | |
| 3 | Create `helm/vizor/values-env/prod/foundation.yaml`, `data-init.yaml`, `identity.yaml`, `apps.yaml`, `traffic-autoscale.yaml` (minimal or full overrides). | |
| 4 | Create same set under `helm/vizor/values-env/uat/` if UAT mirrors dev. | |
| 5 | Set prod (and uat) root values: `repoURL`, `targetRevision`, `ingress.host`, `ingress.certName`, `ingress.certIssuer`. | |
| 6 | Populate prod secrets via secure mechanism; keep `values-env/prod/secrets.yaml` as placeholder only. | |
| 7 | In prod env files: disable or externalise SQL/Mailhog/SFTPGo as needed; pin image tags; set Keycloak to prod mode; enable ingress and TLS. | |
| 8 | Decide: disable Mailhog/SFTPGo in prod (by value file or by not deploying their Applications). | |
| 9 | (Optional) Remove `envValuesFile` from prod/uat root and ApplicationSet template once per-app env files are in use. | |

---

## 9. Files reference

**Argo root**

- `argocd/root/dev/values.yaml` – reference for dev.
- `argocd/root/prod/values.yaml` – set repoURL, ingress, etc.
- `argocd/root/uat/values.yaml` – same for UAT.
- `argocd/root/dev/templates/applicationset.yaml` – reference (per-app appEnvValuesFile).
- `argocd/root/prod/templates/applicationset.yaml` – align with dev; add prod appEnvValuesFile for all apps.
- `argocd/root/uat/templates/applicationset.yaml` – same for UAT.

**Env value files**

- `helm/vizor/values-env/dev/*.yaml` – existing dev overrides.
- `helm/vizor/values-env/prod/secrets.yaml`, `platform-support.yaml` – exist; add foundation, data-init, identity, apps, traffic-autoscale.
- `helm/vizor/values-env/uat/*.yaml` – add missing files to mirror dev structure if desired.

**Legacy (monolith)**

- `helm/vizor/values-prod.yaml` – written for the **monolith** chart (components.*, sqlServer, etc.). With separate charts, prod overrides live in `values-env/prod/<app>.yaml`. You can keep `values-prod.yaml` for reference or for local helm installs of the monolith; it is not used by the prod ApplicationSet if you switch to per-app env files as above.
