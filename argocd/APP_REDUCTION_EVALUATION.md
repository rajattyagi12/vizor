# Evaluation: Should We Reduce the Number of Argo CD Apps to Better Manage Order?

## 1. Current State

### 1.1 App layout (6 applications)

| App                    | Wave | Chart            | What it deploys |
|------------------------|------|------------------|------------------|
| vizor-secrets          | -2   | helm/vizor-secrets| Secret `vizor-secrets` |
| vizor-foundation       | -2   | helm/vizor       | SA, Dapr (secretstore, pubsub, state), PVCs, Role/RoleBinding |
| vizor-data-init        | -1   | helm/vizor       | SQL Server + Service, migrations-job (wave 5) |
| vizor-identity         | 0    | helm/vizor       | mssql-init-job (wave -1), Keycloak, realm job (1), user-sync (6) |
| vizor-apps             | 1    | helm/vizor       | Caddy, frontend, core/engagement/interaction (wave 10), sftpgo, mailhog |
| vizor-traffic-autoscale | 2    | helm/vizor       | Ingress, HPA, observability (Loki/Grafana/Promtail) |

All except vizor-secrets use the **same chart** (`helm/vizor`) with different value files that enable one layer each (`components.foundation`, `dataInit`, `identity`, `apps`, `trafficAutoscale`).

### 1.2 How ordering works today

- **Between apps:** Application-level sync-waves (-2 → 2) control **when each Application is synced**. Argo CD does **not** wait for an app to be **Healthy** before syncing the next—only for the sync (apply) to complete. So we get **apply-order**, not **health-order**.
- **Within an app:** Resource-level sync-waves (e.g. mssql-init -1, realm 1, migrations 5, app Deployments 10) **do** cause Argo to wait for each wave to be **healthy** before applying the next. That’s why we moved mssql-init-job into identity: so one app owns both the job and Keycloak and wave -1 → 0 gives “job complete before Keycloak.”

### 1.3 Current pain

- **Two levels of waves** (app-level and resource-level) are easy to misread; the “wave 2 waits for wave 1” intuition only holds **inside** one app.
- **Weak cross-app ordering:** We already hit “Keycloak before mssql-init-job finished”; we fixed it by moving the job into identity. Migrations-job (data-init) and apps (vizor-apps) are still in different apps—Argo doesn’t wait for migrations-job to complete before syncing vizor-apps. In practice migrations-job often finishes before apps sync, but it’s not guaranteed.
- **Same chart, many apps:** Five apps are different “slices” of one chart; any chart change affects all when they sync. The benefit is mostly apply-order and UI grouping, not true independent lifecycles.

---

## 2. Options

### Option A: Single Application (1 or 2 apps)

**Model:** One Application that deploys `helm/vizor` with **all** layers enabled (one values file that sets `components.foundation.enabled`, `dataInit.enabled`, `identity.enabled`, `apps.enabled`, `trafficAutoscale.enabled` all true). Optionally keep **vizor-secrets** as a separate app at wave -2 so the single “vizor” app still has the Secret created first.

**Ordering:** Entirely by **resource-level** sync-waves inside the one vizor app. No app-level waves. We’d assign waves so that:

- Secret (or rely on vizor-secrets app) → Dapr → SQL Server → mssql-init-job → Keycloak → realm job → user-sync → app Deployments → Ingress/HPA/observability.

Existing in-chart waves (Secret -1 in vizor-secrets; Dapr 0; mssql-init -1; realm 1; migrations 5; user-sync 6; core/engagement/interaction 10) are partly there but today they’re split across apps. In a single app we’d need a **single** values file that enables all components and ensure **every** ordered resource has an explicit wave (e.g. SQL Server, Keycloak Deployment, Caddy, Ingress) so the full chain is health-ordered.

**Pros**

- **Strong ordering:** One app ⇒ Argo waits for each wave to be **healthy** before the next. No “identity started before data-init job finished” races; migrations-job completion before app Deployments would be guaranteed if we put migrations in an earlier wave than app Deployments.
- **Single source of truth:** One place to look for “what’s the deploy order?” (the resource waves in the chart).
- **Simpler mental model:** One “Vizor” app (plus optionally vizor-secrets). No “which app is wave 0 again?”
- **Fewer Application resources:** 1–2 apps instead of 6.

**Cons**

- **No per-layer sync:** You can’t “sync only identity” or “sync only apps” without syncing the whole app (or using partial sync / resource selection, which is more advanced and easy to misuse).
- **One big sync:** Full deploy is one sync; you can’t watch “foundation green, then data-init green” as separate apps. You see one app and drill into resources.
- **Rollback:** Rolling back “just identity” means reverting the repo and syncing the whole app (all layers). No app-level rollback of a single layer.
- **Visibility:** Harder to answer “which layer is broken?” at a glance (you look at resource status, not app status).

**Migration**

- Add a new “all-in-one” values layer (e.g. `values-layers/values-all.yaml`) that enables all components.
- Add/assign sync-waves to every resource that must be ordered (SQL Server, Keycloak Deployment, Caddy, Ingress, etc.); today some rely on app order.
- ApplicationSet: replace the 5 vizor-* apps with one `vizor` app using that all-in-one values file; keep vizor-secrets as-is if desired.
- One-time: either delete the old apps and let the single app own all resources, or run both in parallel in a test env and compare.

---

### Option B: Reduced apps (2–3 apps)

