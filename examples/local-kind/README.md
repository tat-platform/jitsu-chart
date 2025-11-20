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

## Quick Reference

### Application URLs (via port-forward)
- **Console UI**: http://localhost:4000
- **Ingest API**: http://localhost:4000/api/s/s2s/track
- **Health Check**: http://localhost:4000/api/healthcheck

### Service Ports (inside cluster)
- **Console**: 3000
- **Ingest**: 3000
- **Bulker**: 3042
- **Rotor**: 3401
- **Syncctl**: 3043

### Database Ports (port-forward for external access)
```bash
# PostgreSQL
kubectl port-forward -n jitsu svc/jitsu-postgresql 5432:5432 &
# Connection: postgresql://postgres:jitsu123@localhost:5432/jitsu

# MongoDB
kubectl port-forward -n jitsu svc/jitsu-mongodb 27017:27017 &
# Connection: mongodb://jitsu:jitsu123@localhost:27017/jitsu?authSource=admin

# ClickHouse
kubectl port-forward -n jitsu svc/jitsu-clickhouse 8123:8123 9000:9000 &
# HTTP: http://default:jitsu123@localhost:8123/
# TCP: localhost:9000

# Kafka
kubectl port-forward -n jitsu svc/jitsu-kafka 9092:9092 &
# Bootstrap: localhost:9092

# Redis
kubectl port-forward -n jitsu svc/jitsu-redis-master 6379:6379 &
# Connection: redis-cli -h localhost -p 6379 -a jitsu123
```

## Complete Documentation

See the [Local Setup Guide](../../docs/guides/local-setup.md) for complete instructions, troubleshooting, and configuration details.

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
