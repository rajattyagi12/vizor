# Dapr Store Helm Chart

![Version: 0.8.3](https://img.shields.io/badge/Version-0.8.3-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.8.3](https://img.shields.io/badge/AppVersion-0.8.3-informational?style=flat-square)

A reference application showcasing the use of Dapr

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| auth.clientId | string | `nil` | Set this to enable authentication, leave unset to run in demo mode |
| core.annotations | string | `nil` | Dapr store core annotations |
| core.replicas | int | `1` | Dapr store core replica count |
| daprComponents.deploy | bool | `true` | Enable to deploy the Dapr components |
| daprComponents.pubsub.name | string | `"pubsub"` | Dapr pubsub component name |
| daprComponents.pubsub.redisHost | string | `"vizor-redis-master:6379"` | Hostname of Redis (foundation deploys CloudPirates Redis with fullnameOverride: vizor-redis-master) |
| daprComponents.state.name | string | `"statestore"` | Dapr state store component name |
| daprComponents.state.redisHost | string | `"vizor-redis-master:6379"` | Hostname of Redis (foundation deploys CloudPirates Redis with fullnameOverride: vizor-redis-master) |
| frontendHost.annotations | string | `nil` | Dapr store frontend host annotations |
| frontendHost.replicas | int | `1` | Dapr store frontend host replica count |
| image.pullSecrets | list | `[]` | Any pullsecrets that are required to pull the image |
| image.registry | string | `"harbor.nbt.local"` | Image registry, only change if you're using your own images |
| image.repo | string | `"benc-uk/vizor"` | Image repository |
| image.tag | string | `"latest"` | Image tag |
| ingress.certIssuer | string | `nil` | Cert manager issuer, leave unset to run in insecure mode |
| ingress.certName | string | `nil` | Set this to enable TLS, leave unset to run in insecure mode |
| ingress.host | string | `nil` | Ingress host DNS name |
| engagement.annotations | string | `nil` | Dapr store engagement annotations |
| engagement.replicas | int | `1` | Dapr store engagement replica count |
| interaction.annotations | string | `nil` | Dapr store interaction annotations |
| interaction.replicas | int | `1` | Dapr store interaction replica count |
| resources.limits.cpu | string | `"100m"` | CPU limit for the containers, leave alone mostly |
| resources.limits.memory | string | `"200M"` | Memory limit for the containers, leave alone mostly |
| users.annotations | string | `nil` | Dapr store users annotations |
| users.replicas | int | `1` | Dapr store users replica count |

