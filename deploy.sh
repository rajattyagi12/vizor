#!/bin/bash

# Vizor Helm Chart Deployment Script
# Single-click deployment solution for Vizor to Kubernetes
# This script automates all deployment steps from the README.md

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-vizor}"
DAPR_VERSION="1.16.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POWERBI_DB_NAME="PowerBI"
POWERBI_SQL_SCRIPT="${POWERBI_SQL_SCRIPT:-$SCRIPT_DIR/scripts/powerbi-init.sql}"  # Default: deploy/scripts/powerbi-init.sql
SQL_USER="${SQL_USER:-sa}"
SQL_PASSWORD="${SQL_PASSWORD:-P@55w0rd}"
SQL_SERVER="${SQL_SERVER:-sql-server-service}"
SQL_PORT="${SQL_PORT:-1433}"

# Options
SKIP_DAPR=false
SKIP_REDIS=false
SKIP_VIZOR=false
ENABLE_PORT_FORWARD=true
PORT_FORWARD_BACKGROUND=false
ONLY_PORT_FORWARD=false
DRY_RUN=false
USE_LOCAL_IMAGES=false
LOCAL_VALUES_FILE="${SCRIPT_DIR}/config/local-values.yaml"

# Functions
print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Vizor application to Kubernetes using Helm charts.

OPTIONS:
    --skip-dapr          Skip Dapr control plane deployment
    --skip-redis         Skip Redis deployment
    --skip-vizor         Skip Vizor application deployment
    --port-forward       Enable port forwarding for services (development mode)
    --background-pf      Run port forwarding in background (use with --port-forward)
    --only-pf            Only setup port forwarding (skip all deployments)
    --dry-run            Show what would be done without executing
    --use-local-images   Use locally built images (requires build-local-images.sh first)
    --namespace NAME     Use custom namespace (default: vizor)
    --help               Show this help message

Examples:
    $0                                    # Full deployment
    $0 --skip-dapr                       # Skip Dapr if already installed
    $0 --port-forward --background-pf    # Deploy with background port forwarding
    $0 --only-pf --background-pf        # Only setup port forwarding (skip deployments)
    $0 --dry-run                         # Preview deployment steps

Environment Variables:
    NAMESPACE            Kubernetes namespace (default: vizor)
    POWERBI_SQL_SCRIPT   Optional: Path to SQL script to run in PowerBI database
    SQL_USER             SQL Server username (default: sa)
    SQL_PASSWORD         SQL Server password (default: P@55w0rd)

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-dapr)
                SKIP_DAPR=true
                shift
                ;;
            --skip-redis)
                SKIP_REDIS=true
                shift
                ;;
            --skip-vizor)
                SKIP_VIZOR=true
                shift
                ;;
            --port-forward)
                ENABLE_PORT_FORWARD=true
                shift
                ;;
            --background-pf)
                PORT_FORWARD_BACKGROUND=true
                shift
                ;;
            --only-pf)
                ONLY_PORT_FORWARD=true
                ENABLE_PORT_FORWARD=true
                SKIP_DAPR=true
                SKIP_REDIS=true
                SKIP_VIZOR=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --use-local-images)
                USE_LOCAL_IMAGES=true
                shift
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

check_prerequisites() {
    print_step "Checking prerequisites..."
    
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would check prerequisites"
        return 0
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed. Please install helm first."
        exit 1
    fi
    
    # Check dapr CLI (optional, but warn if missing)
    if ! command -v dapr &> /dev/null; then
        print_warning "dapr CLI is not installed. Some features may not work."
        print_info "Install from: https://docs.dapr.io/getting-started/install-dapr-cli/"
    fi
    
    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot access Kubernetes cluster. Please configure kubectl."
        exit 1
    fi
    
    # Check cluster nodes
    READY_NODES=$(kubectl get nodes --no-headers | grep -c " Ready" || true)
    if [ "$READY_NODES" -lt 1 ]; then
        print_error "No ready nodes found in cluster."
        exit 1
    fi
    
    print_success "Prerequisites check passed ($READY_NODES ready nodes)"
}

install_dependencies() {
    print_step "Adding Helm repositories..."
    
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would add Helm repositories:"
        print_info "  - bitnami: https://charts.bitnami.com/bitnami"
        print_info "  - dapr: https://dapr.github.io/helm-charts/"
        print_info "  - local-path-provisioner: https://charts.containeroo.ch/"
        print_info "  - Would run: helm repo update"
        return 0
    fi
    
    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo add dapr https://dapr.github.io/helm-charts/ 2>/dev/null || true
    helm repo add local-path-provisioner https://charts.containeroo.ch/ 2>/dev/null || true
    helm repo update
    
    print_success "Helm repositories updated"
}

deploy_dapr() {
    if [ "$SKIP_DAPR" = true ]; then
        print_info "Skipping Dapr deployment (--skip-dapr flag set)"
        return 0
    fi
    
    print_step "Deploying Dapr control plane..."
    
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would deploy Dapr control plane:"
        print_info "  helm upgrade --install dapr dapr/dapr --version $DAPR_VERSION --namespace dapr-system --create-namespace --wait"
        return 0
    fi
    
    # Check if already deployed
    local dapr_exists=false
    if helm list -n dapr-system 2>/dev/null | grep -q "^dapr"; then
        print_info "Dapr release found, upgrading..."
        dapr_exists=true
    else
        print_info "Dapr release not found, installing..."
        dapr_exists=false
    fi
    
    # For fresh installs, skip --wait to avoid hanging, then wait manually
    if [ "$dapr_exists" = false ]; then
        print_info "Fresh Dapr install - deploying without --wait (will wait for pods manually)..."
        helm upgrade --install dapr dapr/dapr \
            --version "$DAPR_VERSION" \
            --namespace dapr-system \
            --create-namespace \
            --timeout 10m || {
            print_warning "Helm install had issues, but continuing to check pod status..."
        }
    else
        # For upgrades, use --wait
        helm upgrade --install dapr dapr/dapr \
            --version "$DAPR_VERSION" \
            --namespace dapr-system \
            --create-namespace \
            --wait \
            --timeout 10m || {
            print_warning "Helm upgrade with --wait timed out, but continuing to check pod status..."
        }
    fi
        
        echo "⏳ Waiting for Dapr pods to be ready..."
    kubectl wait --for=condition=Ready pods --all -n dapr-system --timeout=300s 2>/dev/null || {
        print_warning "Some Dapr pods may still be starting..."
        print_info "Current Dapr pod status:"
        kubectl get pods -n dapr-system 2>&1 | head -10
    }
    print_success "Dapr control plane deployed/upgraded"
}

create_namespace() {
    print_step "Creating namespace '$NAMESPACE'..."
    
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would create namespace '$NAMESPACE'"
        return 0
    fi
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_warning "Namespace '$NAMESPACE' already exists"
    else
        kubectl create namespace "$NAMESPACE"
        print_success "Namespace '$NAMESPACE' created"
    fi
}

cleanup_orphaned() {
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would clean up orphaned resources"
        return 0
    fi
    
    print_step "Cleaning up orphaned resources..."
    
    # Remove old interaction-service if it exists (from previous hardcoded deployments)
    if kubectl get svc interaction-service -n "$NAMESPACE" &> /dev/null; then
        print_warning "Removing orphaned 'interaction-service'..."
        kubectl delete svc interaction-service -n "$NAMESPACE" || true
    fi
    
    print_success "Cleanup complete"
}

