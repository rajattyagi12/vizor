# ArgoCD Ingress Mapping Comparison: `caddy-ingress` vs `old_code`

## Overview
This document compares the ArgoCD deployment mappings between the `caddy-ingress` and `old_code` branches based on the ArgoCD UI screenshots.

## Key Differences

### 1. Ingress Components

#### `caddy-ingress` Branch:
- ✅ **`vizor-ingress-rules`** - Present and connected to `172.16.0.30`
  - Routes traffic to:
    - `/auth` → `keycloak:8080`
    - `/v1.0/invoke` → `api-proxy-dapr:80`
    - `/chathub` → `interaction-service-dapr:80`
    - `/` → `vizor-frontend:8000`
- ✅ **`mailhog-ingress`** - Present

#### `old_code` Branch:
- ❌ **`vizor-ingress-rules`** - **NOT PRESENT** (This is a major difference!)
- ✅ **`mailhog-ingress`** - Present

### 2. Services Deployed

#### `caddy-ingress` Branch Services:
- ✅ `keycloak` (port 8080) - **Present**
- ✅ `vizor-frontend` (port 8000) - **Present**
- ✅ `interaction-service-dapr` (port 80)
- ✅ `interaction-service`
- ✅ `vizor-interaction-service`
- ✅ `core-service-dapr` (port 80)
- ✅ `vizor-core-service`
- ✅ `api-proxy` (connected to `172.16.0.31`)
- ✅ `api-proxy-dapr` (connected to `172.16.0.31`)
- ✅ `mailhog`

#### `old_code` Branch Services:
- ❌ `keycloak` - **NOT PRESENT**
- ❌ `vizor-frontend` - **NOT PRESENT**
- ✅ `interaction-service-dapr` (port 80)
- ✅ `interaction-service`
- ✅ `vizor-interaction-service`
- ✅ `core-service-dapr` (port 80)
- ✅ `engagement-service-dapr` (port 80) - **Present in old_code, not visible in caddy-ingress**
- ✅ `api-proxy` (connected to `172.16.0.31`)
- ✅ `api-proxy-dapr` (connected to `172.16.0.31`)
- ✅ `mailhog`

### 3. Pods Deployed

#### `caddy-ingress` Branch Pods:
- ✅ `api-proxy-856fd5b758-6cxrp` (2/2 replicas running)
- ✅ `mailhog-8587d4997-jt268` (1/1 replicas running)
- ✅ `vizor-interaction-service-84d4...` (2/2 replicas running)
- ✅ `keycloak-dcf66b599-4xhfm` (1/1 replicas running) - **Present**
- ✅ `vizor-frontend-5dbdf69fcc-k5...` (1/1 replicas running) - **Present**
- ✅ `vizor-core-service-b8dcb4c4d...` (2/2 replicas running)

#### `old_code` Branch Pods:
- ✅ `api-proxy-856fd5b758-6cxrp` (2/2 replicas running)
- ✅ `mailhog-8587d4997-jt268` (1/1 replicas running)
- ✅ `vizor-interaction-service-84d4...` (2/2 replicas running)
- ❌ `keycloak-*` - **NOT PRESENT**
- ❌ `vizor-frontend-*` - **NOT PRESENT**
- ✅ `vizor-core-service-b8dcb4c4d...` (2/2 replicas running)
- ✅ `vizor-engagement-service-7f4...` (2/2 replicas running) - **Present in old_code**

## Network Flow Comparison

### `caddy-ingress` Branch:
```
External (Cloud)
  ├─ 172.16.0.31 (brown)
  │   ├─ api-proxy (SVC)
  │   └─ api-proxy-dapr (SVC)
  │       └─ api-proxy-856fd5b758-6cxrp (Pod)
  │
  └─ 172.16.0.30 (blue)
      ├─ mailhog-ingress (ING)
      │   └─ mailhog (SVC) → mailhog-8587d4997-jt268 (Pod)
      │
      └─ vizor-ingress-rules (ING) ⭐
          ├─ keycloak (SVC) → keycloak-dcf66b599-4xhfm (Pod)
          ├─ api-proxy-dapr (SVC) → api-proxy-856fd5b758-6cxrp (Pod)
          ├─ interaction-service-dapr (SVC) → vizor-interaction-service-84d4... (Pod)
          └─ vizor-frontend (SVC) → vizor-frontend-5dbdf69fcc-k5... (Pod)
```

### `old_code` Branch:
```
External (Cloud)
  ├─ 172.16.0.31 (purple)
  │   ├─ api-proxy (SVC)
  │   └─ api-proxy-dapr (SVC)
  │       └─ api-proxy-856fd5b758-6cxrp (Pod)
  │
  └─ 172.16.0.30 (yellow)
      └─ mailhog-ingress (ING)
          └─ mailhog (SVC) → mailhog-8587d4997-jt268 (Pod)

  ⚠️ NO vizor-ingress-rules ingress!
  ⚠️ NO keycloak service/pod!
  ⚠️ NO vizor-frontend service/pod!
  ✅ engagement-service-dapr (SVC) → vizor-engagement-service-7f4... (Pod)
```

## Summary of Critical Differences

| Component | caddy-ingress | old_code | Impact |
|-----------|---------------|----------|--------|
| **vizor-ingress-rules** | ✅ Present | ❌ Missing | **CRITICAL** - No main ingress routing |
| **keycloak** service/pod | ✅ Present | ❌ Missing | **CRITICAL** - No authentication service |
| **vizor-frontend** service/pod | ✅ Present | ❌ Missing | **CRITICAL** - No frontend application |
| **engagement-service-dapr** | ❓ Not visible | ✅ Present | May be present but not visible in screenshot |
| **mailhog-ingress** | ✅ Present | ✅ Present | Same in both |

## Ingress Configuration Analysis

### Why `vizor-ingress-rules` is Missing in `old_code`:

Even though the `ingress-rules.yaml` template file exists in both branches and is identical, the ingress is not deployed in `old_code`. This could be due to:

1. **Helm values differences** - The ingress might be conditionally disabled in values.yaml
2. **ArgoCD sync status** - The ingress might not be synced/deployed in the old_code environment
3. **Template conditions** - There might be conditional logic preventing deployment (though none found in the template)
4. **Missing dependencies** - The ingress references `keycloak` and `vizor-frontend` services which are also missing, suggesting these components might be disabled together

### Ingress Paths in `caddy-ingress` (when deployed):

1. **`/auth`** → `keycloak:8080` - Keycloak authentication
2. **`/v1.0/invoke`** → `api-proxy-dapr:80` - Dapr service invocation API
3. **`/chathub`** → `interaction-service-dapr:80` - SignalR chat hub
4. **`/`** → `vizor-frontend:8000` - Frontend SPA (catch-all)

## Conclusion

The `caddy-ingress` branch has a **complete ingress setup** with:
- Main ingress controller (`vizor-ingress-rules`)
- Authentication service (Keycloak)
- Frontend application (vizor-frontend)
- All routing paths configured

The `old_code` branch is **missing critical components**:
- No main ingress controller
- No authentication service
- No frontend application
- Only has API proxy and mailhog ingress

This suggests that `caddy-ingress` is a more complete/production-ready configuration, while `old_code` appears to be a minimal/development setup without frontend and authentication components.

