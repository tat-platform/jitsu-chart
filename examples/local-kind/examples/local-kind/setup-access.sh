#!/bin/bash

echo "🚀 Setting up local access to Jitsu..."
echo ""

# Check if jitsu.local is already in /etc/hosts
if grep -q "jitsu.local" /etc/hosts; then
    echo "✅ jitsu.local already in /etc/hosts"
else
    echo "📝 Adding jitsu.local to /etc/hosts (requires sudo password)..."
    echo "127.0.0.1 jitsu.local" | sudo tee -a /etc/hosts
    echo "✅ Added jitsu.local to /etc/hosts"
fi

echo ""
echo "🔍 Checking deployment status..."
echo ""

# Check if all pods are running
kubectl get pods -n jitsu

echo ""
echo "🌐 Ingress configuration:"
kubectl get ingress -n jitsu

echo ""
echo "✨ Setup complete!"
echo ""
echo "📍 Access Jitsu at: http://jitsu.local"
echo ""
echo "🔑 Default login credentials:"
echo "   Email: admin@jitsu.local"
echo "   Password: admin123"
echo ""
echo "💡 If you can't access http://jitsu.local, make sure:"
echo "   1. All pods are running (check above)"
echo "   2. Port 80 is not being used by another application"
echo "   3. The ingress controller is running in the ingress-nginx namespace"
echo ""
