# ArgoCD Deployment with Caddy Built-in Ingress

This guide explains how to deploy Vizor on ArgoCD using Caddy's built-in ingress capabilities **without requiring nginx ingress controller**.

## Overview

Instead of using nginx ingress controller, Caddy (the API Gateway) handles all routing directly:
- Caddy listens on the hostname `vizor.k8s.nbt.local`
- Caddy routes all traffic internally:
  - `/auth*` → keycloak:8080
  - `/v1.0/invoke/*` → Dapr sidecar
  - `/chathub*` → interaction-service:8080
  - `/*` → frontend:8000
- The `api-proxy` service is exposed as LoadBalancer (or NodePort)

## Configuration

### Option 1: Use Pre-configured Values File

Use the provided values file: `config/argocd-caddy-values.yaml`

```yaml
# In your ArgoCD Application manifest
spec:
  source:
    helm:
      valueFiles:
      - config/argocd-caddy-values.yaml
```

### Option 2: Override Values in ArgoCD

Set these values in your ArgoCD Application:

```yaml
spec:
  source:
    helm:
      values: |
        ingress:
          enabled: false
          host: vizor.k8s.nbt.local
        
        apiProxy:
          serviceType: LoadBalancer
          # Optional: Set static IP if available
          # loadBalancerIP: "20.254.189.197"
```

## Key Configuration Values

| Value | Description | Default |
|-------|-------------|---------|
| `ingress.enabled` | **Must be `false`** to use Caddy's built-in ingress | `false` |
| `ingress.host` | Hostname Caddy will use for routing | `vizor.k8s.nbt.local` |
| `apiProxy.serviceType` | Service type: `LoadBalancer` (recommended) or `NodePort` | `LoadBalancer` |
| `apiProxy.loadBalancerIP` | Optional: Static IP for LoadBalancer | `""` |
| `apiProxy.nodePort` | Port for NodePort (only if serviceType=NodePort) | `30080` |

## Deployment Steps

1. **Update ArgoCD Application** with the values above

2. **Sync the Application** in ArgoCD UI or CLI:
   ```bash
   argocd app sync vizor
   ```

3. **Get the LoadBalancer IP**:
   ```bash
   kubectl get svc api-proxy -n vizor
   ```

4. **Configure DNS**:
   - Point `vizor.k8s.nbt.local` to the LoadBalancer IP
   - Or add to `/etc/hosts` for local testing:
     ```
     <loadbalancer-ip>  vizor.k8s.nbt.local
     ```

5. **Access the Application**:
   - URL: `http://vizor.k8s.nbt.local`
   - All routing is handled by Caddy internally

## How It Works

```
Internet/User
    ↓
LoadBalancer Service (api-proxy)
    ↓
Caddy API Gateway (listening on vizor.k8s.nbt.local)
    ↓
Internal Routing:
  - /auth* → keycloak:8080
  - /v1.0/invoke/* → Dapr sidecar
  - /chathub* → interaction-service:8080
  - /* → frontend:8000
```

## Benefits

✅ **No nginx ingress controller required**
✅ **Simpler architecture** - Caddy handles everything
✅ **Built-in TLS support** - Caddy can auto-generate certificates
✅ **WebSocket support** - Native support for SignalR
✅ **Direct routing** - No extra hop through ingress controller

## Troubleshooting

### Service Not Getting External IP

```bash
# Check service status
kubectl get svc api-proxy -n vizor

# Check events
kubectl describe svc api-proxy -n vizor
```

### Caddy Not Routing Correctly

```bash
# Check Caddy configuration
kubectl get configmap caddy-config -n vizor -o yaml

# Check Caddy logs
kubectl logs -n vizor -l app=api-proxy -c caddy
```

### DNS Not Resolving

```bash
# Test from within cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup vizor.k8s.nbt.local

# Check if hostname is configured in Caddy
kubectl exec -n vizor -l app=api-proxy -c caddy -- cat /etc/caddy/Caddyfile | grep vizor.k8s.nbt.local
```

## Comparison: nginx Ingress vs Caddy Built-in

| Feature | nginx Ingress | Caddy Built-in |
|---------|---------------|----------------|
| Requires Ingress Controller | ✅ Yes | ❌ No |
| External Service | LoadBalancer | LoadBalancer/NodePort |
| Hostname Routing | Via Ingress | Via Caddyfile |
| TLS Support | Via cert-manager | Built-in (auto) |
| WebSocket Support | ✅ Yes | ✅ Yes (native) |
| Complexity | Higher | Lower |

## Next Steps

1. Deploy using ArgoCD with the values file
2. Get the LoadBalancer IP
3. Configure DNS to point to the IP
4. Access `http://vizor.k8s.nbt.local`

