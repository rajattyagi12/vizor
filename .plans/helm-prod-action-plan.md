# Helm Production Improvement Plan (ArgoCD)

## Traceability Matrix

| ID | Issue / Risk | Evidence (File) | Impact | Planned Change (Summary) | Phase | Status |
| --- | --- | --- | --- | --- | --- | --- |
| T-02 | Dev components enabled in prod (MailHog, local SQL, local-path) | /Users/pritam/x/Vizor/deploy/helm/vizor/templates/mailhog-deployment.yaml | Production exposure and instability | Add enable flags and disable in prod values | Phase 1 | Planned |
| T-10 | Local SQL Server exposed via NodePort | /Users/pritam/x/Vizor/deploy/helm/vizor/templates/sqlserver.yaml | Production exposure | Disable in prod and use external DB; keep internal DB for dev only | Phase 1 | Planned |
| T-01 | Plaintext secrets in values and ConfigMaps/Secrets | /Users/pritam/x/Vizor/deploy/helm/vizor/values.yaml | Credential exposure in git, Helm values, and runtime | Remove plaintext secrets; rely on Helm parameter overrides | Phase 2 | Planned |
| T-03 | Hardcoded namespaces in templates | /Users/pritam/x/Vizor/deploy/helm/vizor/templates/ingress-rules.yaml | Cross-namespace drift, ArgoCD app mismatch | Replace with .Release.Namespace | Phase 2 | Planned |
| T-05 | Ingress TLS config fallback invalid | /Users/pritam/x/Vizor/deploy/helm/vizor/templates/ingress-rules.yaml | TLS failure, insecure ingress | Require certName or certIssuer and fix secretName | Phase 2 | Planned |
| T-06 | Service account and RBAC use default SA | /Users/pritam/x/Vizor/deploy/helm/vizor/templates/components/secret.yaml | Over-privileged workloads | Add chart SA and restrict RBAC | Phase 2 | Planned |
| T-04 | Keycloak uses start-dev and inline admin creds | /Users/pritam/x/Vizor/deploy/helm/vizor/templates/keycloak-deployment.yaml | Insecure production auth | Use prod start options; rely on Helm parameter overrides for creds | Phase 3 | Planned |
| T-07 | Missing securityContext hardening | /Users/pritam/x/Vizor/deploy/helm/vizor/templates/core-service.yaml | Privilege escalation risk | Add pod/container security contexts | Phase 3 | Planned |
| T-08 | Missing probes on core services | /Users/pritam/x/Vizor/deploy/helm/vizor/templates/interaction-service.yaml | Unreliable rollouts and recovery | Add liveness/readiness/startup probes | Phase 3 | Planned |
| T-12 | Image tags use latest and Always pull | /Users/pritam/x/Vizor/deploy/helm/vizor/values.yaml | Non-reproducible deployments | Pin versions/digests and adjust pull policy | Phase 3 | Planned |
| T-09 | No HPA/PDB | /Users/pritam/x/Vizor/deploy/helm/vizor/templates | Reduced HA and scaling, unclear autoscaling requirements | Audit HPA need and add autoscaling + PDB templates if required | Phase 4 | Planned |
| T-13 | No anti-affinity/topology spread/priority for HA | /Users/pritam/x/Vizor/deploy/helm/vizor/templates | Pod co-location risk across 4 worker nodes | Add anti-affinity/topology spread and priority class options | Phase 4 | Planned |
| T-14 | Several critical components are singleton replicas | /Users/pritam/x/Vizor/deploy/helm/vizor/templates | Single point of failure | Raise replica counts where possible and add PDBs | Phase 4 | Planned |
| T-11 | Misnamed file with leading space | /Users/pritam/x/Vizor/deploy/helm/vizor/templates/components/keycloak/ keycloak-user-sync-job.yaml | Tooling errors, hidden changes | Rename file to remove leading space | Phase 5 | Planned |

## High Availability Audit Findings

**Summary:** HA controls are minimal. Several core components are single‑replica, and there are no anti‑affinity, topology spread, priority classes, or PDBs. This introduces single points of failure and co‑location risk.

**Findings (by component):**
1. **Singleton replicas (SPOF):**
   1. `api-proxy` (Caddy gateway) is `replicas: 1` in `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/caddy-api-gateway.yaml`.
   1. `keycloak` is `replicas: 1` in `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/keycloak-deployment.yaml`.
   1. `sqlserver` is `replicas: 1` in `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/sqlserver.yaml`.
   1. `sftpgo` is `replicas: 1` in `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/sftpgo-deployment.yaml`.
   1. `rust-keycloak-api` is `replicas: 1` in `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/rust-keycloak-api-deployment.yaml`.
   1. `grafana` is `replicas: 1` in `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/grafana-deployment.yaml`.
   1. `frontend` defaults to 1 replica in `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/frontend.yaml` and `/Users/pritam/x/Vizor/deploy/helm/vizor/values.yaml`.
2. **No pod anti‑affinity or topology spread constraints** across workloads; there are no occurrences of `affinity`, `podAntiAffinity`, or `topologySpreadConstraints` in templates.
3. **No priority classes** for critical workloads (`priorityClassName` not present).
4. **No PodDisruptionBudgets** to protect availability during node maintenance or voluntary disruptions.
5. **Session affinity reliance** for `core-service` and `interaction-service` is present, but without HA controls it increases risk during scale‑down or node loss.

## Phased Delivery

