# Local Kind Setup for Jitsu

This directory contains all the files needed to run Jitsu locally on a Kind cluster with OrbStack.

## Files

- **`kind-config.yaml`** - Kind cluster configuration with 1 control-plane and 2 worker nodes
- **`values.yaml`** - Helm values optimized for local development (minimal resources)
- **`mongodb-deployment.yaml`** - Custom MongoDB deployment for ARM64 compatibility
- **`setup-access.sh`** - Quick setup script to configure `/etc/hosts` and verify deployment

## Quick Start

From the repository root:

```bash
# 1. Create Kind cluster
kind create cluster --config examples/local-kind/kind-config.yaml

# 2. Install Nginx Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s

# 3. Deploy MongoDB
kubectl apply -f examples/local-kind/mongodb-deployment.yaml

# 4. Install Jitsu
helm dependency update
helm install jitsu . -f examples/local-kind/values.yaml --create-namespace --namespace jitsu --timeout 10m

# 5. Setup access
./examples/local-kind/setup-access.sh
```

Then open http://jitsu.local in your browser.

**Login**: `admin@jitsu.local` / `admin123`

## Complete Documentation

See the [Local Setup Guide](../../docs/local-setup.md) for complete instructions, troubleshooting, and configuration details.

## Key Configuration

This local setup includes:

- **Minimal Resources**: All services use reduced CPU/memory for development
- **No TLS**: HTTP only for simplicity
- **Custom MongoDB**: Using official MongoDB image for ARM64 support
- **Single Replicas**: All databases run with 1 replica
- **Development Passwords**: Simple passwords (not for production!)

## Notes

- Optimized for Apple Silicon (ARM64)
- MongoDB uses official `mongo:7.0` image due to Bitnami ARM64 issues
- All services accessible via `jitsu.local` (requires `/etc/hosts` entry)
- Port 80 must be available on your host machine
