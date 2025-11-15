# Jitsu Helm Chart Documentation

Complete documentation for deploying and managing Jitsu on Kubernetes.

## Quick Links

### Getting Started
- **[Local Setup Guide](local-setup.md)** - Run Jitsu locally on Kind with OrbStack (macOS/ARM64 optimized)
- **[Production Deployment Guide](production-deployment.md)** - Production configuration, scaling, and best practices

### Extending Jitsu
- **[Adding Airbyte Connectors](adding-airbyte-connectors.md)** - Add 300+ connectors (Google Analytics, Stripe, PostgreSQL, etc.)

## Documentation Overview

### [Local Setup Guide](local-setup.md)

Complete guide for running Jitsu locally:
- Kind cluster setup with OrbStack
- ARM64/Apple Silicon compatibility (MongoDB)
- Port-forward access configuration
- Troubleshooting common issues
- Development workflow

**Perfect for:** Local development, testing, learning Jitsu

### [Production Deployment Guide](production-deployment.md)

Production-ready deployment:
- Helm installation and configuration
- High availability setup
- Resource management
- Ingress and TLS configuration
- Scaling strategies
- Upgrading procedures
- Security best practices

**Perfect for:** Production deployments, staging environments

### [Adding Airbyte Connectors](adding-airbyte-connectors.md)

Extend Jitsu with custom connectors:
- Quick start guide (Google Analytics example)
- Helper script usage
- 30+ popular connector examples
- Manual database insertion method
- Troubleshooting connector issues
- Technical details on how connectors work

**Perfect for:** Extending Jitsu beyond the 4 default connectors

## Common Tasks

### Start Jitsu Locally

```bash
# From repository root
kind create cluster --config examples/local-kind/kind-config.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s
helm dependency update
helm install jitsu . -f examples/local-kind/values.yaml --create-namespace --namespace jitsu --timeout 10m
kubectl port-forward -n jitsu svc/jitsu-console 4000:3000 &
```

Access: **http://localhost:4000** (admin@jitsu.local / admin123)

### Add a Connector

```bash
# Using helper script
./scripts/add-connector.sh airbyte-stripe airbyte/source-stripe "Stripe"

# Or manually
kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c \
  'export PGPASSWORD=jitsu123 && psql -U jitsu -d jitsu -c \
  "INSERT INTO newjitsu.\"ConnectorPackage\" (id, \"packageId\", \"packageType\", meta) \
   VALUES ('\''airbyte-stripe'\'', '\''airbyte/source-stripe'\'', '\''airbyte'\'', \
           '\''{\"name\": \"Stripe\"}'\''::jsonb);"'
```

### Deploy to Production

```bash
helm install jitsu oci://registry-1.docker.io/stafftasticcharts/jitsu -f-<<EOF
ingress:
  host: "jitsu.example.com"
console:
  config:
    seedUserEmail: "admin@example.com"
    seedUserPassword: "secure-password"
EOF
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Jitsu Stack                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Console (UI)          Ingest (Events)                 │
│  Rotor (Streaming)     Bulker (Data Loading)           │
│  Syncctl (Airbyte)                                     │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                   Dependencies                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  PostgreSQL   MongoDB   ClickHouse   Kafka   Redis     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Key Features

- ✅ **Complete Stack** - All Jitsu services included
- ✅ **Airbyte Integration** - 300+ data source connectors
- ✅ **ARM64 Support** - Optimized for Apple Silicon
- ✅ **Production Ready** - HA, scaling, security best practices
- ✅ **Easy Local Development** - Kind + OrbStack setup
- ✅ **Flexible Configuration** - Helm values + secrets

## Support & Resources

- **Jitsu Documentation**: https://jitsu.com/docs
- **Jitsu GitHub**: https://github.com/jitsucom/jitsu
- **Helm Chart Issues**: https://github.com/[your-repo]/issues
- **Airbyte Connectors**: https://docs.airbyte.com/integrations/

## Version Information

- **Chart Version**: 0.0.0 (development)
- **Jitsu Version**: 2.11.0
- **Kubernetes**: 1.24+
- **Helm**: 3.0+

## Contributing

Found an issue or have a suggestion? Please open an issue or submit a pull request!

## License

This Helm chart is provided under the same license as Jitsu. See LICENSE for details.