**Model:** Merge layers into fewer apps so that **within** each app we get health-ordered waves, and we have fewer app boundaries where ordering is weak.

Examples:

- **2 apps:** `vizor-platform` (secrets + foundation + data-init + identity), `vizor-apps-traffic` (apps + traffic-autoscale). Platform must be healthy (including migrations and Keycloak jobs) before apps-traffic syncs; between the two we still only have apply-order, but migrations and identity live in one app so their internal order is strong.
- **3 apps:** `vizor-platform` (secrets + foundation + data-init + identity), `vizor-apps` (apps), `vizor-traffic` (traffic-autoscale). Same idea: platform is one app (strong internal order), then apps, then traffic. Between apps we still rely on apply-order.

**Pros**

- **Fewer apps** (2–3) ⇒ fewer wave boundaries where “wait for healthy” is lost.
- **Critical path in one app:** If “platform” = secrets + foundation + data-init + identity (including mssql-init, migrations, Keycloak, realm, user-sync), then that entire chain is health-ordered inside one app. Only the “platform → apps” and “apps → traffic” boundaries are apply-order only.
- **Some per-layer visibility:** e.g. “platform” vs “apps” in the UI.
- **Some targeted sync:** Sync platform, then later sync apps (or vice versa for app-only changes).

**Cons**

- **Still two levels of waves:** App-level (platform -2, apps 0, traffic 1) and resource-level inside each app.
- **Platform → apps:** Argo still won’t wait for “platform Healthy” before syncing apps (unless we use sync hooks or a different mechanism). So “migrations completed before app Deployments” is still only best-effort unless we add something (e.g. a PreSync hook in apps that waits for migrations Job).
- **Values complexity:** Need combined values files (e.g. platform = foundation + dataInit + identity enabled) and possibly shared env values.

**Migration**

- Define new value layers (e.g. `values-platform.yaml` enabling foundation + dataInit + identity).
- ApplicationSet: replace foundation, data-init, identity with one `vizor-platform` app; keep apps and traffic-autoscale or merge apps+traffic into one.
- Assign resource-level waves inside platform so Secret → Dapr → SQL → mssql-init → Keycloak → realm → user-sync is health-ordered.

---

### Option C: Keep 6 apps, document and accept

**Model:** No structural change. Rely on apply-order between apps; rely on in-app waves where we already fixed the critical race (mssql-init inside identity). Document that “between apps we do not wait for Healthy” and add operational mitigations (e.g. “for full deploy, sync in order and wait for migrations-job if needed” or accept rare races and restart Keycloak/apps if needed).

**Pros**

- **No migration.** Current setup stays.
- **Per-layer sync and visibility** as today.
- **Clear ownership** in UI (foundation, data-init, identity, apps, traffic).

**Cons**

- **Ordering between apps remains weak.** Any new cross-app dependency (e.g. a job in data-init that apps need) risks the same “next app started before job finished” issue.
- **Two levels of waves** and the “wave 2 waits for wave 1” confusion remain.

---

## 3. Comparison

| Criterion                 | Option A (1 app)      | Option B (2–3 apps)   | Option C (6 apps)     |
|---------------------------|------------------------|------------------------|------------------------|
| **Ordering strength**     | Strong (all health-ordered) | Strong inside platform; apply-only at 1–2 boundaries | Apply-only between apps; strong only inside identity (after our fix) |
| **Simplicity**            | Highest (one app, one wave model) | Medium (fewer apps, still app + resource waves) | Lowest (6 apps, two wave levels) |
| **Per-layer sync**        | No                    | Partial (e.g. platform vs apps) | Yes                   |
| **Per-layer visibility**  | Low (drill into resources) | Medium (e.g. platform vs apps) | High (5–6 apps)       |
| **Rollback granularity**  | Whole stack           | By merged layer (e.g. platform vs apps) | By layer (foundation / data-init / identity / apps / traffic) |
| **Migration effort**      | Medium (waves + values + ApplicationSet) | Medium (merge values, ApplicationSet) | None                  |
| **Risk of future races**   | Low                   | Low for platform; medium at platform→apps | Medium (any new cross-app dep) |

---

## 4. Recommendation

- **If the main goal is “reliable, understandable ordering” and you’re okay with “one Vizor app” and no per-layer sync:**  
  **Option A (single app)** is the best fit. You get one place to define order (resource waves), and Argo’s “wait for healthy” applies to the whole chain. Keeping vizor-secrets as a separate app at wave -2 is optional and keeps secret ownership clear.

- **If you want to reduce apps but keep some “platform vs apps” separation and a bit of per-layer sync:**  
  **Option B (2–3 apps)** is a good compromise: put secrets + foundation + data-init + identity in one **platform** app (so the whole DB + Keycloak chain is health-ordered), and either one “apps-traffic” app or separate “apps” and “traffic.” You still have one or two boundaries where we only have apply-order; you can document that and optionally add a PreSync in the apps app that waits for migrations-job if you want that guarantee.

- **If you prefer no change and are willing to accept apply-order and occasional manual fixes:**  
  **Option C** is fine; just document the limitation and that “wave N+1 app does not wait for wave N app to be Healthy.”

**Summary:** Reducing apps (A or B) **does** improve order management because it moves more of the dependency chain **inside** a single Application, where sync-waves give health-ordered rollout. The benefit is real; the trade-off is less granular sync/visibility/rollback. Option A maximizes ordering and simplicity; Option B keeps some layer separation with fewer apps and stronger ordering than today.
