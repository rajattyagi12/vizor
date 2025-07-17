# justfile for deploying Dapr Store to Kubernetes with readiness checks

# Set the namespace for deployment
namespace := "vizor"

# Check that Kubernetes cluster is accessible and has at least 2 Ready nodes
check-cluster:
    #! /usr/bin/env nix-shell
    #! nix-shell -i bash -p bash
    echo "🔍 Checking Kubernetes cluster access and node count..."
    kubectl version || { echo "❌ kubectl not configured properly or cluster unreachable."; exit 1; }
    count=$(kubectl get nodes --no-headers | grep -c " Ready")
    if [ "$count" -lt 2 ]; then
        echo "❌ Cluster does not have at least 2 Ready nodes (found $count)"
        exit 1
    else
        echo "✅ Cluster is accessible and has $count Ready nodes."
    fi


# 🥾 Initial Setup
install-deps:
    @echo "🔧 Adding Helm repos..."
    @helm repo list | grep -q "bitnami" || helm repo add bitnami https://charts.bitnami.com/bitnami
    @helm repo list | grep -q "ingress-nginx" || helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    @helm repo list | grep -q "dapr" || helm repo add dapr https://dapr.github.io/helm-charts/
    helm repo update

deploy-dapr:
    @echo "🚀 Deploying Dapr control plane..."
    helm upgrade --install dapr dapr/dapr --namespace dapr-system --create-namespace --wait
    echo "⏳ Waiting for Dapr control plane pods to be ready..."
    kubectl wait --for=condition=Ready pods --all --namespace dapr-system --timeout=300s

# 🧪 (Optional) Run this if you want to access the Dapr dashboard
dapr-dashboard:
    @echo "📊 Forwarding Dapr dashboard to localhost:8080..."
    kubectl port-forward deploy/dapr-dashboard --namespace dapr-system 8080:8080

# Create namespace
create-namespace:
    @if kubectl get ns {{namespace}} > /dev/null 2>&1; then \
      echo "✅ Namespace '{{namespace}}' already exists."; \
    else \
      echo "📁 Creating namespace '{{namespace}}'..."; \
      kubectl create namespace {{namespace}}; \
    fi

# 💾 Deploy Redis
deploy-redis:
    @if helm list -n {{namespace}} | grep -q '^dapr-redis'; then \
      echo "✅ Redis already deployed in namespace '{{namespace}}'."; \
    else \
      echo "🛠 Deploying Redis..."; \
      helm upgrade --install dapr-redis bitnami/redis --values ./config/redis-values.yaml --namespace {{namespace}}; \
      kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=master -n {{namespace}} --timeout=300s; \
    fi

# Deploy Ingress NGINX
deploy-ingress:
    @if helm list -n {{namespace}} | grep -q '^api-gateway'; then \
      echo "✅ Ingress NGINX already deployed."; \
    else \
      echo "🌐 Deploying ingress-nginx..."; \
      helm install api-gateway ingress-nginx/ingress-nginx --values ./config/ingress-values.yaml --namespace {{namespace}}; \
      kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=controller -n {{namespace}} --timeout=300s; \
    fi

# 🚀 Deploy Vizor App
deploy-vizor-apps:
    echo "📦 Deploying Vizor apps..."; \
    helm upgrade --install vizor ./helm/vizor --namespace {{namespace}}; \
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=vizor-apps -n {{namespace}} --timeout=300s; \
    helm list --namespace {{namespace}}

# 🧰 Run the full deployment pipeline
deploy-all: check-cluster install-deps create-namespace deploy-dapr deploy-redis deploy-ingress deploy-vizor-apps