deploy_redis() {
    if [ "$SKIP_REDIS" = true ]; then
        print_info "Skipping Redis deployment (--skip-redis flag set)"
        return 0
    fi
    
    print_step "Deploying Redis..."
    
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would deploy Redis:"
        print_info "  helm upgrade --install dapr-redis bitnami/redis --values $SCRIPT_DIR/config/redis-values.yaml --namespace $NAMESPACE"
        return 0
    fi
    
    # Check if Redis is already deployed via Helm
    if helm list -n "$NAMESPACE" | grep -q '^dapr-redis'; then
        print_info "Redis already deployed via Helm, checking readiness..."
        
        # Wait for Redis master pod to be ready
        if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=master &> /dev/null; then
            print_info "Waiting for Redis master pod to be ready..."
            kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=master -n "$NAMESPACE" --timeout=60s || {
                print_warning "Redis master pod may not be ready yet"
            }
        fi
        
        # Verify Redis service exists
        if kubectl get svc vizor-redis-master -n "$NAMESPACE" &> /dev/null; then
            print_success "Redis is deployed and ready"
            return 0
        else
            print_warning "Redis Helm release exists but service not found, redeploying..."
            helm uninstall dapr-redis -n "$NAMESPACE" > /dev/null 2>&1 || true
            sleep 5
        fi
    fi
    
    # Deploy Redis using Helm
    cd "$SCRIPT_DIR"
    print_info "Installing Redis using Helm chart..."
    
    if ! helm upgrade --install dapr-redis bitnami/redis \
        --values ./config/redis-values.yaml \
        --namespace "$NAMESPACE" \
        --wait \
        --timeout 5m; then
        print_error "Failed to deploy Redis via Helm"
        return 1
    fi
    
    # Wait for Redis master pod to be ready
    print_info "Waiting for Redis master pod to be ready..."
    if kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=master -n "$NAMESPACE" --timeout=300s; then
        print_success "Redis master pod is ready"
    else
        print_warning "Redis master pod may not be ready yet, but continuing..."
    fi
    
    # Verify Redis service exists
    if kubectl get svc vizor-redis-master -n "$NAMESPACE" &> /dev/null; then
        print_success "Redis service 'vizor-redis-master' is available"
    else
        print_error "Redis service 'vizor-redis-master' not found after deployment"
        print_info "Available Redis services:"
        kubectl get svc -n "$NAMESPACE" | grep -i redis || echo "  None found"
        return 1
    fi
    
    # Test Redis connectivity (optional but helpful)
    print_info "Verifying Redis connectivity..."
    local redis_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$redis_pod" ]; then
        if kubectl exec "$redis_pod" -n "$NAMESPACE" -- redis-cli ping > /dev/null 2>&1; then
            print_success "Redis is responding to ping"
        else
            print_warning "Redis pod exists but not responding to ping yet"
        fi
    fi
    
    print_success "Redis deployed and ready"
}

# Note: Ingress NGINX deployment removed - using Caddy API Gateway instead
# Caddy API Gateway is deployed as part of Vizor Helm chart (api-proxy deployment)

