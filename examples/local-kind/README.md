# Local Kind Setup for Jitsu

This directory contains all the files needed to run Jitsu locally on a Kind cluster with OrbStack.

## Files

- **`kind-config.yaml`** - Kind cluster configuration with 1 control-plane and 2 worker nodes
- **`values.yaml`** - Helm values optimized for local development (includes ARM64-compatible MongoDB)
- **`setup-access.sh`** - Quick setup script to configure `/etc/hosts` and verify deployment
- **`README.md`** - This file

## Quick Start

From the repository root:

```bash
# 1. Create Kind cluster
kind create cluster --config examples/local-kind/kind-config.yaml

# 2. Install Nginx Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s

# 3. Install Jitsu (MongoDB included with ARM64 support)
helm dependency update
helm install jitsu . -f examples/local-kind/values.yaml --create-namespace --namespace jitsu --timeout 10m

# 4. Setup access (port-forward)
kubectl port-forward -n jitsu svc/jitsu-console 4000:3000 &
```

Then open **http://localhost:4000** in your browser.

**Login**: `admin@jitsu.local` / `admin123`

**Note**: Due to OrbStack/Kind limitations on macOS, port 80 routing doesn't work reliably. We use port-forwarding to port 4000 instead.

## Complete Documentation

See the [Local Setup Guide](../../docs/local-setup.md) for complete instructions, troubleshooting, and configuration details.

## Key Configuration

This local setup includes:

- **Minimal Resources**: All services use reduced CPU/memory for development
- **No TLS**: HTTP only for simplicity
- **ARM64 MongoDB**: Automatically uses official `mongo:7.0.15` image for ARM64 compatibility
- **Single Replicas**: All databases run with 1 replica
- **Development Passwords**: Simple passwords (not for production!)

## Notes

- Optimized for Apple Silicon (ARM64)
- MongoDB automatically uses official `mongo:7.0.15` image (Bitnami doesn't support ARM64)
- The MongoDB image override is configured in `values.yaml` with proper security contexts
- All services deployed via Helm chart (no manual deployments needed)
- Access via port-forward to `localhost:4000` (port 80 doesn't work reliably on OrbStack/Kind on macOS)
- URLs configured for localhost access in `values.yaml`
