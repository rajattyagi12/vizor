# Ingress Settings Comparison: `old_code` vs `caddy-ingress`

## Summary
**All ingress-related files are IDENTICAL between both branches.** No differences were found in ingress configurations.

## Files Compared

### 1. `helm/vizor/templates/ingress-rules.yaml`
**Status:** ✅ **IDENTICAL** in both branches

Both branches use the same Kubernetes Ingress resource with:
- **Ingress Controller:** nginx-ingress
- **Annotations:** All nginx-specific annotations are the same:
  - WebSocket support enabled
  - Proxy timeouts: 3600s
  - Session affinity with cookies
  - Client max body size: 100m
  - SSL redirect based on TLS configuration

- **TLS Configuration:** Same conditional TLS setup based on `certIssuer` or `certName`

- **Routing Paths:** Identical path configurations:
  - `/auth` → keycloak:8080
  - `/v1.0/invoke` → api-proxy-dapr:80 (Dapr service invocation)
  - `/chathub` → interaction-service-dapr:80 (SignalR)
  - `/` → vizor-frontend:8000 (SPA frontend)

### 2. `config/ingress-values.yaml`
**Status:** ✅ **IDENTICAL** in both branches

Both branches contain the same nginx-ingress Helm chart values:
- Controller service labels: `purpose: "vizor-api-gateway"`
- Ingress class: `nginx`
- Dapr annotations:
  - `dapr.io/enabled: "true"`
  - `dapr.io/app-id: "api-gateway"`
  - `dapr.io/app-port: "80"`
  - `dapr.io/sidecar-listen-addresses: "0.0.0.0"`
- Namespace scoping enabled

### 3. `live/ingress-values.yaml`
**Status:** ✅ **IDENTICAL** in both branches

Both branches have the same live/production values:
- Load balancer IP: `20.254.189.197` (static IP)
- Ingress class: `dapr` (note: different from config/ingress-values.yaml which uses `nginx`)
- Same Dapr annotations as config file
- Namespace scoping enabled

### 4. `helm/vizor/templates/caddy-api-gateway.yaml`
**Status:** ✅ **IDENTICAL** in both branches

Both branches contain the same Caddy deployment configuration:
- Deployment name: `api-proxy`
- Namespace: `vizor`
- Image: `caddy:latest`
- Dapr annotations:
  - `dapr.io/enabled: "true"`
  - `dapr.io/app-id: "api-proxy"`
  - `dapr.io/app-port: "80"`
  - `dapr.io/sidecar-listen-addresses: "0.0.0.0"`
  - `dapr.io/max-body-size: "4Mi"`
- OpenTelemetry tracing configured
- Resources: 100m CPU / 128Mi memory (requests), 250m CPU / 256Mi memory (limits)
- ConfigMap volume mount for Caddyfile

### 5. `helm/vizor/templates/caddy-cm.yaml`
**Status:** ✅ **IDENTICAL** in both branches

Both branches have the same Caddy ConfigMap:
- ConfigMap name: `caddy-config`
- Caddyfile configuration:
  - Listens on port 80
  - DEBUG level logging to stdout
  - Routes `/v1.0/invoke/{service}/method/*` to `{service}-dapr:3500`
  - Health check endpoint: `/health` returns "OK"
  - Tracing enabled

## Key Observations

1. **No Ingress Differences:** Despite the branch name "caddy-ingress", there are no differences in ingress-related configurations between the two branches.

2. **Dual Gateway Setup:** Both branches maintain:
   - **nginx-ingress** as the main ingress controller (via Ingress resource)
   - **Caddy** as an API proxy/gateway (via Deployment) for Dapr service invocations

3. **Caddy Configuration:** The Caddy setup in both branches:
   - Handles Dapr service invocation routing (`/v1.0/invoke/{service}/method/*`)
   - Is Dapr-enabled with sidecar annotations
   - Has OpenTelemetry tracing configured

4. **Ingress Class Discrepancy:** 
   - `config/ingress-values.yaml` uses `ingressClass: "nginx"`
   - `live/ingress-values.yaml` uses `ingressClass: "dapr"`
   - This discrepancy exists in both branches

## Conclusion

The `caddy-ingress` branch does not contain any changes to ingress settings compared to `old_code`. All ingress-related files are identical. The branch name suggests it was intended for Caddy-related ingress changes, but those changes are not present in the current state of the branch.

