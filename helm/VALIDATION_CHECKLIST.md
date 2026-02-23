# Separate charts – validation checklist

## Helm template (per chart)

Run from repo root. Use namespace and SA param matching your Argo env (e.g. `vizor` / `vizor-runtime` or `vizor-apps` / `vizor-apps-runtime`).

```bash
NS=vizor SA=vizor-runtime
helm template vizor-data-init    helm/vizor-data-init    -n $NS --set serviceAccount.name=$SA -f helm/vizor-data-init/values.yaml    > /dev/null && echo data-init OK
helm template vizor-identity      helm/vizor-identity     -n $NS --set serviceAccount.name=$SA -f helm/vizor-identity/values.yaml     > /dev/null && echo identity OK
helm template vizor-platform-support helm/vizor-platform-support -n $NS --set serviceAccount.name=$SA -f helm/vizor-platform-support/values.yaml > /dev/null && echo platform-support OK
helm template vizor-sftpgo        helm/vizor-sftpgo       -n $NS --set serviceAccount.name=$SA -f helm/vizor-sftpgo/values.yaml       > /dev/null && echo sftpgo OK
helm template vizor-apps          helm/vizor-apps         -n $NS --set serviceAccount.name=$SA -f helm/vizor-apps/values.yaml        > /dev/null && echo apps OK
helm template vizor-traffic       helm/vizor-traffic      -n $NS -f helm/vizor-traffic/values.yaml > /dev/null && echo traffic OK
helm template vizor-mailhog       helm/vizor-mailhog      -n $NS -f helm/vizor-mailhog/values.yaml  > /dev/null && echo mailhog OK
```

**vizor-foundation** requires the `local-path-provisioner` subchart. Either run `helm dependency update` in `helm/vizor-foundation` (with network), or deploy foundation with the monolith vizor chart and foundation layer until the subchart is available.

## Values coverage (no nil dereference)

| Chart | Key values | Notes |
|-------|------------|-------|
| vizor-data-init | global.*, sqlServer.*, image.*, serviceAccount.* | All present in values.yaml |
| vizor-identity | global.*, sqlServer.service, keycloak.*, keycloakRealmConfiguration.*, image.*, serviceAccount.* | All present |
| vizor-platform-support | global.*, apiProxy, serviceAccount.*, scheduling.* | Caddy only; Mailhog/SFTPGo are standalone |
| vizor-sftpgo | global.secretName, serviceAccount.*, image.*, service.*, config, description, env, persistence, daprComponent.* | env: [] |
| vizor-apps | global.*, image.*, resources, auth.clientId, *Service.replicas/annotations, interactionService.redisConnectionString, serviceAccount.* | All present |
| vizor-traffic | global.serviceNames, ingress.*, autoscaling.*, observability.enabled | All present (Mailhog ingress is in vizor-mailhog) |
| vizor-foundation | global.*, serviceAccount.*, daprComponents.*, persistence.*, local-path-provisioner.* | All present |

## Argo CD

- **dev/uat/prod** ApplicationSet: chart paths are `helm/vizor-foundation`, `helm/vizor-data-init`, etc. valueFiles for new charts use `values.yaml` (chart default) and optional `appEnvValuesFile` (e.g. `../vizor/values-env/dev/foundation.yaml`).
- **serviceAccount.name** is passed as Helm param from `derivedServiceAccountName` (e.g. `vizor-runtime` when `destinationNamespace` is `vizor`).
- **templatePatch** for vizor-traffic-autoscale: adds ingress.* and serviceAccount.name params.

## Naming contract

- All charts use `global.secretName`, `global.serviceAccountName`, and (where needed) `global.serviceNames.*`, `global.migrationsJobName`.
- No template uses `include "vizor.*"` (only chart-specific helpers).
- Resource names (Secret, SA, Job, Services) match [NAMING_CONTRACT.md](NAMING_CONTRACT.md).

## Namespaces

- All resources (except observability stack) use `{{ .Release.Namespace }}`.
- Observability (Loki, Grafana, Promtail) use hardcoded `observability` namespace; ensure that namespace exists or is created by the chart (loki-deployment creates the Namespace when observability.enabled).

## Optional

- **vizor-foundation:** Run `helm dependency update` and commit `charts/` if you want the chart to be fully self-contained.
- **Env overlays:** Ensure `helm/vizor/values-env/{dev,uat,prod}/*.yaml` exist for any app that uses `appEnvValuesFile` (e.g. dev foundation, data-init, identity, platform-support, apps, traffic-autoscale).
