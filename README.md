# Jitsu Helm Chart

Official Helm chart for deploying [Jitsu](https://jitsu.com) - an open-source data ingestion and event streaming platform.

## Quick Start

### Production Deployment

```bash
helm install jitsu oci://registry-1.docker.io/stafftasticcharts/jitsu -f-<<EOF
ingress:
  host: "jitsu.example.com"
console:
  config:
    seedUserEmail: "me@example.com"
    seedUserPassword: "changeMe"
EOF
```

For production deployments, see [Production Deployment Guide](docs/production-deployment.md).

### Local Development (Kind/OrbStack)

For local development on Kind using OrbStack:

```bash
# Create Kind cluster
kind create cluster --config examples/local-kind/kind-config.yaml

# Install Nginx Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s

# Install Jitsu (MongoDB will be deployed automatically with ARM64 support)
helm dependency update
helm install jitsu . -f examples/local-kind/values.yaml --create-namespace --namespace jitsu --timeout 10m

# Setup access via port-forward
kubectl port-forward -n jitsu svc/jitsu-console 4000:3000 &
```

Access at: **http://localhost:4000** (credentials: `admin@jitsu.local` / `admin123`)

For complete local setup instructions, see [Local Setup Guide](docs/local-setup.md).

## Documentation

- **[Local Setup Guide](docs/local-setup.md)** - Complete guide for running Jitsu locally on Kind/OrbStack
- **[Production Deployment Guide](docs/production-deployment.md)** - Production configuration, upgrading, and best practices
- **[Adding Airbyte Connectors](docs/adding-airbyte-connectors.md)** - How to add custom Airbyte connectors (Google Analytics, Stripe, etc.)

## Key Features

- **Complete Jitsu Stack**: Console, Ingest, Rotor, Bulker, and Syncctl services
- **Bundled Dependencies**: PostgreSQL, MongoDB, Kafka, ClickHouse, and Redis (optional)
- **Flexible Configuration**: Environment-based config with secrets support
- **ARM64 Support**: Optimized for Apple Silicon with custom MongoDB deployment
- **Production Ready**: High-availability options, resource management, and scaling

## Components

| Component | Description |
|-----------|-------------|
| Console | Web-based management UI |
| Ingest | Event collection API |
| Rotor | Event routing engine |
| Bulker | Data loading service |
| Syncctl | Synchronization management |
| PostgreSQL | Metadata storage |
| MongoDB | Document storage |
| ClickHouse | Analytics database |
| Kafka | Message queue |

## Requirements

- Kubernetes 1.20+
- Helm 3.0+
- Persistent Volume support (for databases)

## Configuration

See [values.yaml](values.yaml) for all available configuration options.

Key configuration areas:
- **Ingress**: Configure hostnames and TLS
- **Authentication**: Set up OAuth providers or seed users
- **Resources**: Adjust CPU/memory limits
- **Dependencies**: Configure or disable bundled services
- **Storage**: Configure persistent volume sizes

## Important Notes

### ⚠️ Bitnami Dependencies

This chart uses Bitnami Helm charts for dependencies (PostgreSQL, Kafka, MongoDB, ClickHouse). Bitnami has retired their public catalog, so these dependencies won't receive updates. **For production use, deploy these services separately.**

See the [Production Deployment Guide](docs/production-deployment.md#dependencies) for details.

### ⚠️ ARM64 / Apple Silicon

The Bitnami MongoDB images don't support ARM64. The local setup automatically uses the official MongoDB image instead, configured in `examples/local-kind/values.yaml`. No additional steps needed!

See [Local Setup Guide](docs/local-setup.md) for complete instructions.

## Repository Structure

```
jitsu-chart/
├── Chart.yaml                      # Helm chart metadata
├── values.yaml                     # Default configuration values
├── templates/                      # Kubernetes manifests
├── docs/                          # Documentation
│   ├── local-setup.md            # Local development guide
│   └── production-deployment.md  # Production guide
├── examples/                      # Example configurations
│   └── local-kind/               # Local Kind setup
│       ├── kind-config.yaml      # Kind cluster config
│       ├── values.yaml           # Local values (includes ARM64 MongoDB)
│       ├── setup-access.sh       # Quick setup script
│       └── README.md             # Quick reference
└── scripts/                       # Helper scripts
    └── token-generator.py        # Token generation
```

## Version

- **Chart Version**: 0.0.0 (development)
- **App Version**: 2.11.0

## License

See [LICENSE](LICENSE)

## Links

- [Jitsu Website](https://jitsu.com)
- [Jitsu GitHub](https://github.com/jitsucom/jitsu)
- [Helm Chart Repository](https://github.com/stafftastic/jitsu-chart)
