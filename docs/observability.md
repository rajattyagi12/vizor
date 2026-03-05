# Observability — App Instrumentation Guide

> **Audience**: Developers adding new services or debugging observability for existing ones.
> For the full SRE infrastructure reference, see `kubespray/docs/observability.md`.

---

## What's Automatically Available

Once the cluster is running with observability enabled:

| Signal | Collection | Where to view |
|---|---|---|
| **Traces** | Dapr sidecar → Jaeger (via OTLP) | `https://observability.k8s.nbt.local` |
| **Metrics** | Prometheus scrapes Dapr sidecar `:9090` | Grafana → Dashboards → Dapr |
| **Logs** | Grafana Alloy collects all pod stdout/stderr | Grafana → Explore → Loki |

Logs and metrics are collected **automatically** from all pods. Traces require two annotations on the pod.

---

## Enabling Traces for a Dapr-enabled Service

### Required annotations (add to your Deployment's pod template)

```yaml
spec:
  template:
    metadata:
      annotations:
        dapr.io/enabled: "true"
        dapr.io/app-id: "my-service"      # must be unique cluster-wide
        dapr.io/app-port: "8080"
        dapr.io/config: "tracing"         # ← connects to Jaeger via Dapr Configuration CR
        dapr.io/log-as-json: "true"       # ← recommended: structured logs for Loki
```

### How it works

```
Pod starts
  └─▶ Dapr injector adds sidecar (dapr.io/enabled: "true")
        └─▶ Sidecar reads Configuration CR named "tracing" in same namespace
              └─▶ CR points to: collector.observability.svc.cluster.local:4317
                    └─▶ Dapr sends OTLP spans to Jaeger collector
                          └─▶ Traces visible in Jaeger UI
```

The `tracing` Configuration CR is deployed per-environment by the `vizor-foundation` Helm chart.
It exists in `vizor-dev`, `vizor-uat`, and `vizor-prod` automatically.

### Current services with tracing enabled

| Service | Helm chart | dapr.io/app-id | Tracing annotation |
|---|---|---|---|
| core-service | `vizor-apps` | `core-service` | ✅ `dapr.io/config: tracing` |
| engagement-service | `vizor-apps` | `engagement-service` | ✅ `dapr.io/config: tracing` |
| interaction-service | `vizor-apps` | `interaction-service` | ✅ `dapr.io/config: tracing` |
| api-proxy (Caddy) | `vizor-platform-support` | `api-proxy` | ✅ via `OTEL_EXPORTER_OTLP_ENDPOINT` |
| Keycloak | `vizor-identity` | — (no Dapr) | Metrics via Prometheus scrape |

---

## Enabling Metrics for a Non-Dapr Service

For services without a Dapr sidecar, annotate the pod for Prometheus scraping:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"      # port that exposes /metrics
  prometheus.io/path: "/metrics"  # path (default is /metrics)
```

Prometheus will automatically scrape the endpoint on the next scrape interval (15s).

---

## Querying Logs in Grafana

Navigate to **Grafana → Explore → Loki datasource**.

### Useful LogQL queries

```logql
# All logs from a namespace
{namespace="vizor-dev"}

# Logs from a specific service
{namespace="vizor-dev", app="core-service"}

# Logs from Dapr sidecar only
{namespace="vizor-dev", container="daprd"}

# Error logs across all services
{namespace="vizor-dev"} |= "error"

# Structured JSON log field filter (when dapr.io/log-as-json: "true")
{namespace="vizor-dev"} | json | level="error"

# Count error rate per service over 5m
sum by (app) (rate({namespace="vizor-dev"} |= "error" [5m]))
```

---

## Querying Traces in Jaeger

Navigate to **`https://observability.k8s.nbt.local`**.

- **Service**: select from dropdown (e.g., `core-service`, `engagement-service`, `traefik`)
- **Operation**: filter by specific operation/endpoint
- **Tags**: filter by HTTP status, error, etc.
- **Lookback**: time range (last 1h, 6h, etc.)

Traces show the full call graph across Dapr service invocations, including latency at each hop.

You can also view traces in **Grafana → Explore → Jaeger datasource**.

---

## Querying Metrics in Grafana

Navigate to **Grafana → Dashboards** for pre-built views, or **Explore → Prometheus** for ad-hoc queries.

### Useful PromQL queries

```promql
# Dapr sidecar HTTP request rate (per app, per namespace)
rate(dapr_http_server_request_count{namespace="vizor-dev"}[5m])

# Dapr service invocation latency p99
histogram_quantile(0.99,
  rate(dapr_http_server_latency_bucket{namespace="vizor-dev"}[5m])
)

# Pod CPU usage by service
rate(container_cpu_usage_seconds_total{namespace="vizor-dev", container!=""}[5m])

# Pod memory usage
container_memory_working_set_bytes{namespace="vizor-dev", container!=""}

# Keycloak active sessions
keycloak_active_sessions
```

---

## Dapr Configuration CR Reference

The `tracing` Configuration CR (managed by `vizor-foundation` Helm chart):

```yaml
apiVersion: dapr.io/v1alpha1
kind: Configuration
metadata:
  name: tracing
  namespace: <release-namespace>   # vizor-dev, vizor-uat, or vizor-prod
spec:
  tracing:
    samplingRate: "1"              # 100% sampling — all spans captured
    otel:
      endpointAddress: "collector.observability.svc.cluster.local:4317"
      protocol: grpc
      isSecure: false
```

To verify it exists in your environment:
```bash
kubectl get configuration tracing -n vizor-dev -o yaml
```

---

## Caddy API Gateway Tracing

The Caddy gateway (`vizor-platform-support`) sends traces via OpenTelemetry using the env var:

```yaml
OTEL_EXPORTER_OTLP_ENDPOINT: "http://collector.observability.svc.cluster.local:4317"
OTEL_EXPORTER_OTLP_INSECURE: "true"
```

This is configurable via `helm/vizor-platform-support/values.yaml`:
```yaml
tracing:
  enabled: true
  otlpEndpoint: "http://collector.observability.svc.cluster.local:4317"
```

---

## Troubleshooting

### Traces not showing for my service

1. Check the pod has `dapr.io/config: tracing` annotation:
   ```bash
   kubectl get pod <pod> -n vizor-dev -o jsonpath='{.metadata.annotations}' | python3 -m json.tool
   ```

2. Verify the Dapr Configuration CR exists:
   ```bash
   kubectl get configuration tracing -n vizor-dev
   ```

3. Check Dapr sidecar logs:
   ```bash
   kubectl logs <pod> -n vizor-dev -c daprd | grep -i "trace\|otel"
   ```

4. Confirm Jaeger is up:
   ```bash
   kubectl get pods -n jaeger
   ```

### My service logs aren't appearing in Loki

Logs are collected from **all pods automatically**. If missing:

1. Confirm Grafana Alloy DaemonSet is running:
   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/name=alloy
   ```

2. Try a broader query with just the namespace:
   ```logql
   {namespace="vizor-dev"}
   ```

3. Check the time range in Grafana (default is "Last 1 hour").

### My Prometheus metrics aren't showing

For Dapr-enabled services, metrics are scraped automatically (no annotation needed).

1. Confirm the Dapr sidecar is running (metrics exposed on `:9090`):
   ```bash
   kubectl exec <pod> -n vizor-dev -c daprd -- wget -qO- localhost:9090/metrics | head -3
   ```

2. For non-Dapr services, check the `prometheus.io/scrape: "true"` annotation is present.
