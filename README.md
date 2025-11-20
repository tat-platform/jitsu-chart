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

For production deployments, see [Production Deployment Guide](docs/guides/production-deployment.md).

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

For complete local setup instructions, see [Local Setup Guide](docs/guides/local-setup.md).

## Documentation

### 📚 Complete Documentation Hub
See **[docs/README.md](docs/README.md)** for the complete documentation index with:
- Local development and production deployment guides
- Cloud platform deployment guides (AWS, DigitalOcean, Huawei Cloud)
- Cost vs performance comparisons
- Airbyte connector integration

### 🚀 Quick Links
- **[Local Setup Guide](docs/guides/local-setup.md)** - Run Jitsu locally on Kind/OrbStack (ARM64 compatible)
- **[Production Deployment Guide](docs/guides/production-deployment.md)** - Production configuration and best practices
- **[Adding Airbyte Connectors](docs/guides/adding-airbyte-connectors.md)** - Extend with 300+ data sources
- **[Deployment Comparison](docs/deployments/deployment-comparison.md)** - Compare costs ($480-$8,500/mo) and performance

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

See the [Production Deployment Guide](docs/guides/production-deployment.md#dependencies) for details.

### ⚠️ ARM64 / Apple Silicon

The Bitnami MongoDB images don't support ARM64. The local setup automatically uses the official MongoDB image instead, configured in `examples/local-kind/values.yaml`. No additional steps needed!

See [Local Setup Guide](docs/guides/local-setup.md) for complete instructions.

## Repository Structure

```
jitsu-chart/
├── Chart.yaml                      # Helm chart metadata
├── values.yaml                     # Default configuration values
├── templates/                      # Kubernetes manifests
├── docs/                          # 📚 Documentation hub
│   ├── README.md                  # Documentation index and navigation
│   ├── guides/                    # Setup and configuration guides
│   │   ├── local-setup.md        # Local development (Kind/OrbStack)
│   │   ├── production-deployment.md # Production best practices
│   │   └── adding-airbyte-connectors.md # Extend with 300+ connectors
│   └── deployments/               # Cloud platform deployment guides
│       ├── deployment-comparison.md # Cost vs performance analysis
│       ├── digitalocean-deployment.md # $480-1,200/mo (best value)
│       ├── huawei-cce-deployment.md # $1,400/mo (Asia-Pacific)
│       ├── aws-baremetal-deployment.md # $2,700/mo (full control)
│       ├── aws-eks-deployment.md # $3,900/mo (enterprise AWS)
│       └── cloudflare-hybrid-deployment.md # Add to any deployment
├── examples/                      # Example configurations
│   └── local-kind/               # 🏠 Local Kind setup
│       ├── kind-config.yaml      # Kind cluster config (3 nodes)
│       ├── values.yaml           # Local values (ARM64 MongoDB support)
│       ├── setup-access.sh       # Port-forward setup script
│       ├── test-setup.sh         # Validation and health check script
│       └── README.md             # Quick reference guide
└── scripts/                       # Helper scripts
    ├── add-connector.sh          # Add Airbyte connectors easily
    └── token-generator.py        # Token generation utility
```

## Tested and Verified ✅

This chart has been tested and verified on:
- ✅ **macOS** (Apple Silicon M1/M2/M3) with OrbStack + Kind
- ✅ **Kubernetes** 1.24+ (Kind v1.34.0)
- ✅ **Helm** 3.0+
- ✅ **MongoDB** 7.0.15 (ARM64 compatible)

All components successfully deployed and tested:
- Console, Ingest, Rotor, Bulker, Syncctl
- PostgreSQL, MongoDB, ClickHouse, Kafka, Redis
- Health checks passing
- API endpoints accessible

## Common Tasks

### Validate Local Setup
```bash
./examples/local-kind/test-setup.sh
```

### Add Airbyte Connectors
```bash
# Using helper script
./scripts/add-connector.sh airbyte-google-analytics-data-api \
  airbyte/source-google-analytics-data-api "Google Analytics (GA4)"

# Or manually via PostgreSQL
kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c \
  'PGPASSWORD=jitsu123 psql -U jitsu -d jitsu -c \
  "INSERT INTO newjitsu.\"ConnectorPackage\" ..."'
```

See [Adding Airbyte Connectors](docs/guides/adding-airbyte-connectors.md) for 30+ connector examples.

### Access Services via Port-Forward
```bash
# Console
kubectl port-forward -n jitsu svc/jitsu-console 4000:3000 &

# PostgreSQL
kubectl port-forward -n jitsu svc/jitsu-postgresql 5432:5432 &

# MongoDB
kubectl port-forward -n jitsu svc/jitsu-mongodb 27017:27017 &
```

### View Logs
```bash
# Console logs
kubectl logs -f -n jitsu -l app.kubernetes.io/component=console

# All services
kubectl logs -f -n jitsu -l app.kubernetes.io/instance=jitsu
```

## Troubleshooting

### MongoDB ARM64 Issues
If you see `ImagePullBackOff` for MongoDB on ARM64:
- The local values already use `mongo:7.0.15` instead of Bitnami
- Ensure you're using `examples/local-kind/values.yaml` for local deployments

### Port 80 Not Working on macOS
This is a known limitation with Kind + OrbStack on macOS:
- Use port-forward instead: `kubectl port-forward -n jitsu svc/jitsu-console 4000:3000`
- Access at `http://localhost:4000`

### Authentication Issues
Ensure `nextauthUrl` matches your access method:
- Local (port-forward): `http://localhost:4000`
- Ingress: `http://your-domain.com`

See [Local Setup Guide](docs/guides/local-setup.md#troubleshooting) for more.

## Production Deployment Options

| Platform | Monthly Cost | Setup Time | Best For |
|----------|-------------|------------|----------|
| [DigitalOcean + Cloudflare](docs/deployments/digitalocean-deployment.md) | $480 | 1 hour | Startups, MVPs |
| [Huawei Cloud CCE](docs/deployments/huawei-cce-deployment.md) | $1,400 | 2 hours | China/Asia-Pacific |
| [AWS Bare Metal](docs/deployments/aws-baremetal-deployment.md) | $2,700 | 4 hours | Full K8s control |
| [AWS EKS](docs/deployments/aws-eks-deployment.md) | $3,900 | 3 hours | Enterprise AWS |
| Multi-Region AWS | $8,500 | 8 hours | Global SaaS |

See [Deployment Comparison](docs/deployments/deployment-comparison.md) for detailed analysis.

## Version

- **Chart Version**: 0.0.0 (development)
- **App Version**: 2.11.0 (Jitsu)
- **Tested Kubernetes**: 1.24+ (Kind v1.34.0)
- **MongoDB Version**: 7.0.15 (ARM64 compatible)

## Contributing

Issues and pull requests are welcome! Please:
1. Check existing issues before creating new ones
2. Test changes locally with `examples/local-kind/test-setup.sh`
3. Update documentation as needed
4. Follow the existing code style

## License

See [LICENSE](LICENSE)

## Links

- **[Jitsu Website](https://jitsu.com)** - Official website
- **[Jitsu GitHub](https://github.com/jitsucom/jitsu)** - Main Jitsu repository
- **[Jitsu Documentation](https://jitsu.com/docs)** - Official Jitsu docs
- **[Helm Chart Repository](https://github.com/stafftastic/jitsu-chart)** - This repository
- **[Airbyte Connectors](https://docs.airbyte.com/integrations/)** - 300+ available connectors

## Support

- 📖 **Documentation**: See [docs/README.md](docs/README.md)
- 🐛 **Issues**: [GitHub Issues](https://github.com/stafftastic/jitsu-chart/issues)
- 💬 **Discussions**: [Jitsu Community](https://jitsu.com/community)
