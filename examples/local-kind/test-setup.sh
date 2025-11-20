#!/bin/bash
set -e

echo "🧪 Testing Jitsu Local Setup..."
echo ""

# Check if Kind cluster exists
echo "1️⃣ Checking Kind cluster..."
if ! kind get clusters | grep -q "jitsu-local"; then
    echo "❌ Kind cluster 'jitsu-local' not found"
    echo "   Run: kind create cluster --config examples/local-kind/kind-config.yaml"
    exit 1
fi
echo "✅ Kind cluster 'jitsu-local' exists"
echo ""

# Check if namespace exists
echo "2️⃣ Checking jitsu namespace..."
if ! kubectl get namespace jitsu &>/dev/null; then
    echo "❌ Namespace 'jitsu' not found"
    echo "   Run: helm install jitsu . -f examples/local-kind/values.yaml --create-namespace --namespace jitsu --timeout 10m"
    exit 1
fi
echo "✅ Namespace 'jitsu' exists"
echo ""

# Check if Helm release exists
echo "3️⃣ Checking Helm release..."
if ! helm list -n jitsu | grep -q "jitsu"; then
    echo "❌ Helm release 'jitsu' not found"
    echo "   Run: helm install jitsu . -f examples/local-kind/values.yaml --create-namespace --namespace jitsu --timeout 10m"
    exit 1
fi
echo "✅ Helm release 'jitsu' deployed"
echo ""

# Check pod status
echo "4️⃣ Checking pod status..."
NOT_RUNNING=$(kubectl get pods -n jitsu --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l | xargs)
if [ "$NOT_RUNNING" -gt 0 ]; then
    echo "⚠️  Warning: $NOT_RUNNING pod(s) not in Running/Completed state:"
    kubectl get pods -n jitsu | grep -v "Running\|Completed" | tail -n +2
    echo ""
fi

TOTAL_PODS=$(kubectl get pods -n jitsu --no-headers | wc -l | xargs)
RUNNING_PODS=$(kubectl get pods -n jitsu --no-headers | grep -E "Running|Completed" | wc -l | xargs)
echo "✅ Pods status: $RUNNING_PODS/$TOTAL_PODS Running/Completed"
echo ""

# Check key services
echo "5️⃣ Checking key services..."
SERVICES=(
    "jitsu-console"
    "jitsu-postgresql"
    "jitsu-mongodb"
    "jitsu-clickhouse"
    "jitsu-kafka"
)

for svc in "${SERVICES[@]}"; do
    if kubectl get svc -n jitsu "$svc" &>/dev/null; then
        echo "   ✅ $svc"
    else
        echo "   ❌ $svc (not found)"
    fi
done
echo ""

# Test console connectivity
echo "6️⃣ Testing console connectivity..."
if kubectl get pod -n jitsu -l app.kubernetes.io/component=console -o name &>/dev/null; then
    CONSOLE_POD=$(kubectl get pod -n jitsu -l app.kubernetes.io/component=console -o name | head -1)
    if [ -n "$CONSOLE_POD" ]; then
        echo "✅ Console pod found: $CONSOLE_POD"

        # Test if port 3000 is listening
        if kubectl exec -n jitsu "$CONSOLE_POD" -- sh -c "nc -z localhost 3000" &>/dev/null; then
            echo "✅ Console listening on port 3000"
        else
            echo "⚠️  Console may not be ready yet (port 3000 not responding)"
        fi
    fi
else
    echo "❌ Console pod not found"
fi
echo ""

# Check MongoDB
echo "7️⃣ Testing MongoDB connection..."
MONGO_POD=$(kubectl get pod -n jitsu -l app.kubernetes.io/name=mongodb -o name 2>/dev/null | head -1)
if [ -n "$MONGO_POD" ]; then
    if kubectl exec -n jitsu "$MONGO_POD" -- mongosh --quiet --eval "db.version()" &>/dev/null 2>&1; then
        MONGO_VERSION=$(kubectl exec -n jitsu "$MONGO_POD" -- mongosh --quiet --eval "db.version()" 2>/dev/null)
        echo "✅ MongoDB connected (version: $MONGO_VERSION)"
    else
        echo "⚠️  MongoDB pod exists but connection test failed"
    fi
else
    echo "❌ MongoDB pod not found"
fi
echo ""

# Check PostgreSQL
echo "8️⃣ Testing PostgreSQL connection..."
if kubectl get pod -n jitsu jitsu-postgresql-0 &>/dev/null; then
    if kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c "PGPASSWORD=jitsu123 psql -U postgres -c 'SELECT 1;'" &>/dev/null 2>&1; then
        echo "✅ PostgreSQL connected"
    else
        echo "⚠️  PostgreSQL pod exists but connection test failed"
    fi
else
    echo "❌ PostgreSQL pod not found"
fi
echo ""

# Check if port-forward is needed
echo "9️⃣ Checking access method..."
if lsof -i:4000 &>/dev/null; then
    echo "✅ Port 4000 is in use (port-forward likely running)"
    echo "   Access Jitsu at: http://localhost:4000"
else
    echo "⚠️  Port 4000 not in use"
    echo "   Start port-forward: kubectl port-forward -n jitsu svc/jitsu-console 4000:3000 &"
    echo "   Then access: http://localhost:4000"
fi
echo ""

# Summary
echo "=========================================="
echo "📊 Setup Summary"
echo "=========================================="
echo "Cluster: jitsu-local (Kind)"
echo "Namespace: jitsu"
echo "Release: jitsu"
echo "Pods: $RUNNING_PODS/$TOTAL_PODS Running/Completed"
echo ""
echo "🔑 Default Credentials:"
echo "  Email: admin@jitsu.local"
echo "  Password: admin123"
echo ""
echo "🌐 Access URL: http://localhost:4000"
echo "  (Requires port-forward to be running)"
echo ""
echo "✨ All checks complete!"
