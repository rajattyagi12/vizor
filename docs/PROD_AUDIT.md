# Production settings audit

Audit of prod templates and value files to ensure all requisite pieces are in place.  
**Status:** Completed. See **Gaps** for items that require operator action or a decision.

---

## 1. Argo CD root (argocd/root/prod)

| Item | Status | Notes |
|------|--------|--------|
| **Chart.yaml** | OK | `vizor-root` type application, version 0.1.0 |
| **values.yaml** | Placeholders | `env.repoURL`, `env.ingress.host`, `env.ingress.certName`, `env.ingress.certIssuer` are `#CHANGEME`; must be set before prod deploy |
| **values.example.yaml** | OK | Documents real-looking values for copy/paste |
| **templates/applicationset.yaml** | OK | All 7 apps have explicit `appEnvValuesFile` → `../vizor/values-env/prod/<app>.yaml` |
| **templatePatch (ingress)** | OK | vizor-traffic-autoscale gets `ingress.className`, `ingress.host`, `ingress.certName`, `ingress.certIssuer` and `serviceAccount.name` from root values |
| **envValuesFile** | Redundant | Still in generator and root values (`values-prod.yaml`); unused because every app has `appEnvValuesFile`. Safe to remove for clarity |

---

## 2. ApplicationSet – apps and value file paths

All paths are relative to the **application path** (e.g. `helm/vizor-secrets`). So `../vizor/values-env/prod/secrets.yaml` resolves to `helm/vizor/values-env/prod/secrets.yaml` (repo root = parent of `helm/`).

| Order | App name | chartPath | appEnvValuesFile | layerValuesFile | extraValueFile |
|-------|----------|-----------|------------------|-----------------|----------------|
| 1 | vizor-secrets | helm/vizor-secrets | ../vizor/values-env/prod/secrets.yaml | ../vizor/values-layers/values-secrets.yaml | ../vizor/values-layers/values-empty.yaml |
| 2 | vizor-foundation | helm/vizor-foundation | ../vizor/values-env/prod/foundation.yaml | values.yaml | values.yaml |
| 3 | vizor-data-init | helm/vizor-data-init | ../vizor/values-env/prod/data-init.yaml | values.yaml | values.yaml |
| 4 | vizor-identity | helm/vizor-identity | ../vizor/values-env/prod/identity.yaml | values.yaml | values.yaml |
| 5 | vizor-platform-support | helm/vizor-platform-support | ../vizor/values-env/prod/platform-support.yaml | values.yaml | values.yaml |
| 6 | vizor-apps | helm/vizor-apps | ../vizor/values-env/prod/apps.yaml | values.yaml | values.yaml |
| 7 | vizor-traffic-autoscale | helm/vizor-traffic | ../vizor/values-env/prod/traffic-autoscale.yaml | values.yaml | values.yaml |

**Verification:** Each chart has a `values.yaml`; each referenced env file and layer file exists (see below).

---

## 3. Value files existence

**helm/vizor/values-env/prod/**

| File | Exists | Purpose |
|------|--------|---------|
| secrets.yaml | Yes | Secret content; placeholders only – replace via params/External Secrets |
| foundation.yaml | Yes | Prod foundation overrides (minimal) |
| data-init.yaml | Yes | `sqlServer.enabled: false` for external SQL |
| identity.yaml | Yes | Keycloak prod mode |
| platform-support.yaml | Yes | mailhog/sftpgo disabled (Caddy only) |
| apps.yaml | Yes | Prod apps overrides (minimal) |
| traffic-autoscale.yaml | Yes | mailhog disabled, observability off |
| mailhog.yaml | Yes | `enabled: false` for standalone vizor-mailhog in prod |
| sftpgo.yaml | Yes | `enabled: false` for standalone vizor-sftpgo in prod |

**helm/vizor/values-layers/** (referenced by vizor-secrets only)

| File | Exists |
|------|--------|
| values-secrets.yaml | Yes |
| values-empty.yaml | Yes |

**Per-chart values.yaml**

| Chart | Path | Exists |
|-------|------|--------|
| vizor-secrets | helm/vizor-secrets/values.yaml | Yes |
| vizor-foundation | helm/vizor-foundation/values.yaml | Yes |
| vizor-data-init | helm/vizor-data-init/values.yaml | Yes |
| vizor-identity | helm/vizor-identity/values.yaml | Yes |
| vizor-platform-support | helm/vizor-platform-support/values.yaml | Yes |
| vizor-apps | helm/vizor-apps/values.yaml | Yes |
| vizor-traffic | helm/vizor-traffic/values.yaml | Yes |

---

## 4. Standalone applications (Redis, Mailhog, SFTPGo)

| App | Template | Values refs | Status |
|-----|----------|-------------|--------|
| **vizor-redis** | application-redis.yaml | `.Values.argocdNamespace`, `.Values.project`, `.Values.env.destinationNamespace` | OK – no repoURL/targetRevision (OCI chart) |
| **vizor-mailhog** | application-mailhog.yaml | `.Values.env.repoURL`, `.Values.env.targetRevision`, `.Values.env.destinationNamespace` | OK – prod uses `../vizor/values-env/prod/mailhog.yaml` with `enabled: false` |
| **vizor-sftpgo** | application-sftpgo.yaml | Same as mailhog | OK – prod uses `../vizor/values-env/prod/sftpgo.yaml` with `enabled: false` |

---

## 5. Ingress and TLS (vizor-traffic)

- **templatePatch** passes `ingress.className`, `ingress.host`, `ingress.certName`, `ingress.certIssuer` into the vizor-traffic-autoscale Application.
- **vizor-traffic** chart uses `required "ingress.certName is required when TLS is enabled"` when TLS is enabled.
- **Gap:** Root `values.yaml` has `host: "#CHANGEME"`, `certName: "#CHANGEME"`, `certIssuer: "#CHANGEME"`. Sync will succeed only after these are set to real values (or TLS disabled in chart).

---

## 6. Gaps and required actions

| # | Gap | Action |
|---|-----|--------|
| 1 | **Root values placeholders** | Set `argocd/root/prod/values.yaml`: `env.repoURL`, `env.ingress.host`, `env.ingress.certName`, `env.ingress.certIssuer` before deploying prod (or use a non-committed overlay). |
| 2 | **Prod secrets** | Do not commit real credentials. Supply vizor-secrets content via Argo CD parameters, External Secrets, or a secured overlay. Keep `values-env/prod/secrets.yaml` as placeholders. |
| 3 | **Mailhog/SFTPGo in prod** | Addressed: prod standalone apps use `../vizor/values-env/prod/mailhog.yaml` and `../vizor/values-env/prod/sftpgo.yaml` with `enabled: false`, so no Mailhog/SFTPGo resources are created in prod. |
| 4 | **envValuesFile** | Optional cleanup: remove `envValuesFile` from `argocd/root/prod/values.yaml` and from the ApplicationSet generator (and valueFiles line) so prod matches dev (per-app env files only). |

---

## 7. Summary

- **Templates:** All requisite prod templates are in place (ApplicationSet + 3 standalone Applications). All appEnvValuesFile paths point to existing files.
- **Value files:** All 7 prod env files exist under `helm/vizor/values-env/prod/`. Layer files used by vizor-secrets exist.
- **Charts:** Every chart referenced by the ApplicationSet has a `values.yaml`.
- **Remaining:** Set root prod values (repoURL, ingress), supply secrets securely. Mailhog and SFTPGo are disabled in prod via `values-env/prod/mailhog.yaml` and `sftpgo.yaml`.
