# RCA: api-proxy Dapr sidecar – statestore init failure (Redis unreachable)

## Symptom

api-proxy pods crash with Dapr runtime fatal error:

```
level=fatal msg="Fatal error from runtime: process component statestore error: [INIT_COMPONENT_FAILURE]: initialization error occurred for statestore (state.redis/v1): ... redis store: error connecting to redis at vizor-redis-master:6379: dial tcp: lookup vizor-redis-master on 169.254.25.10:53: no such host
```

## Sync waves and deployment order (verified)

Order is **correct** relative to in-repo apps:

| Wave | App                    | Relevant resources |
|------|------------------------|--------------------|
| -2    | vizor-secrets          | Secret `vizor-secrets` |
| -2    | vizor-foundation       | Dapr Components (secretstore, **state**, pubsub), SA, job-reader RBAC |
| -1    | vizor-data-init        | SQL Server, migrations-job |
| 0     | vizor-identity         | mssql-init-job, Keycloak, realm/user-sync jobs |
| 1     | vizor-platform-support | **api-proxy** (Caddy), mailhog, sftpgo |
| 2     | vizor-apps             | core, engagement, interaction, frontend |
| 3     | vizor-traffic-autoscale | Ingress, HPA |

- Foundation (wave -2) creates the Dapr **Component** resources (including `statestore` with `redisHost: vizor-redis-master:6379`) **before** platform-support (wave 1) deploys api-proxy.
- So the statestore component **exists** when api-proxy’s Dapr sidecar starts; the sidecar then tries to **connect** to Redis using that component’s metadata.

So the failure is **not** due to sync order (e.g. api-proxy starting before foundation or before the Dapr component exists). The component is present; the failure is when connecting to Redis.

## Root cause

The error is from **cluster DNS**: `lookup vizor-redis-master on ... :53: no such host`.

So:

1. **Redis is not deployed** in the cluster, or  
2. **Redis is in another namespace**: the hostname `vizor-redis-master` is a short name and resolves only inside the **same namespace** as the pod. If Redis runs in another namespace (e.g. `redis`), the lookup in the vizor namespace fails unless you use the FQDN, e.g. `vizor-redis-master.redis.svc.cluster.local:6379`, or  
3. **Service name differs**: the Redis service might have a different name (e.g. `redis-master`).

When using the Argo CD app-of-apps, **Redis is deployed by vizor-foundation** (CloudPirates OSS Redis subchart; `redis.enabled: true` in the foundation layer) with service name `vizor-redis-master`. If Redis is disabled in foundation or you deploy without Argo, Redis is an external prerequisite (e.g. via `deploy.sh` or another Redis Helm chart in the same namespace).

## Conclusion

- **Sync waves / deployment order:** Correct; no change needed for wave ordering.
- **Root cause:** Redis is either missing or not resolvable from the vizor namespace (not deployed, or in another namespace without FQDN).

## Recommendations

1. **Use foundation-deployed Redis** (default): ensure `redis.enabled: true` in the foundation layer so vizor-foundation deploys Redis (CloudPirates chart) with service `vizor-redis-master`. Or **deploy Redis in the same namespace as Vizor** with service name `vizor-redis-master` if you disabled Redis in foundation.
2. **If Redis is in another namespace:** set `daprComponents.state.redisHost` and `daprComponents.pubsub.redisHost` in foundation values to the **FQDN**, e.g. `vizor-redis-master.<redis-namespace>.svc.cluster.local:6379`.
3. **Document** Redis (and Dapr control plane) as prerequisites in the Argo CD README or deploy docs so operators deploy them before or with Vizor.
