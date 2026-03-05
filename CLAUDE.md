# Deploy (Vizor Helm/GitOps) — Claude Context

## Sibling Repo
This repo works together with **../kubespray** (`git@git.nbt.local:vizor/kubespray.git`).
- **kubespray owns**: K8s cluster, ArgoCD, Dapr, Traefik, cert-manager, `vizor-secrets` Secret
- **deploy owns**: Helm charts, ArgoCD ApplicationSets, app Helm values
- **Bridge**: kubespray's `argocd_vizor` role creates an ArgoCD Application pointing to THIS repo,
  and injects gateway config + namespace via `helm.valuesObject`

## Critical Dependency: vizor-secrets
The `vizor-secrets` Kubernetes Secret **must already exist** — it is created by kubespray's
`argocd_vizor` role, not by anything in this repo.
- **Contains**: SQL Server creds, SFTP creds + host key, Keycloak admin/DB passwords, SMTP, SSRS, Dapr secrets
- Deploy charts READ from this secret — they never create or modify it
- **If `vizor-secrets` is missing**: pods will fail to start with missing env var / secret errors
- To recreate: re-run kubespray `argocd_vizor` role

## Directory Structure
```
argocd/
  root/{dev,uat,prod}/    # ArgoCD App-of-Apps root charts per environment
helm/
  vizor/                  # Main aggregation chart (v0.8.1)
  vizor-apps/             # Application microservices
  vizor-data-init/        # DB schema + PowerBI initialization
  vizor-foundation/       # Dapr components + Secrets config
  vizor-identity/         # Keycloak
  vizor-mailhog/          # Email capture (dev/test only)
  vizor-platform-support/ # API proxy (Caddy)
  vizor-secrets/          # K8s Secret template (populated from kubespray values)
  vizor-sftpgo/           # SFTP server (dev in-cluster mode)
  vizor-traffic/          # Ingress/Gateway API + HPA autoscaling
config/                   # Shared Helm values (app, ingress, local, redis, sftpgo)
docs/                     # Deployment guides
scripts/                  # SQL initialization scripts (powerbi-init.sql)
live/                     # Personal deployment values (gitignored)
justfile                  # Task automation (Helm-only)
taskfile.yaml             # Go Task automation (alternative to justfile)
deploy.sh                 # Full automated deployment script
```

## Environments
| Env | Namespace | Branch | ArgoCD path | SFTP | Mailhog |
|---|---|---|---|---|---|
| dev | `vizor-dev` | `develop` | `argocd/root/dev` | In-cluster SFTPGo | Enabled |
| uat | `vizor-uat` | `uat` | `argocd/root/uat` | External | Optional |
| prod | `vizor-prod` | `prod` | `argocd/root/prod` | External (win2k5.nbt.local) | Disabled |

## Deployment Modes
1. **GitOps (ArgoCD)** — kubespray deploys ArgoCD and creates the root Application; this repo drives
   all changes via Git commits (auto-sync + prune enabled)
2. **Helm CLI** — `task deploy` / `just deploy` for manual dev installs (no ArgoCD required)
3. **Kind (local)** — see `docs/LOCAL_DEVELOPMENT_KIND.md` for full local GitOps or Helm-only flow

## Common Commands
```bash
# Activate dev environment
direnv allow

# Helm-only deploy (dev)
task deploy           # via taskfile.yaml
just deploy           # via justfile

# Full automated deploy (includes Kind cluster setup)
./deploy.sh

# Render Helm templates locally (for inspection/debugging)
helm template ./helm/vizor -f config/app-values.yaml

# ArgoCD sync (once kubespray has set up ArgoCD)
argocd app sync vizor-root-dev
argocd app sync vizor-root-uat

# Check ArgoCD app status
argocd app get vizor-root-dev
```

## Conventions
- **Secrets**: never store in this repo — all secrets come from `vizor-secrets` (kubespray-managed)
- **New app**: add a subchart under `helm/vizor/`, register in `argocd/root/*/values.yaml`
- **Gateway config** (name, namespace, listeners) is injected by kubespray via ArgoCD `valuesObject`
- Follow `helm/NAMING_CONTRACT.md` for chart/resource naming
- Follow `helm/VALIDATION_CHECKLIST.md` before releasing a chart change
- Ingress strategy (Traefik Gateway API vs Ingress): see `INGRESS_COMPARISON.md`

## Key Docs
- `README.md` — Quick start
- `argocd/README.md` — Multi-environment ArgoCD ApplicationSet architecture
- `docs/LOCAL_DEVELOPMENT_KIND.md` — Local Kind cluster setup guide
- `INGRESS_COMPARISON.md` / `ARGOCD_INGRESS_COMPARISON.md` — Ingress strategy notes
- `helm/NAMING_CONTRACT.md` — Chart naming rules
- `helm/VALIDATION_CHECKLIST.md` — Pre-release checklist
- `docs/DEV_TO_PROD_CARRYOVER.md` — Promoting changes across environments
