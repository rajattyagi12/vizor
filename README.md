# Deployment of Dapr Store to Kubernetes

This is a brief guide to deploying Dapr Store to Kubernetes.

Assumptions:

- kubectl is installed, and configured to access your Kubernetes cluster
- dapr CLI is installed - https://docs.dapr.io/getting-started/install-dapr-cli/
- helm is installed - https://helm.sh/docs/intro/install/

This guide does not cover more advanced deployment scenarios such as deploying behind a DNS name, or with HTTPS enabled or with used identity enabled.

For more details see the [documentation for the Dapr Store Helm chart](./helm/vizor/readme.md)

## 🥾 Initial Setup

### Deploy Dapr to Kubernetes

### Add Helm repos

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add dapr https://dapr.github.io/helm-charts/
helm repo add local-path-provisioner https://charts.containeroo.ch/
helm repo update
```

## 🥾 Deploy Dapr control plane
Skip this if the Dapr control plane is already deployed

```bash
helm upgrade --install dapr dapr/dapr --version 1.16.1-rc.1 --namespace dapr-system --create-namespace --wait
kubectl get pod --namespace dapr-system
```

Full instructions here:
📃 https://docs.dapr.io/operations/hosting/kubernetes/kubernetes-overview/

### Optional - If you wish to view or check the Dapr dashboard

```bash
kubectl port-forward deploy/dapr-dashboard --namespace dapr-system 8080:8080
```
Open the dashboard at http://localhost:8080/


## Create namespace for Dapr Store app

```bash
namespace=vizor
kubectl create namespace $namespace
```


## 💾 Deploy Redis

```bash
# helm install dapr-redis bitnami/redis --values ./config/redis-values.yaml --namespace $namespace
kubectl apply -f ./config/redis.yaml
```

## 🚀 Ingress NGINX

```bash
helm install api-gateway ingress-nginx/ingress-nginx --values ./config/ingress-values.yaml --namespace $namespace
```

## 🚀 Deploy Vizor Apps

Now deploy the Vizor application and all services using Helm

```bash
helm install vizor ./helm/vizor --namespace $namespace
```

### 🚀 Port forwarding sqlserver service locally
```bash
nohup kubectl port-forward svc/sql-server-service 1433:1433 -n vizor &
```

### 🚀 Port forwarding for ingress controller service
```bash
nohup kubectl port-forward svc/api-gateway-ingress-nginx-controller -n vizor 8080:80 &
```
