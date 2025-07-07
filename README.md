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

Skip this if the Dapr control plane is already deployed

```bash
dapr init --kubernetes
kubectl get pod --namespace dapr-system
```

Full instructions here:  
📃 https://docs.dapr.io/operations/hosting/kubernetes/kubernetes-overview/

Optional - If you wish to view or check the Dapr dashboard

```bash
kubectl port-forward deploy/dapr-dashboard --namespace dapr-system 8080:8080
```

Open the dashboard at http://localhost:8080/

### Create namespace for Dapr Store app

```bash
namespace=vizor
kubectl create namespace $namespace
```

### Add Helm repos

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
# helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

## 💾 Deploy Redis

```bash
helm install dapr-redis bitnami/redis --values ./config/redis-values.yaml --namespace $namespace
```

Validate & check status

```bash
helm list --namespace $namespace
kubectl get pod vizor-redis-master-0 --namespace $namespace
```

## 🌐 Deploy k8s Gateway API


Install Gateway API CRDs

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
```
Validate Gateway API CRDs

```bash
kubectl get crd | grep gateway
```

Install MetalLB CRDs

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
```

Validate MetalLB is running

```bash
kubectl get pods -n metallb-system
```

Then setup localLB
```bash
./metal-lb.sh
```

## 🚀 Deploy Dapr Store

Now deploy the Dapr Store application and all services using Helm

```bash
helm install vizor ./helm/vizor --namespace $namespace
```

Validate & check status

```bash
helm list --namespace $namespace
kubectl get pod -l app.kubernetes.io/instance=vizor-apps --namespace $namespace
```

To get the URL of the deployed store run the following command:

```bash
echo -e "Access Dapr Store here: http://$(kubectl get svc -l "purpose=vizor-api-gateway" -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")/"
```



Ingress NGINX

```bash
helm install api-gateway ingress-nginx/ingress-nginx --values ./config/ingress-values.yaml --namespace $namespace
```