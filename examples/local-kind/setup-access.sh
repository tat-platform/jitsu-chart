#!/bin/bash

echo "🚀 Setting up local access to Jitsu..."
echo ""

echo "🔍 Checking deployment status..."
echo ""

# Check if all pods are running
kubectl get pods -n jitsu

echo ""
echo "🌐 Ingress configuration:"
kubectl get ingress -n jitsu

echo ""
echo "📡 Starting port-forward to console (port 4000)..."

# Kill any existing port-forwards on port 4000
lsof -ti:4000 | xargs kill -9 2>/dev/null || true

# Start port-forward in background
kubectl port-forward -n jitsu svc/jitsu-console 4000:3000 > /dev/null 2>&1 &
PF_PID=$!

# Wait a moment for port-forward to establish
sleep 2

# Check if port-forward is running
if lsof -i:4000 > /dev/null 2>&1; then
    echo "✅ Port-forward established on port 4000 (PID: $PF_PID)"
else
    echo "❌ Failed to establish port-forward"
    exit 1
fi

echo ""
echo "✨ Setup complete!"
echo ""
echo "📍 Access Jitsu at: http://localhost:4000"
echo ""
echo "🔑 Default login credentials:"
echo "   Email: admin@jitsu.local"
echo "   Password: admin123"
echo ""
echo "💡 Notes:"
echo "   - Port-forward is running in background (PID: $PF_PID)"
echo "   - To stop: kill $PF_PID"
echo "   - If connection fails, restart with: kubectl port-forward -n jitsu svc/jitsu-console 4000:3000 &"
echo ""
echo "⚠️  Port 80 access via jitsu.local doesn't work reliably on OrbStack/Kind on macOS"
echo "   That's why we use port-forward to localhost:4000 instead"
echo ""
