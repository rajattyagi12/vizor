# Replicating the Vizor environment on Kind (local development)

This guide describes how to run the same stack (separate Helm charts, Redis, Mailhog, SFTPGo, etc.) locally using a [Kind](https://kind.sigs.k8s.io/) cluster. Two approaches:

1. **Helm-only** – Script installs each chart in dependency order; no Argo CD. Easiest for “same resources, fast iteration.”
2. **Argo CD in Kind** – Install Argo CD and point it at this repo so the same ApplicationSet and Applications drive the cluster. Best for testing the exact GitOps flow.

---

## Prerequisites

- **kind** – [Install Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- **kubectl** – configured to use the Kind cluster
- **helm** – v3
- **Dapr** – control plane must be installed in the cluster (see below)

---

## 1. Create the Kind cluster

```bash
kind create cluster --name vizor-dev
kubectl cluster-info --context kind-vizor-dev
```

Optional: if you use images from a private registry (e.g. `harbor.nbt.local`), either:

- Push images to a registry Kind can pull from, or  
- [Load images into Kind](https://kind.sigs.k8s.io/docs/user/loading-images/):  
  `kind load docker-image <your-image> --name vizor-dev`

---

## 2. Install Dapr

The stack expects the Dapr control plane in `dapr-system`. Install it once per cluster:

```bash
helm repo add dapr https://dapr.github.io/helm-charts/
helm repo update
helm upgrade --install dapr dapr/dapr \
  --version 1.16.2 \
  --namespace dapr-system \
  --create-namespace \
  --wait
kubectl get pods -n dapr-system
```

---

## 3. Option A: Helm-only (no Argo CD)

Deploy the same components in dependency order with Helm. All in one namespace (e.g. `vizor`). From the **deploy repo root**:

```bash
NS=vizor
SA=vizor-runtime

# 1. Namespace
kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -

# 2. Redis (same as Argo: OCI chart or Bitnami with fullnameOverride)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade --install vizor-redis bitnami/redis \
  -n $NS --create-namespace \
  --set fullnameOverride=vizor-redis-master \
  --set auth.enabled=false \
  --set architecture=standalone \
  --set persistence.enabled=false

# 3. Secrets (must exist before data-init/identity)
helm upgrade --install vizor-secrets ./helm/vizor-secrets -n $NS \
  -f helm/vizor-secrets/values.yaml
# Override with dev secrets if needed:
#  -f helm/vizor/values-env/dev/secrets.yaml

# 4. Foundation (SA + Dapr components)
helm dependency update ./helm/vizor-foundation 2>/dev/null || true
helm upgrade --install vizor-foundation ./helm/vizor-foundation -n $NS \
  --set serviceAccount.name=$SA \
  -f helm/vizor-foundation/values.yaml

# 5. Mailhog (optional)
helm upgrade --install vizor-mailhog ./helm/vizor-mailhog -n $NS \
  -f helm/vizor-mailhog/values.yaml

# 6. Data-init (SQL Server + migrations job)
helm upgrade --install vizor-data-init ./helm/vizor-data-init -n $NS \
  --set serviceAccount.name=$SA \
  -f helm/vizor-data-init/values.yaml

# 7. Identity (Keycloak, jobs)
helm upgrade --install vizor-identity ./helm/vizor-identity -n $NS \
  --set serviceAccount.name=$SA \
  -f helm/vizor-identity/values.yaml
# Optional: -f helm/vizor/values-env/dev/identity.yaml

# 8. Platform-support (Caddy api-proxy)
helm upgrade --install vizor-platform-support ./helm/vizor-platform-support -n $NS \
  --set serviceAccount.name=$SA \
  -f helm/vizor-platform-support/values.yaml

# 9. SFTPGo (optional)
helm upgrade --install vizor-sftpgo ./helm/vizor-sftpgo -n $NS \
  --set serviceAccount.name=$SA \
  -f helm/vizor-sftpgo/values.yaml

# 10. Apps (wait for migrations; may need to re-run after migrations job completes)
helm upgrade --install vizor-apps ./helm/vizor-apps -n $NS \
  --set serviceAccount.name=$SA \
  -f helm/vizor-apps/values.yaml

# 11. Traffic (Ingress, HPA, observability)
helm upgrade --install vizor-traffic ./helm/vizor-traffic -n $NS \
  -f helm/vizor-traffic/values.yaml
```

**Notes:**

- **vizor-secrets**: Populate with dev credentials. Use `helm/vizor/values-env/dev/secrets.yaml` shape (or a local file) so the Secret has `connectionString`, `SA_PASSWORD`, Keycloak keys, etc.
- **Order**: Data-init creates SQL and the migrations Job; identity and apps depend on it. If apps come up before migrations complete, re-sync or wait and restart the apps release.
- **Images**: If your images are in a private registry, set `image.registry` / `image.pullSecrets` via `-f` or `--set`. Or load images into Kind and use a local tag.
- **Storage**: Foundation’s optional `local-path-provisioner` subchart needs `helm dependency update` in `helm/vizor-foundation` first; or disable it and rely on the default StorageClass in Kind.

You can turn the block above into a script (e.g. `scripts/deploy-local-kind.sh`) and add waits (e.g. for migrations Job or SQL Server) between steps if you want.

---

## 4. Option B: Argo CD in Kind (same as deployed env)

This replicates the **exact** setup: Argo CD + ApplicationSet + standalone Applications (redis, mailhog, sftpgo).

### 4.1 Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Available deploy/argocd-server -n argocd --timeout=300s
# Optional: expose UI
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
```

### 4.2 Bootstrap the root (dev) so Argo creates all apps

The apps are defined by the **root** Helm chart (`argocd/root/dev`). That chart templates:

- The ApplicationSet (generates the 7 child apps: secrets, foundation, data-init, identity, platform-support, apps, traffic)
- Standalone Applications: vizor-redis, vizor-mailhog, vizor-sftpgo

You need to **render** that root chart and apply the result, **or** register a single “root” Application that points at the root chart (app-of-apps).

**Option B1 – Apply rendered manifests (repo on disk):**

From the deploy repo root, with `argocd/root/dev` containing the chart and `values.yaml`:

```bash
helm template vizor-root ./argocd/root/dev -f ./argocd/root/dev/values.yaml \
  --namespace argocd | kubectl apply -n argocd -f -
```

That creates the ApplicationSet and the standalone Applications (vizor-redis, vizor-mailhog, vizor-sftpgo). The ApplicationSet will generate the seven apps. **Important:** Each generated app’s source is `repoURL` and `path` from the ApplicationSet. So the cluster (Argo CD) must be able to **pull from that repo**. If `repoURL` is `git@git.nbt.local:vizor/deploy.git`, then from inside the Kind cluster that host must be reachable (e.g. same network, or use a different repo URL for local such as a GitHub clone).

**Option B2 – Repo URL for local:**

If you use a **public or reachable Git URL** (e.g. GitHub), clone the deploy repo there and point the root’s `env.repoURL` and `env.targetRevision` at it. Then when you run the helm template above, use a values override that sets that URL:

```bash
helm template vizor-root ./argocd/root/dev \
  -f ./argocd/root/dev/values.yaml \
  -f /path/to/local-overrides.yaml \
  --namespace argocd | kubectl apply -n argocd -f -
```

In `local-overrides.yaml` set something like:

```yaml
env:
  repoURL: https://github.com/your-org/deploy.git   # or a URL Kind can reach
  targetRevision: main
  destinationNamespace: vizor
```

Then sync the generated apps in Argo CD (or enable auto-sync). Dapr must already be installed (step 2).

### 4.3 Summary for Option B

- Create Kind cluster and install Dapr.
- Install Argo CD.
- Render the **root** chart (`argocd/root/dev`) with values that use a **repo URL reachable from the cluster**.
- Apply the rendered manifests so the ApplicationSet and standalone apps exist.
- Ensure vizor-secrets (and any secret content) is present for the apps that need it (e.g. from values-env/dev or a local values file).

---

## 5. Port-forwarding and access (both options)

After the stack is up:

```bash
NS=vizor

# Caddy API gateway (main entry)
kubectl port-forward svc/api-proxy -n $NS 8080:80

# SQL Server
kubectl port-forward svc/sql-server-service -n $NS 1433:1433

# Keycloak
kubectl port-forward svc/keycloak -n $NS 8081:8080

# Mailhog Web UI
kubectl port-forward svc/mailhog -n $NS 8025:8025
```

If you use a local Ingress (e.g. with a Kind Ingress controller and `/etc/hosts`), you can point hosts (e.g. for Mailhog) at the cluster and skip some port-forwards.

---

## 6. Tear down

**Helm-only:**

```bash
helm uninstall vizor-traffic vizor-apps vizor-sftpgo vizor-platform-support \
  vizor-identity vizor-data-init vizor-mailhog vizor-foundation vizor-secrets -n vizor
helm uninstall vizor-redis -n vizor
```

**Argo CD:** Delete the ApplicationSet and Applications (or the whole `argocd` namespace), then uninstall Dapr if desired.

**Kind cluster:**

```bash
kind delete cluster --name vizor-dev
```

---

## Summary

| Goal                         | Approach   | When to use it                          |
|-----------------------------|------------|-----------------------------------------|
| Same resources, no Argo     | Option A   | Day-to-day local dev, fast redeploys   |
| Same GitOps flow as deployed| Option B   | Testing Argo/ApplicationSet/ordering   |

In both cases you get the same logical stack: Redis, vizor-secrets, foundation, data-init, identity, platform-support (Caddy), vizor-sftpgo, vizor-apps, vizor-traffic, and optionally Mailhog, with Dapr and a single namespace (`vizor`) for app workloads.