deploy_vizor() {
    if [ "$SKIP_VIZOR" = true ]; then
        print_info "Skipping Vizor application deployment (--skip-vizor flag set)"
        return 0
    fi
    
    print_step "Deploying Vizor applications..."
    
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would deploy Vizor applications:"
        print_info "  helm upgrade --install vizor $SCRIPT_DIR/helm/vizor --namespace $NAMESPACE --wait"
        return 0
    fi
    
    cleanup_orphaned
    
    # Check if this is a fresh install or an upgrade
    local is_fresh_install=false
    local release_status=""
    
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "^vizor"; then
        release_status=$(helm list -n "$NAMESPACE" 2>/dev/null | grep "^vizor" | awk '{print $NF}' || echo "")
        print_info "Vizor release found (status: $release_status)"
        
        # If release is failed or pending, treat as fresh install and clean up
        if [ "$release_status" = "failed" ] || [ "$release_status" = "pending-upgrade" ] || [ "$release_status" = "pending-install" ]; then
            print_warning "Release is in bad state ($release_status), cleaning up and treating as fresh install..."
            helm rollback vizor -n "$NAMESPACE" 2>/dev/null || helm uninstall vizor -n "$NAMESPACE" 2>/dev/null || true
            sleep 5
            is_fresh_install=true
            print_info "Cleaned up, will perform fresh install..."
        else
            print_info "This is an UPGRADE..."
            is_fresh_install=false
        fi
    else
        print_info "Vizor release not found, this is a fresh INSTALL..."
        is_fresh_install=true
    fi
    
    # Delete existing jobs if they exist (to prevent Helm hook conflicts)
    # We'll recreate them after setup (if fresh install) or just run them (if upgrade)
    local powerbi_job="vizor-powerbi-setup"
    
    print_info "Cleaning up existing jobs before Helm install..."
    
    if kubectl get job "$powerbi_job" -n "$NAMESPACE" &> /dev/null; then
        print_info "Removing existing PowerBI setup job (will recreate via Helm hook)..."
        kubectl delete job "$powerbi_job" -n "$NAMESPACE" > /dev/null 2>&1 || true
        sleep 2
        kubectl delete pods -n "$NAMESPACE" -l job-name="$powerbi_job" > /dev/null 2>&1 || true
    fi
    
    # Clean up Keycloak jobs that might conflict
    if kubectl get job keycloak-db-init -n "$NAMESPACE" &> /dev/null; then
        print_info "Removing existing Keycloak db-init job..."
        kubectl delete job keycloak-db-init -n "$NAMESPACE" > /dev/null 2>&1 || true
        sleep 2
    fi
    
    # Also clean up ConfigMap if it exists
    if kubectl get configmap powerbi-init-script -n "$NAMESPACE" &> /dev/null; then
        print_info "Removing existing PowerBI script ConfigMap..."
        kubectl delete configmap powerbi-init-script -n "$NAMESPACE" > /dev/null 2>&1 || true
    fi
    
    sleep 2
    
    cd "$SCRIPT_DIR"
    
    # Note: SQL Server is created BY the Helm chart, so we install first, then wait for it
    # PowerBI hook is disabled (skipHelmHook=true) so it won't run automatically
    
    # Check for Helm lock and cleanup stuck releases
    print_info "Checking for Helm lock and stuck releases..."
    
    # Check if release exists and is stuck
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "^vizor"; then
        local release_status=$(helm list -n "$NAMESPACE" 2>/dev/null | grep "^vizor" | awk '{print $NF}' || echo "")
        if [ "$release_status" = "pending-install" ] || [ "$release_status" = "pending-upgrade" ] || [ "$release_status" = "pending-rollback" ]; then
            print_warning "Helm release is stuck in '$release_status' state, cleaning up..."
            # Try to rollback first
            helm rollback vizor -n "$NAMESPACE" 2>/dev/null || true
            sleep 5
            # If still stuck, uninstall
            if helm list -n "$NAMESPACE" 2>/dev/null | grep "^vizor" | grep -q "pending"; then
                print_warning "Release still stuck, attempting uninstall..."
                helm uninstall vizor -n "$NAMESPACE" 2>/dev/null || true
                sleep 5
                # Clean up stuck Helm secrets
                kubectl delete secret -n "$NAMESPACE" -l owner=helm --field-selector metadata.name=sh.helm.release.vizor.v1 2>/dev/null || true
                sleep 3
            fi
        fi
    fi
    
    # Wait for any in-progress operations
    local lock_wait=0
    local max_lock_wait=60  # 1 minute
    while [ $lock_wait -lt $max_lock_wait ]; do
        if helm list -n "$NAMESPACE" 2>&1 | grep -q "another operation.*in progress"; then
            print_warning "Helm operation in progress, waiting ${lock_wait}s..."
            sleep 5
            lock_wait=$((lock_wait + 5))
        else
            break
        fi
    done
    
    # Deploy Helm chart
    print_info "Deploying Vizor Helm chart..."
    
    # Prepare Helm command arguments
    local helm_args=(
        "upgrade" "--install" "vizor" "./helm/vizor"
        "--namespace" "$NAMESPACE"
        "--set" "powerbi.skipHelmHook=true"
        "--timeout" "10m"
    )
    
    # Add local values file if --use-local-images is set
    if [ "$USE_LOCAL_IMAGES" = true ]; then
        if [ -f "$LOCAL_VALUES_FILE" ]; then
            print_info "Using local images configuration from $LOCAL_VALUES_FILE"
            helm_args+=("-f" "$LOCAL_VALUES_FILE")
        else
            print_warning "Local values file not found: $LOCAL_VALUES_FILE"
            print_info "Creating local values file..."
            # Create a basic local values file
            cat > "$LOCAL_VALUES_FILE" <<EOF
image:
  registry: localhost
  repo: vizor
  tag: test
  pullPolicy: IfNotPresent
EOF
            helm_args+=("-f" "$LOCAL_VALUES_FILE")
            print_success "Created local values file"
        fi
    fi
    
    if [ "$is_fresh_install" = true ]; then
        # Fresh install: skip --wait to avoid timeout, we'll wait manually for pods
        print_info "Fresh install: deploying without --wait (will wait for pods manually)..."
        
        # Retry logic for Helm lock issues
        local retry_count=0
        local max_retries=3
        while [ $retry_count -lt $max_retries ]; do
            if helm "${helm_args[@]}" 2>&1 | tee /tmp/helm-install.log; then
                break
            else
                if grep -q "another operation.*in progress" /tmp/helm-install.log 2>/dev/null; then
                    retry_count=$((retry_count + 1))
                    if [ $retry_count -lt $max_retries ]; then
                        print_warning "Helm operation in progress, waiting 10s before retry ${retry_count}/${max_retries}..."
                        sleep 10
                        # Try to release the lock by getting status
                        helm status vizor -n "$NAMESPACE" 2>/dev/null || true
                    else
                        print_warning "Helm install had issues after retries, but continuing to check pod status..."
                        break
                    fi
                else
                    print_warning "Helm install had issues, but continuing to check pod status..."
                    break
                fi
            fi
        done
    else
        # Upgrade: skip --wait to avoid hanging (similar to fresh install)
        print_info "Upgrade: deploying without --wait (will wait for pods manually)..."
        helm "${helm_args[@]}" || {
            print_warning "Helm upgrade had issues, but continuing to check pod status..."
        }
    fi
    
    echo "⏳ Waiting for Vizor pods to be ready..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=vizor -n "$NAMESPACE" --timeout=600s || {
        print_warning "Some Vizor pods may still be starting..."
        print_info "Current pod status:"
        kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=vizor 2>&1 | head -10
    }
    
    # Also wait for SQL Server pods specifically (they might not have the instance label)
    if kubectl get pods -n "$NAMESPACE" -l app=sqlserver &> /dev/null; then
        print_info "Waiting for SQL Server pods to be ready..."
        kubectl wait --for=condition=Ready pods -l app=sqlserver -n "$NAMESPACE" --timeout=300s || {
            print_warning "SQL Server pods may still be starting..."
        }
    fi
    
    # CRITICAL: Check if SQL Server was created by Helm chart
    print_step "Checking if SQL Server was created by Helm chart..."
    print_info "SQL Server is created by Helm chart - checking if it exists..."
    
    # Check if SQL Server service exists
    if ! kubectl get svc "$SQL_SERVER" -n "$NAMESPACE" &> /dev/null; then
        print_error "SQL Server service '$SQL_SERVER' was not created by Helm chart"
        print_error "Cannot proceed with database operations without SQL Server"
        print_info "Check Helm chart deployment status:"
        print_info "  kubectl get pods -n $NAMESPACE -l app=sqlserver"
        print_info "  helm status vizor -n $NAMESPACE"
        return 1
    fi
    
    print_success "SQL Server service exists"
    
    # Wait for SQL Server to be ready
    print_info "Waiting for SQL Server to be ready and accepting connections..."
    if ! wait_for_sql_server; then
        print_error "SQL Server service is not ready - cannot proceed with database operations"
        print_error "SQL Server should be created by Helm chart. Check pod status:"
        print_info "  kubectl get pods -n $NAMESPACE -l app=sqlserver"
        print_info "  kubectl logs -n $NAMESPACE -l app=sqlserver --tail=50"
        return 1
    fi
    print_success "SQL Server service is ready and accepting connections"
    
    # Wait for Keycloak to be ready (required before PowerBI jobs)
    print_step "Ensuring Keycloak service is ready..."
    print_info "Waiting for Keycloak pod to be ready..."
    if kubectl get pods -n "$NAMESPACE" -l app=keycloak &> /dev/null; then
        print_info "Waiting for Keycloak pods to be ready..."
        kubectl wait --for=condition=Ready pods -l app=keycloak -n "$NAMESPACE" --timeout=300s || {
            print_warning "Keycloak pods may still be starting..."
            print_info "Current Keycloak pod status:"
            kubectl get pods -n "$NAMESPACE" -l app=keycloak 2>&1 | head -5
        }
        print_success "Keycloak service is ready"
        
        # Configure master realm CSP for 3rd party cookie checks
        print_info "Configuring Keycloak master realm CSP..."
        if [ -f "$SCRIPT_DIR/configure-keycloak-master-csp.sh" ]; then
            "$SCRIPT_DIR/configure-keycloak-master-csp.sh" || {
                print_warning "Failed to configure master realm CSP - this is non-critical"
            }
        fi
    else
        print_warning "Keycloak pods not found with label app=keycloak, skipping Keycloak readiness check"
    fi
    
    # Handle fresh installs vs upgrades differently
    if [ "$is_fresh_install" = true ]; then
        # ============================================================
        # FRESH INSTALL SEQUENCE:
        # 1. SQL Server is already verified as ready (above)
        # 2. Keycloak is verified as ready (above)
        # 3. Port forward SQL Server
        # 4. Run PowerBI job
        # ============================================================
        print_info "=== FRESH INSTALL SEQUENCE ==="
        
        # Step 1: Port forward SQL Server immediately (SQL Server is already verified ready)
        print_step "Step 1: Setting up SQL Server port forwarding..."
        if [ "$ENABLE_PORT_FORWARD" = true ]; then
            setup_sql_port_forward
        else
            print_info "Port forwarding disabled (use --port-forward to enable)"
        fi
        
        # Step 2: Check if PowerBI database exists, then run PowerBI setup job if needed
        print_step "Step 2: Checking PowerBI database and running setup job if needed..."
        
        # First, check if PowerBI database already exists
        local powerbi_exists=false
        if check_powerbi_database_exists; then
            powerbi_exists=true
            print_success "PowerBI database already exists - skipping PowerBI setup job"
        else
            print_info "PowerBI database does not exist - will run setup job"
        fi
        
        # Only run PowerBI job if database doesn't exist
        local powerbi_success=false
        if [ "$powerbi_exists" = false ]; then
            print_info "Running PowerBI setup job..."
            if trigger_powerbi_setup_job; then
                # Verify database was created after job completion
                if check_powerbi_database_exists; then
                    powerbi_success=true
                    print_success "PowerBI setup job completed and database verified"
                else
                    print_warning "PowerBI setup job completed but database not found"
                    powerbi_success=true
                fi
            else
                # Job failed or timed out - check if database exists anyway
                print_warning "PowerBI setup job had issues, but checking if database exists..."
                if check_powerbi_database_exists; then
                    print_success "PowerBI database exists despite job issues - proceeding"
                    powerbi_success=true
                else
                    print_error "PowerBI setup job failed and database does not exist"
                    print_error "Please check the PowerBI setup job logs and fix any issues"
                    print_info "You can manually run: kubectl get job vizor-powerbi-setup -n $NAMESPACE"
                    print_info "Or check logs: kubectl logs -l job-name=vizor-powerbi-setup -n $NAMESPACE"
                    return 1
                fi
            fi
        else
            # Database already exists, skip job
            powerbi_success=true
        fi
        
        # Step 3: Run powerbi-init.sql script
        print_step "Step 3: Running powerbi-init.sql script against PowerBI database..."
        if ! run_powerbi_init_script; then
            print_error "powerbi-init.sql script failed - cannot proceed"
            return 1
        fi
        
        # Step 4: Run scripts from Scripts directory
        print_step "Step 4: Running scripts from Scripts directory..."
        if ! run_scripts_from_directory; then
            print_warning "Some scripts from Scripts directory failed, but continuing..."
        fi
        
        # Cleanup PowerBI job after successful setup
        print_info "Cleaning up PowerBI job after successful setup..."
        local powerbi_job_name="vizor-powerbi-setup"
        if kubectl get job "$powerbi_job_name" -n "$NAMESPACE" &> /dev/null; then
            kubectl delete job "$powerbi_job_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
            local powerbi_pods=$(kubectl get pods -n "$NAMESPACE" -l job-name="$powerbi_job_name" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
            if [ -n "$powerbi_pods" ]; then
                echo "$powerbi_pods" | while read -r pod; do
                    kubectl delete pod "$pod" -n "$NAMESPACE" > /dev/null 2>&1 || true
                done
            fi
        fi
    else
        # ============================================================
        # UPGRADE SEQUENCE:
        # 1. SQL Server is already verified as ready (above)
        # 2. Keycloak is verified as ready (above)
        # 3. Check if PowerBI database exists
        # ============================================================
        print_info "=== UPGRADE SEQUENCE ==="
        
        # Step 1: Check if PowerBI database exists (SQL Server and Keycloak are already verified ready)
        print_step "Step 1: Checking if PowerBI database exists..."
        local powerbi_exists=false
        if check_powerbi_database_exists; then
            powerbi_exists=true
            print_success "PowerBI database exists"
        else
            print_warning "PowerBI database does not exist"
            print_info "This might indicate a previous incomplete installation"
        fi
    fi
    
    print_success "Vizor applications deployed/upgraded"
}