**Phase 1: Prod Safety Baseline (disable non‑prod services in prod to ease testing)**
1. Implement `values-prod.yaml` and `values-dev.yaml` with prod disabling:
   1. `mailhog.enabled: false` (dev only).
   1. `sftpgo.enabled: false` (not required in prod).
   1. `sqlServer.enabled: false` (external DB in prod).
   1. `local-path-provisioner.enabled: false`.
   1. `observability.enabled: false` until tested.
2. Add end-to-end disablement for non‑prod services by gating templates:
   1. Add `mailhog.enabled` to `/Users/pritam/x/Vizor/deploy/helm/vizor/values.yaml` (default `false`, dev only).
   1. Wrap `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/mailhog-deployment.yaml` with `if .Values.mailhog.enabled` so prod values can fully disable it.
2. Ensure ArgoCD Application references `values-prod.yaml` for prod and `values-dev.yaml` for dev.

**Phase 2: Security and Correctness**
1. Remove plaintext secrets from `values.yaml` and rely on Helm parameter overrides in ArgoCD.
2. Add service account and tighten RBAC for secrets.
3. Fix ingress correctness (Traefik class, TLS secret naming).
4. Remove hardcoded namespaces.

**Phase 3: Production Hardening**
1. Keycloak production mode (non‑dev start flags) and Helm‑configurable hostname.
2. SecurityContext hardening.
3. Health probes.
4. Image tag pinning and pull policy adjustments.

**Phase 4: High Availability**
1. Replica targets (including `frontend` and `api-proxy` based on expected traffic).
2. PDBs with `minAvailable: 1`.
3. Anti‑affinity/topology spread and priority classes.
4. HPA rollout including Keycloak (replicas: 2) once clustering config is finalized.

**Phase 5: Hygiene**
1. Fix misnamed template file.

**Deployment Gate**
1. Block production deployment until T-13 (anti‑affinity/topology spread/priority) and all related Phase 4 action items are implemented and verified.

## Detailed Action Plan (Grouped by Phase)

### Phase 1: Prod Safety Baseline
1. Create `/Users/pritam/x/Vizor/deploy/helm/vizor/values-prod.yaml` and `/Users/pritam/x/Vizor/deploy/helm/vizor/values-dev.yaml`.
1. In `values-prod.yaml` disable non‑prod services:
   1. `mailhog.enabled: false` (dev only).
   1. `sftpgo.enabled: false` (not required in prod).
   1. `sqlServer.enabled: false` (external DB in prod).
   1. `local-path-provisioner.enabled: false`.
   1. `observability.enabled: false` until tested.
1. Ensure ArgoCD Application references `values-prod.yaml` for prod and `values-dev.yaml` for dev.

### Phase 2: Security and Correctness
1. Replace plaintext secrets in `/Users/pritam/x/Vizor/deploy/helm/vizor/values.yaml` with `#CHANGEME` placeholders and rely on Helm parameter overrides in ArgoCD.
2. Move the replaced secret values into `/Users/pritam/x/Vizor/deploy/helm/vizor/values-dev.yaml` for dev only.
1. Add `serviceAccount` values and a ServiceAccount template; bind workloads to it.
1. Tighten RBAC in `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/components/secret.yaml` to `get` only and bind to the chart service account.
1. Fix ingress correctness in `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/ingress-rules.yaml`:
   1. Add `ingressClassName`.
   1. Fix TLS secret name to use `ingress.certName`.
   1. Set `ingress.className: traefik` in `values-prod.yaml`.
1. Replace all hardcoded namespaces with `{{ .Release.Namespace }}` in templates.
1. Ensure ArgoCD Application uses Helm parameters or value files to inject secret values at sync time.

### Phase 3: Production Hardening
1. Replace `start-dev` with production start flags in `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/keycloak-deployment.yaml`.
1. Add Helm‑configurable Keycloak hostname values (`keycloak.hostname`, `keycloak.hostnameStrict`) and wire into Keycloak args.
1. Set `keycloak.hostnameStrict` default to `false` in `/Users/pritam/x/Vizor/deploy/helm/vizor/values.yaml`.
1. Add pod and container security contexts to critical workloads.
1. Add readiness/liveness/startup probes to core services and enable Dapr app health checks.
1. Pin image tags and set pull policy in `values-prod.yaml`.

### Phase 4: High Availability
1. Set replica targets in `values-prod.yaml`:
   1. `coreService.replicas: 2` (or higher based on load).
   1. `interactionService.replicas: 2` (or higher; keep session affinity considerations).
   1. `engagementService.replicas: 2`.
   1. `frontend.replicas` based on expected traffic.
   1. `api-proxy` replicas based on expected traffic.
   1. `keycloak.replicas: 2` and enable HPA for Keycloak.
1. Add pod anti‑affinity and topology spread constraints for critical stateless workloads (4 worker nodes).
1. Add `priorityClassName` values and wire into critical deployments.
1. Add HPA templates and `autoscaling` values, including Keycloak.
1. Add PDBs with `minAvailable: 1` for critical services.
1. Ensure Kubernetes Metrics Server is installed and resource requests are set.

### Phase 5: Hygiene
1. Rename `/Users/pritam/x/Vizor/deploy/helm/vizor/templates/components/keycloak/ keycloak-user-sync-job.yaml` to remove the leading space.

## Execution Notes
- Apply changes in small, reviewable commits, grouped by step.
- Validate Helm render with `helm template` before ArgoCD sync.
- Do not commit secrets to git.
