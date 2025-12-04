#!/bin/bash

# Quick script to run migration job directly
# Usage: ./run-migration-job.sh [namespace] [--wait]

set -e

# Parse arguments
WAIT_FOR_COMPLETION=false
NAMESPACE="vizor"

while [[ $# -gt 0 ]]; do
    case $1 in
        --wait)
            WAIT_FOR_COMPLETION=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [namespace] [--wait]"
            echo ""
            echo "Options:"
            echo "  namespace    Kubernetes namespace (default: vizor)"
            echo "  --wait       Wait for job to complete before exiting"
            echo "  --help, -h   Show this help message"
            echo ""
            exit 0
            ;;
        *)
            if [ "$NAMESPACE" = "vizor" ] && [[ ! "$1" =~ ^-- ]]; then
                NAMESPACE="$1"
            else
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Running Migration Job..."
echo "Namespace: $NAMESPACE"
echo ""

cd "$SCRIPT_DIR"

# Check if PowerBI database exists first (migration requires it)
echo "🔍 Checking if PowerBI database exists..."
SQL_USER="${SQL_USER:-sa}"
SQL_PASSWORD="${SQL_PASSWORD:-P@55w0rd}"
SQL_SERVER="${SQL_SERVER:-sql-server-service}"
SQL_PORT="${SQL_PORT:-1433}"
POWERBI_DB_NAME="PowerBI"

# Check if PowerBI database exists using a temporary pod
CHECK_POD="migration-check-powerbi-$(date +%s | cut -c9-)"
kubectl run "$CHECK_POD" -n "$NAMESPACE" \
    --image=mcr.microsoft.com/mssql-tools \
    --restart=Never \
    --command -- \
    /opt/mssql-tools/bin/sqlcmd \
    -S "$SQL_SERVER,$SQL_PORT" \
    -U "$SQL_USER" \
    -P "$SQL_PASSWORD" \
    -Q "SELECT CASE WHEN EXISTS(SELECT name FROM sys.databases WHERE name='$POWERBI_DB_NAME') THEN 'EXISTS' ELSE 'NOT_EXISTS' END" \
    -h -1 -W \
    > /dev/null 2>&1 || true

# Wait for pod to complete
wait_attempt=0
db_exists="NOT_EXISTS"
while [ $wait_attempt -lt 30 ]; do
    phase=$(kubectl get pod "$CHECK_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$phase" = "Succeeded" ]; then
        db_exists=$(kubectl logs "$CHECK_POD" -n "$NAMESPACE" 2>/dev/null | tr -d '\r\n ' || echo "NOT_EXISTS")
        break
    elif [ "$phase" = "Failed" ]; then
        break
    fi
    sleep 1
    wait_attempt=$((wait_attempt + 1))
done

# Cleanup pod
kubectl delete pod "$CHECK_POD" -n "$NAMESPACE" > /dev/null 2>&1 || true

if [ "$db_exists" != "EXISTS" ]; then
    echo "⚠️  WARNING: PowerBI database does not exist!"
    echo "   Migration job requires PowerBI database to exist."
    echo "   Please run PowerBI setup job first:"
    echo "   ./run-powerbi-job.sh $NAMESPACE"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Aborted"
        exit 1
    fi
    echo "⚠️  Proceeding despite missing PowerBI database..."
else
    echo "✅ PowerBI database exists"
fi

echo ""

# Generate job YAML from Helm template
echo "📝 Generating migration job YAML..."
helm template vizor ./helm/vizor \
  --namespace "$NAMESPACE" \
  --show-only templates/components/migrations-job.yaml \
  > /tmp/migrations-job.yaml

# Remove Helm hook annotations
echo "🔧 Removing Helm hook annotations..."
sed -i.bak '/helm.sh\/hook/d' /tmp/migrations-job.yaml 2>/dev/null || \
sed -i '' '/helm.sh\/hook/d' /tmp/migrations-job.yaml 2>/dev/null || true
rm -f /tmp/migrations-job.yaml.bak 2>/dev/null || true

# Remove ArgoCD hook annotations too
sed -i.bak '/argocd.argoproj.io\/hook/d' /tmp/migrations-job.yaml 2>/dev/null || \
sed -i '' '/argocd.argoproj.io\/hook/d' /tmp/migrations-job.yaml 2>/dev/null || true
rm -f /tmp/migrations-job.yaml.bak 2>/dev/null || true