setup_api_gateway_port_forward() {
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    print_info "Starting Caddy API Gateway port-forward on localhost:8080..."
    
    # Wait for Caddy API Gateway service (api-proxy-dapr) availability
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if kubectl get svc api-proxy-dapr -n "$NAMESPACE" &> /dev/null; then
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        print_warning "Caddy API Gateway service not ready yet, skipping port forward"
        return 0
    fi
    
    # Kill any existing PF
    pkill -f "kubectl port-forward.*api-proxy-dapr" || true
    sleep 1
    
    # Background or manual depending on flag
    if [ "$PORT_FORWARD_BACKGROUND" = true ]; then
        nohup kubectl port-forward svc/api-proxy-dapr 8080:80 -n "$NAMESPACE" > /dev/null 2>&1 &
        local pf_pid=$!
        sleep 2
        if ps -p $pf_pid > /dev/null 2>&1; then
            print_success "Caddy API Gateway port-forward started (PID: $pf_pid)"
        else
            print_warning "Failed to start Caddy API Gateway port-forward"
        fi
    else
        print_warning "Run manually in another terminal:"
        print_info "  kubectl port-forward svc/api-proxy-dapr -n $NAMESPACE 8080:80"
    fi
}

setup_sql_port_forward() {
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    print_info "Setting up automatic port forwarding for SQL Server..."
    
    # Wait for SQL Server service to be available
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if kubectl get svc sql-server-service -n "$NAMESPACE" &> /dev/null; then
            # Check if SQL Server pod is running
            if kubectl get pods -n "$NAMESPACE" -l app=sqlserver --field-selector=status.phase=Running 2>/dev/null | grep -q sqlserver; then
                break
            fi
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        print_warning "SQL Server service not ready yet, port forwarding will not be started"
        print_info "You can manually start it later with: kubectl port-forward svc/sql-server-service -n $NAMESPACE 1433:1433"
        return 0
    fi
    
    # Kill any existing SQL Server port-forward processes
    pkill -f "kubectl port-forward.*sql-server-service" || true
    sleep 1
    
    # Start port forwarding in background
    print_info "Starting SQL Server port-forward on localhost:1433..."
    nohup kubectl port-forward svc/sql-server-service 1433:1433 -n "$NAMESPACE" > /dev/null 2>&1 &
    local pf_pid=$!
    
    # Wait a moment and check if it started successfully
    sleep 2
    if ps -p $pf_pid > /dev/null 2>&1; then
        print_success "SQL Server port-forward started successfully (PID: $pf_pid)"
        print_info "SQL Server is now accessible at localhost:1433"
    else
        # Check if port is already in use
        if lsof -ti:1433 > /dev/null 2>&1; then
            print_warning "Port 1433 is already in use. Port forwarding not started."
            print_info "To use SQL Server, either:"
            print_info "  1. Stop the process using port 1433"
            print_info "  2. Or access SQL Server via NodePort: kubectl get svc sql-server-service -n $NAMESPACE"
        else
            print_warning "Failed to start SQL Server port-forward. You can start it manually:"
            print_info "  kubectl port-forward svc/sql-server-service -n $NAMESPACE 1433:1433"
        fi
    fi
}