# Ensure namespace is set in metadata
if ! grep -A 5 "^metadata:" /tmp/migrations-job.yaml | grep -q "namespace:"; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' '/^metadata:/a\
  namespace: '"$NAMESPACE"'
' /tmp/migrations-job.yaml
    else
        sed -i '/^metadata:/a\  namespace: '"$NAMESPACE"'' /tmp/migrations-job.yaml
    fi
fi

# Check if job already exists
JOB_NAME="vizor-migrations"
JOB_EXISTS=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" 2>/dev/null && echo "yes" || echo "no")

if [ "$JOB_EXISTS" = "yes" ]; then
    JOB_STATUS=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
    JOB_FAILED=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
    
    if [ "$JOB_STATUS" = "True" ]; then
        echo "ℹ️  Job already exists and completed"
        echo "   To rerun, delete it first: kubectl delete job $JOB_NAME -n $NAMESPACE"
        read -p "Delete and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "🗑️  Deleting existing job..."
            kubectl delete job "$JOB_NAME" -n "$NAMESPACE" 2>/dev/null || true
            sleep 2
        else
            echo "❌ Aborted"
            exit 0
        fi
    elif [ "$JOB_FAILED" = "True" ]; then
        echo "⚠️  Job exists but failed. Deleting and recreating..."
        kubectl delete job "$JOB_NAME" -n "$NAMESPACE" 2>/dev/null || true
        sleep 2
    else
        echo "ℹ️  Job already exists and is running."
        read -p "Wait for completion or delete and recreate? (w/d/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Dd]$ ]]; then
            echo "🗑️  Deleting existing job..."
            kubectl delete job "$JOB_NAME" -n "$NAMESPACE" 2>/dev/null || true
            sleep 2
        elif [[ $REPLY =~ ^[Ww]$ ]]; then
            echo "⏳ Waiting for job to complete..."
            kubectl wait --for=condition=complete --timeout=600s job/"$JOB_NAME" -n "$NAMESPACE" 2>/dev/null && \
                echo "✅ Job completed successfully" || \
                echo "⚠️  Job did not complete within timeout"
            exit 0
        else
            echo "❌ Aborted"
            exit 0
        fi
    fi
fi

# Apply the job
echo "✅ Applying migration job to Kubernetes..."
kubectl apply -f /tmp/migrations-job.yaml -n "$NAMESPACE"

# Clean up temp file
rm -f /tmp/migrations-job.yaml

echo ""
echo "✅ Migration job created successfully!"
echo ""

# Wait for completion if --wait flag is set
if [ "$WAIT_FOR_COMPLETION" = true ]; then
    echo "⏳ Waiting for migration job to complete (timeout: 600s)..."
    if kubectl wait --for=condition=complete --timeout=600s job/"$JOB_NAME" -n "$NAMESPACE" 2>/dev/null; then
        echo "✅ Migration job completed successfully!"
        
        # Show job logs
        POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$POD_NAME" ]; then
            echo ""
            echo "📋 Job logs (last 30 lines):"
            kubectl logs "$POD_NAME" -n "$NAMESPACE" --tail=30 2>/dev/null || true
        fi
    else
        echo "⚠️  Migration job did not complete within timeout or encountered an error"
        echo ""
        echo "Check job status:"
        kubectl get job "$JOB_NAME" -n "$NAMESPACE" 2>&1 || true
        echo ""
        POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$POD_NAME" ]; then
            echo "Pod logs:"
            kubectl logs "$POD_NAME" -n "$NAMESPACE" --tail=50 2>/dev/null || true
        fi
        exit 1
    fi
else
    echo "Monitor job status:"
    echo "  kubectl get job $JOB_NAME -n $NAMESPACE -w"
    echo ""
    echo "Check job logs:"
    echo "  POD_NAME=\$(kubectl get pods -n $NAMESPACE -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}')"
    echo "  kubectl logs \$POD_NAME -n $NAMESPACE"
    echo ""
    echo "Wait for completion:"
    echo "  kubectl wait --for=condition=complete --timeout=600s job/$JOB_NAME -n $NAMESPACE"
    echo ""
    echo "Or run with --wait flag to automatically wait:"
    echo "  $0 $NAMESPACE --wait"
fi