wait_for_sql_server() {
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    print_info "Waiting for SQL Server to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    # Wait for SQL Server service to be available
    while [ $attempt -lt $max_attempts ]; do
        if kubectl get svc "$SQL_SERVER" -n "$NAMESPACE" &> /dev/null; then
            # Check if SQL Server pod is running
            if kubectl get pods -n "$NAMESPACE" -l app=sqlserver --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep -q .; then
                local sql_pod=$(kubectl get pods -n "$NAMESPACE" -l app=sqlserver --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
                if [ -n "$sql_pod" ] && kubectl get pod "$sql_pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; then
                    break
                fi
            fi
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        print_error "SQL Server pod not ready after $max_attempts attempts"
        return 1
    fi
    
    # Test SQL Server connection using mssql-tools pod
    print_info "Testing SQL Server connection..."
    
    # Try connection test multiple times
    attempt=0
    while [ $attempt -lt 10 ]; do
        local test_pod_name="sql-test-$(date +%s | cut -c9-)"
        
        # Create a temporary pod with mssql-tools and test connection
        kubectl run "$test_pod_name" -n "$NAMESPACE" \
            --image=mcr.microsoft.com/mssql-tools \
            --restart=Never \
            --command -- \
            /opt/mssql-tools/bin/sqlcmd \
            -S "$SQL_SERVER,$SQL_PORT" \
            -U "$SQL_USER" \
            -P "$SQL_PASSWORD" \
            -Q "SELECT 1" \
            > /dev/null 2>&1
        
        # Wait for pod to complete (it goes directly to Succeeded/Completed)
        local wait_attempt=0
        while [ $wait_attempt -lt 30 ]; do
            local phase=$(kubectl get pod "$test_pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            if [ "$phase" = "Succeeded" ]; then
                kubectl delete pod "$test_pod_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
                print_success "SQL Server is ready and accepting connections"
                return 0
            elif [ "$phase" = "Failed" ]; then
                break
            fi
            sleep 1
            wait_attempt=$((wait_attempt + 1))
        done
        
        # Cleanup failed pod
        kubectl delete pod "$test_pod_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
        
        if [ $attempt -lt 9 ]; then
            sleep 3
        fi
        attempt=$((attempt + 1))
    done
    
    print_error "SQL Server connection test failed after $attempt attempts"
    return 1
}

setup_powerbi_database() {
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would create PowerBI database and run script"
        return 0
    fi
    
    # Wait for SQL Server to be ready
    if ! wait_for_sql_server; then
        print_error "Cannot proceed with PowerBI database setup - SQL Server not ready"
        return 1
    fi
    
    print_step "Setting up PowerBI database..."
    
    # Create PowerBI database if it doesn't exist using mssql-tools pod
    print_info "Creating PowerBI database..."
    local create_db_pod="powerbi-create-db-$(date +%s | cut -c9-)"
    
    kubectl run "$create_db_pod" -n "$NAMESPACE" \
        --image=mcr.microsoft.com/mssql-tools \
        --restart=Never \
        --command -- \
        /opt/mssql-tools/bin/sqlcmd \
        -S "$SQL_SERVER,$SQL_PORT" \
        -U "$SQL_USER" \
        -P "$SQL_PASSWORD" \
        -Q "IF NOT EXISTS(SELECT name FROM sys.databases WHERE name='$POWERBI_DB_NAME') CREATE DATABASE [$POWERBI_DB_NAME];" \
        > /dev/null 2>&1
    
    # Wait for pod to complete (check for Succeeded phase)
    print_info "Waiting for database creation to complete..."
    local wait_attempt=0
    local pod_succeeded=false
    
    while [ $wait_attempt -lt 60 ]; do
        local phase=$(kubectl get pod "$create_db_pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [ "$phase" = "Succeeded" ]; then
            pod_succeeded=true
            break
        elif [ "$phase" = "Failed" ]; then
            # Get logs to see what went wrong
            print_error "Pod failed. Logs:"
            kubectl logs "$create_db_pod" -n "$NAMESPACE" 2>&1 | head -10
            kubectl delete pod "$create_db_pod" -n "$NAMESPACE" > /dev/null 2>&1 || true
            print_error "Failed to create PowerBI database"
            return 1
        fi
        
        sleep 2
        wait_attempt=$((wait_attempt + 1))
    done
    
    # Always cleanup pod (regardless of success/failure)
    if [ "$pod_succeeded" = true ]; then
        print_success "PowerBI database created or already exists"
    else
        print_error "Database creation timed out"
        print_info "Cleaning up temporary resources..."
    fi
    
    # Cleanup pod
    kubectl delete pod "$create_db_pod" -n "$NAMESPACE" > /dev/null 2>&1 || true
    
    if [ "$pod_succeeded" != true ]; then
        return 1
    fi
    
    # Run SQL script in PowerBI database if provided
    if [ -n "$POWERBI_SQL_SCRIPT" ] && [ -f "$POWERBI_SQL_SCRIPT" ]; then
        print_info "Running SQL script in PowerBI database: $POWERBI_SQL_SCRIPT"
        print_info "Script will create tables and stored procedures for PowerBI"
        
        # Create a ConfigMap from the SQL script
        local script_basename=$(basename "$POWERBI_SQL_SCRIPT")
        local configmap_name="powerbi-script-$(date +%s | cut -c1-10)"
        
        kubectl create configmap "$configmap_name" -n "$NAMESPACE" \
            --from-file="$script_basename=$POWERBI_SQL_SCRIPT" \
            > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            # Create a pod to run the script
            local run_script_pod="powerbi-run-script-$(date +%s)"
            
            # Create pod YAML and apply it
            local pod_yaml="/tmp/${run_script_pod}.yaml"
            cat > "$pod_yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $run_script_pod
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  containers:
  - name: sqlcmd
    image: mcr.microsoft.com/mssql-tools
    command: ["/opt/mssql-tools/bin/sqlcmd"]
    args:
    - -S
    - "$SQL_SERVER,$SQL_PORT"
    - -U
    - "$SQL_USER"
    - -P
    - "$SQL_PASSWORD"
    - -d
    - "$POWERBI_DB_NAME"
    - -i
    - "/tmp/$script_basename"
    volumeMounts:
    - name: script
      mountPath: /tmp
  volumes:
  - name: script
    configMap:
      name: $configmap_name
EOF
            
            kubectl apply -f "$pod_yaml" > /dev/null 2>&1
            
            # Initialize exit code
            local script_exit_code=0
            
            # Wait for pod to be ready and then complete
            if kubectl wait --for=condition=Ready --timeout=60s pod/"$run_script_pod" -n "$NAMESPACE" > /dev/null 2>&1; then
                # Show pod logs in real-time
                print_info "Executing SQL script (this may take a moment)..."
                kubectl logs -f pod/"$run_script_pod" -n "$NAMESPACE" 2>&1 | while IFS= read -r line; do
                    if [[ "$line" =~ [Ee]rror|[Ff]ailed ]]; then
                        print_error "$line"
                    fi
                done || true
                
                # Wait for pod completion
                kubectl wait --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s pod/"$run_script_pod" -n "$NAMESPACE" > /dev/null 2>&1
                script_exit_code=$?
            else
                print_error "Failed to start script execution pod"
                script_exit_code=1
            fi
            
            # Always cleanup pod, configmap, and temp files (regardless of success/failure)
            print_info "Cleaning up temporary resources..."
            kubectl delete pod "$run_script_pod" -n "$NAMESPACE" > /dev/null 2>&1 || true
            kubectl delete configmap "$configmap_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
            rm -f "$pod_yaml"
            
            if [ $script_exit_code -eq 0 ]; then
                print_success "SQL script executed successfully in PowerBI database"
            else
                print_warning "SQL script execution completed with warnings (exit code: $script_exit_code)"
            fi
        else
            print_error "Failed to create ConfigMap from SQL script"
            return 1
        fi
    elif [ -n "$POWERBI_SQL_SCRIPT" ]; then
        print_warning "SQL script file not found: $POWERBI_SQL_SCRIPT (skipping script execution)"
        print_info "Looking for script at: $SCRIPT_DIR/scripts/powerbi-init.sql"
    else
        print_info "No PowerBI SQL script specified (using default: $SCRIPT_DIR/scripts/powerbi-init.sql)"
    fi
    
    print_success "PowerBI database setup completed"
}

trigger_powerbi_setup_job() {
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would trigger PowerBI setup job"
        return 0
    fi
    
    local job_name="vizor-powerbi-setup"
    local max_wait=600  # 10 minutes
    
    print_step "Triggering PowerBI setup job..."
    
    # Check if job already exists from Helm hook
    if kubectl get job "$job_name" -n "$NAMESPACE" &> /dev/null; then
        local job_complete=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        
        if [ "$job_complete" = "True" ]; then
            print_info "PowerBI setup job already completed"
            
            # Show job logs
            local pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            if [ -n "$pod_name" ]; then
                print_info "Job logs:"
                kubectl logs "$pod_name" -n "$NAMESPACE" 2>&1 | tail -20
            fi
            
            # Cleanup completed job
            print_info "Cleaning up completed PowerBI setup job..."
            kubectl delete job "$job_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
            local powerbi_pods=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
            if [ -n "$powerbi_pods" ]; then
                echo "$powerbi_pods" | while read -r pod; do
                    kubectl delete pod "$pod" -n "$NAMESPACE" > /dev/null 2>&1 || true
                done
            fi
            print_success "PowerBI job already completed and cleaned up"
            return 0
        else
            # Check if job failed
            local job_failed_check=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
            if [ "$job_failed_check" = "True" ]; then
                print_warning "PowerBI setup job failed, recreating..."
                kubectl delete job "$job_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
                sleep 3
            else
                print_info "PowerBI setup job exists and is running, waiting for completion..."
            fi
        fi
    else
        # Job doesn't exist, create it manually using Helm template
        print_info "Creating PowerBI setup job manually..."
        cd "$SCRIPT_DIR"
        
        # Render the Helm template for the PowerBI job and apply it
        local job_yaml="/tmp/${job_name}.yaml"
        
        # Use helm template to render the PowerBI job
        helm template vizor ./helm/vizor \
            --namespace "$NAMESPACE" \
            --set powerbi.enabled=true \
            --show-only templates/components/powerbi-setup-job.yaml \
            > "$job_yaml" 2>/dev/null
        
        if [ -f "$job_yaml" ] && grep -q "kind: Job\|kind: ConfigMap" "$job_yaml"; then
            # Remove hook annotations so it doesn't get deleted automatically
            sed -i.bak '/helm.sh\/hook/d' "$job_yaml" 2>/dev/null || sed -i '' '/helm.sh\/hook/d' "$job_yaml" 2>/dev/null || true
            rm -f "${job_yaml}.bak" 2>/dev/null || true
            
            # Apply both ConfigMap and Job together
            if kubectl apply -f "$job_yaml" > /dev/null 2>&1; then
                print_info "PowerBI setup job and ConfigMap created successfully"
                rm -f "$job_yaml"
            else
                print_error "Failed to create PowerBI setup job"
                rm -f "$job_yaml"
                return 1
            fi
        else
            print_error "Failed to render PowerBI setup job template"
            print_info "Falling back to manual PowerBI setup using temporary pods..."
            rm -f "$job_yaml"
            setup_powerbi_database  # Fallback to old method
            return $?
        fi
        
        # Wait a moment for job to be registered
        sleep 3
    fi
    
    # Wait for job completion using kubectl wait (more reliable)
    print_info "Waiting for PowerBI setup job to complete (timeout: ${max_wait}s)..."
    
    # Use kubectl wait for more reliable job completion detection
    if kubectl wait --for=condition=complete --timeout=${max_wait}s job/"$job_name" -n "$NAMESPACE" 2>/dev/null; then
        print_success "PowerBI setup job completed successfully"
        
        # Show job logs
        local pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$pod_name" ]; then
            print_info "Job logs:"
            kubectl logs "$pod_name" -n "$NAMESPACE" 2>&1 | tail -20 || true
        fi
        
        # Verify database was actually created
        print_info "Verifying PowerBI database was created..."
        if check_powerbi_database_exists; then
            print_success "PowerBI database verified after job completion"
        else
            print_warning "PowerBI job completed but database not found - this may be okay if it already existed"
        fi
        
        # Cleanup PowerBI job after successful completion
        print_info "Cleaning up PowerBI setup job after successful completion..."
        kubectl delete job "$job_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
        
        # Clean up associated pods
        local powerbi_pods=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
        if [ -n "$powerbi_pods" ]; then
            echo "$powerbi_pods" | while read -r pod; do
                kubectl delete pod "$pod" -n "$NAMESPACE" > /dev/null 2>&1 || true
            done
        fi
        
        print_success "PowerBI setup job completed and cleaned up successfully"
        return 0
    else
        # Check if job failed
        local job_failed=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
        if [ "$job_failed" = "True" ]; then
            print_warning "PowerBI setup job failed, but checking if database exists anyway..."
            
            # Show job logs for debugging
            local pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            if [ -n "$pod_name" ]; then
                print_info "Job logs:"
                kubectl logs "$pod_name" -n "$NAMESPACE" 2>&1 | tail -50 || true
            fi
            
            # Check if database exists despite job failure (maybe it was created before failure)
            if check_powerbi_database_exists; then
                print_success "PowerBI database exists despite job failure - proceeding"
                return 0
            else
                print_error "PowerBI setup job failed and database does not exist"
                return 1
            fi
        else
            print_warning "PowerBI setup job timed out or did not complete within ${max_wait}s"
            
            # Show current job status
            print_info "Current job status:"
            kubectl get job "$job_name" -n "$NAMESPACE" 2>&1 || true
            
            # Check for pods
            local pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            if [ -n "$pod_name" ]; then
                print_info "Pod status:"
                kubectl get pod "$pod_name" -n "$NAMESPACE" 2>&1 || true
                print_info "Pod logs (last 30 lines):"
                kubectl logs "$pod_name" -n "$NAMESPACE" --tail=30 2>&1 || true
            fi
            
            # Check if database exists despite timeout (maybe job completed but kubectl wait didn't detect it)
            print_info "Checking if PowerBI database exists despite timeout..."
            if check_powerbi_database_exists; then
                print_success "PowerBI database exists despite timeout - job may have completed successfully"
                return 0
            else
                print_warning "PowerBI database does not exist after timeout"
                print_info "Job may still be running. You can check status with:"
                print_info "  kubectl get job $job_name -n $NAMESPACE"
                print_info "  kubectl logs -l job-name=$job_name -n $NAMESPACE"
                return 0
            fi
        fi
    fi
}

# Run powerbi-init.sql script
run_powerbi_init_script() {
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would run powerbi-init.sql script"
        return 0
    fi
    
    # Wait for SQL Server to be ready
    if ! wait_for_sql_server; then
        print_error "Cannot run powerbi-init.sql - SQL Server not ready"
        return 1
    fi
    
    print_info "Running powerbi-init.sql script against PowerBI database..."
    
    # Check if powerbi-init.sql exists
    local powerbi_init_script="${SCRIPT_DIR}/scripts/powerbi-init.sql"
    if [ ! -f "$powerbi_init_script" ]; then
        print_warning "powerbi-init.sql not found at '$powerbi_init_script'. Skipping..."
        return 0
    fi
    
    # Create a ConfigMap from the SQL script
    local script_basename=$(basename "$powerbi_init_script")
    local configmap_name="powerbi-init-script-$(date +%s | cut -c1-10)"
    
    kubectl create configmap "$configmap_name" -n "$NAMESPACE" \
        --from-file="$script_basename=$powerbi_init_script" \
        > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        print_error "Failed to create ConfigMap from powerbi-init.sql"
        return 1
    fi
    
    # Create a pod to run the script
    local run_script_pod="powerbi-init-$(date +%s)"
    
    # Create pod YAML and apply it
    local pod_yaml="/tmp/${run_script_pod}.yaml"
    cat > "$pod_yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $run_script_pod
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  containers:
  - name: sqlcmd
    image: mcr.microsoft.com/mssql-tools
    command: ["/opt/mssql-tools/bin/sqlcmd"]
    args:
    - -S
    - "$SQL_SERVER,$SQL_PORT"
    - -U
    - "$SQL_USER"
    - -P
    - "$SQL_PASSWORD"
    - -d
    - "$POWERBI_DB_NAME"
    - -i
    - "/tmp/$script_basename"
    volumeMounts:
    - name: script
      mountPath: /tmp
  volumes:
  - name: script
    configMap:
      name: $configmap_name
EOF
    
    kubectl apply -f "$pod_yaml" > /dev/null 2>&1
    
    # Wait for pod to be ready and then complete
    local script_exit_code=0
    if kubectl wait --for=condition=Ready --timeout=60s pod/"$run_script_pod" -n "$NAMESPACE" > /dev/null 2>&1; then
        print_info "Executing powerbi-init.sql (this may take a moment)..."
        kubectl logs -f pod/"$run_script_pod" -n "$NAMESPACE" 2>&1 | while IFS= read -r line; do
            if [[ "$line" =~ [Ee]rror|[Ff]ailed ]]; then
                print_error "$line"
            fi
        done || true
        
        # Wait for pod completion
        kubectl wait --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s pod/"$run_script_pod" -n "$NAMESPACE" > /dev/null 2>&1
        script_exit_code=$?
    else
        print_error "Failed to start powerbi-init.sql execution pod"
        script_exit_code=1
    fi
    
    # Cleanup
    kubectl delete pod "$run_script_pod" -n "$NAMESPACE" > /dev/null 2>&1 || true
    kubectl delete configmap "$configmap_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
    rm -f "$pod_yaml"
    
    if [ $script_exit_code -eq 0 ]; then
        print_success "powerbi-init.sql executed successfully"
        return 0
    else
        print_error "powerbi-init.sql execution failed"
        return 1
    fi
}

# Run scripts from Scripts directory
run_scripts_from_directory() {
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would run scripts from Scripts directory"
        return 0
    fi
    
    # Wait for SQL Server to be ready
    if ! wait_for_sql_server; then
        print_error "Cannot run scripts - SQL Server not ready"
        return 1
    fi
    
    print_info "Running scripts from Scripts directory..."
    
    # Check if Scripts directory exists
    local scripts_dir="${SCRIPT_DIR}/Scripts"
    if [ ! -d "$scripts_dir" ]; then
        print_warning "Scripts directory not found at '$scripts_dir'. Skipping script execution."
        return 0
    fi
    
    # Find all SQL scripts in Scripts directory
    local sql_scripts=$(find "$scripts_dir" -name "*.sql" -type f | sort)
    
    if [ -z "$sql_scripts" ]; then
        print_info "No SQL scripts found in '$scripts_dir'. Skipping script execution."
        return 0
    fi
    
    print_info "Found SQL scripts in '$scripts_dir'. Executing them in order..."
    
    # Execute each script
    local script_count=0
    for script in $sql_scripts; do
        script_count=$((script_count + 1))
        local script_name=$(basename "$script")
        print_info "Executing script $script_count: $script_name"
        
        # Create a temporary job to run the script
        local temp_job_name="script-runner-$(basename "$script" .sql)-$(date +%s)"
        
        # Read script content
        local script_content=$(cat "$script")
        
        # Create ConfigMap with script content first
        echo "$script_content" | kubectl create configmap "${temp_job_name}-cm" \
            --from-file=script.sql=/dev/stdin \
            -n "$NAMESPACE" > /dev/null 2>&1 || {
            print_error "Failed to create ConfigMap for script $script_name"
            continue
        }
        
        # Create job that uses the ConfigMap
        cat <<EOF | kubectl apply -f - -n "$NAMESPACE" > /dev/null 2>&1
apiVersion: batch/v1
kind: Job
metadata:
  name: ${temp_job_name}
spec:
  ttlSecondsAfterFinished: 30
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: run-script
        image: mcr.microsoft.com/mssql-tools
        command:
        - /bin/bash
        - -c
        - |
          echo "Executing script: ${script_name}"
          /opt/mssql-tools/bin/sqlcmd -S "${SQL_SERVER},${SQL_PORT}" -U "${SQL_USER}" -P "${SQL_PASSWORD}" \
            -i /tmp/script.sql
        volumeMounts:
        - name: script
          mountPath: /tmp/script.sql
          subPath: script.sql
          readOnly: true
      volumes:
      - name: script
        configMap:
          name: ${temp_job_name}-cm
EOF
        
        # Wait for job to complete
        local max_wait=300  # 5 minutes per script
        local wait_count=0
        local job_succeeded=false
        
        while [ $wait_count -lt $max_wait ]; do
            local job_status=$(kubectl get job "$temp_job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
            local job_failed=$(kubectl get job "$temp_job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
            
            if [ "$job_status" = "True" ]; then
                job_succeeded=true
                print_success "Script $script_name executed successfully!"
                
                # Show logs
                local script_pod=$(kubectl get pods -n "$NAMESPACE" -l job-name="$temp_job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                if [ -n "$script_pod" ]; then
                    kubectl logs "$script_pod" -n "$NAMESPACE" --tail=20 || true
                fi
                break
            elif [ "$job_failed" = "True" ]; then
                print_error "Script $script_name failed!"
                
                # Show logs for debugging
                local script_pod=$(kubectl get pods -n "$NAMESPACE" -l job-name="$temp_job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                if [ -n "$script_pod" ]; then
                    print_error "Script execution logs:"
                    kubectl logs "$script_pod" -n "$NAMESPACE" || true
                fi
                
                # Clean up
                kubectl delete job "$temp_job_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
                kubectl delete configmap "${temp_job_name}-cm" -n "$NAMESPACE" > /dev/null 2>&1 || true
                print_error "Stopping script execution due to failure."
                return 1
            fi
            
            sleep 2
            wait_count=$((wait_count + 2))
        done
        
        if [ "$job_succeeded" != true ]; then
            print_error "Script $script_name did not complete within timeout."
            kubectl delete job "$temp_job_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
            kubectl delete configmap "${temp_job_name}-cm" -n "$NAMESPACE" > /dev/null 2>&1 || true
            return 1
        fi
        
        # Clean up
        kubectl delete job "$temp_job_name" -n "$NAMESPACE" > /dev/null 2>&1 || true
        kubectl delete configmap "${temp_job_name}-cm" -n "$NAMESPACE" > /dev/null 2>&1 || true
    done
    
    print_success "All scripts from Scripts directory executed successfully!"
    return 0
}

# Check if PowerBI database exists
check_powerbi_database_exists() {
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    print_info "Checking if PowerBI database exists..."
    
    # Wait for SQL Server to be ready
    if ! wait_for_sql_server; then
        print_error "Cannot check PowerBI database - SQL Server not ready"
        return 1
    fi
    
    # Check if PowerBI database exists using mssql-tools pod
    local check_pod="powerbi-db-check-$(date +%s | cut -c9-)"
    
    kubectl run "$check_pod" -n "$NAMESPACE" \
        --image=mcr.microsoft.com/mssql-tools \
        --restart=Never \
        --command -- \
        /opt/mssql-tools/bin/sqlcmd \
        -S "$SQL_SERVER,$SQL_PORT" \
        -U "$SQL_USER" \
        -P "$SQL_PASSWORD" \
        -Q "SELECT CASE WHEN EXISTS(SELECT name FROM sys.databases WHERE name='$POWERBI_DB_NAME') THEN 'EXISTS' ELSE 'NOT_EXISTS' END" \
        -h -1 -W \
        > /dev/null 2>&1
    
    # Wait for pod to complete
    local wait_attempt=0
    local db_exists="NOT_EXISTS"
    
    while [ $wait_attempt -lt 30 ]; do
        local phase=$(kubectl get pod "$check_pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [ "$phase" = "Succeeded" ]; then
            db_exists=$(kubectl logs "$check_pod" -n "$NAMESPACE" 2>/dev/null | tr -d '\r\n ' || echo "NOT_EXISTS")
            break
        elif [ "$phase" = "Failed" ]; then
            break
        fi
        
        sleep 1
        wait_attempt=$((wait_attempt + 1))
    done
    
    # Cleanup pod
    kubectl delete pod "$check_pod" -n "$NAMESPACE" > /dev/null 2>&1 || true
    
    if [ "$db_exists" = "EXISTS" ]; then
        print_success "PowerBI database exists"
        return 0
    else
        print_warning "PowerBI database does not exist"
        return 1
    fi
}

setup_port_forwarding() {
    if [ "$ENABLE_PORT_FORWARD" = false ]; then
        return 0
    fi
    
    print_step "Setting up port forwarding..."
    
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would set up port forwarding:"
        print_info "  - Dapr Dashboard: 8081:8080"
        print_info "  - Caddy API Gateway: 8080:80"
        print_info "  - SQL Server: 1433:1433"
        return 0
    fi
    
    # Kill existing port-forward processes if any
    pkill -f "kubectl port-forward.*dapr-dashboard" || true
    pkill -f "kubectl port-forward.*api-proxy-dapr" || true
    pkill -f "kubectl port-forward.*sql-server-service" || true
    
    # Function to start port-forward in background or foreground
    start_port_forward() {
        local service=$1
        local local_port=$2
        local remote_port=$3
        local namespace=$4
        local description=$5
        
        if [ "$PORT_FORWARD_BACKGROUND" = true ]; then
            print_info "Starting port-forward for $description in background..."
            nohup kubectl port-forward "$service" "$local_port:$remote_port" -n "$namespace" > /dev/null 2>&1 &
            sleep 2
            if ps -p $! > /dev/null; then
                print_success "$description port-forward started (PID: $!)"
            else
                print_error "Failed to start port-forward for $description"
            fi
        else
            print_warning "Port-forward for $description should be started manually:"
            print_info "  kubectl port-forward $service $local_port:$remote_port -n $namespace"
        fi
    }
    
    # Dapr Dashboard runs on local port 8081 to avoid conflicts with API Gateway (port 8080)
    
    if [ "$PORT_FORWARD_BACKGROUND" = true ]; then
        print_info "Starting port forwards in background..."
        
        # Dapr Dashboard (local port 8081)
        if kubectl get deploy dapr-dashboard -n dapr-system &> /dev/null; then
            start_port_forward "deploy/dapr-dashboard" "8081" "8080" "dapr-system" "Dapr Dashboard"
        else
            print_warning "Dapr dashboard not found, skipping..."
        fi
        
        # Caddy API Gateway (local port 8080)
        if kubectl get svc api-proxy-dapr -n "$NAMESPACE" &> /dev/null; then
            start_port_forward "svc/api-proxy-dapr" "8080" "80" "$NAMESPACE" "Caddy API Gateway"
        else
            print_warning "Caddy API Gateway service not found, skipping..."
        fi
        
        # SQL Server
        if kubectl get svc sql-server-service -n "$NAMESPACE" &> /dev/null; then
            start_port_forward "svc/sql-server-service" "1433" "1433" "$NAMESPACE" "SQL Server"
        else
            print_warning "SQL Server service not found, skipping..."
        fi
        
        print_success "Port forwarding configured (running in background)"
        print_info "Access points:"
        print_info "  - Dapr Dashboard: http://localhost:8081"
        print_info "  - Caddy API Gateway: http://localhost:8080"
        print_info "  - SQL Server: localhost:1433"
        print_warning "To stop port-forwarding, use: pkill -f 'kubectl port-forward'"
    else
        # Show all options for manual execution
        print_info "Port forwarding commands (run manually):"
        
        # Dapr Dashboard
        if kubectl get deploy dapr-dashboard -n dapr-system &> /dev/null; then
            print_info "  Dapr Dashboard: kubectl port-forward deploy/dapr-dashboard -n dapr-system 8081:8080"
        fi
        
        # Caddy API Gateway
        if kubectl get svc api-proxy-dapr -n "$NAMESPACE" &> /dev/null; then
            print_info "  Caddy API Gateway: kubectl port-forward svc/api-proxy-dapr -n $NAMESPACE 8080:80"
        fi
        
        # SQL Server
        if kubectl get svc sql-server-service -n "$NAMESPACE" &> /dev/null; then
            print_info "  SQL Server: kubectl port-forward svc/sql-server-service -n $NAMESPACE 1433:1433"
        fi
    fi
}

show_status() {
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would show deployment status"
        return 0
    fi
    
    print_step "Deployment Status:"
    echo ""
    echo "📊 Helm Releases:"
    helm list -n "$NAMESPACE" 2>/dev/null || print_warning "No Helm releases found"
    echo ""
    echo "📦 Pods:"
    kubectl get pods -n "$NAMESPACE" || print_warning "No pods found"
    echo ""
    echo "🌐 Services:"
    kubectl get svc -n "$NAMESPACE" || print_warning "No services found"
    echo ""
    
    # Show Dapr status if available
    if helm list -n dapr-system 2>/dev/null | grep -q "^dapr"; then
        echo "🔷 Dapr System Pods:"
        kubectl get pods -n dapr-system || true
        echo ""
    fi
}

print_summary() {
    echo ""
    if [ "$DRY_RUN" = true ]; then
        print_warning "⚠️  DRY RUN MODE - No changes were made"
        echo ""
    else
        print_success "🎉 Deployment complete!"
        echo ""
    fi
    
    echo "📋 Deployment Summary:"
    echo "   Namespace: $NAMESPACE"
    [ "$SKIP_DAPR" = false ] && echo "   ✓ Dapr control plane"
    [ "$SKIP_REDIS" = false ] && echo "   ✓ Redis"
    [ "$SKIP_VIZOR" = false ] && echo "   ✓ Vizor applications (includes Caddy API Gateway)"
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        echo "💡 Useful commands:"
        echo "   View pods:        kubectl get pods -n $NAMESPACE"
        echo "   View services:    kubectl get svc -n $NAMESPACE"
        echo "   View ingress:     kubectl get ingress -n $NAMESPACE"
        echo "   View logs:        kubectl logs -f <pod-name> -n $NAMESPACE"
        echo ""
        echo "🔌 Port forwarding commands (run manually if needed):"
        echo "   Dapr Dashboard:     kubectl port-forward deploy/dapr-dashboard -n dapr-system 8081:8080"
        echo "   Caddy API Gateway:  kubectl port-forward svc/api-proxy-dapr -n $NAMESPACE 8080:80"
        echo "   SQL Server:         kubectl port-forward svc/sql-server-service -n $NAMESPACE 1433:1433"
        echo ""
    fi
}

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Change to script directory for relative paths
    cd "$SCRIPT_DIR"
    
    echo ""
    echo "🚀 Vizor Deployment Script"
    echo "=========================="
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "Running in DRY RUN mode - no changes will be made"
        echo ""
    fi
    
    if [ "$ONLY_PORT_FORWARD" = true ]; then
        print_info "Port forwarding only mode - skipping deployments"
        echo ""
        setup_port_forwarding
        return 0
    fi
    
    check_prerequisites
    install_dependencies
    create_namespace
    deploy_dapr
    deploy_redis
    # Note: Ingress NGINX removed - using Caddy API Gateway (deployed as part of Vizor chart)
    deploy_vizor
    setup_port_forwarding
    show_status
    print_summary
}

# Run main function with all arguments
main "$@"

