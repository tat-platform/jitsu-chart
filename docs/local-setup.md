# Jitsu Local Development Setup on Kind/OrbStack

This guide helps you run Jitsu locally on a Kind cluster using OrbStack.

> **Note**: All local development files are located in `examples/local-kind/`

## Prerequisites

- OrbStack (for Docker/Kubernetes)
- Homebrew
- kubectl

## Components Deployed

- **Jitsu Services**: Console, Ingest, Rotor, Bulker, Syncctl
- **Databases**: PostgreSQL, MongoDB (custom deployment), ClickHouse
- **Message Queue**: Kafka
- **Ingress**: Nginx Ingress Controller

## Quick Start

### 1. Create the Kind Cluster

```bash
kind create cluster --config examples/local-kind/kind-config.yaml
```

### 2. Install Nginx Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s
```

### 3. Deploy MongoDB

The Bitnami MongoDB charts don't support ARM64 (Apple Silicon), so we use a custom MongoDB deployment:

```bash
kubectl apply -f examples/local-kind/mongodb-deployment.yaml
kubectl wait --for=condition=ready pod -l app=mongodb -n jitsu --timeout=120s
```

### 4. Install Jitsu

```bash
# Update Helm dependencies
helm dependency update

# Install Jitsu with local values
helm install jitsu . -f examples/local-kind/values.yaml --create-namespace --namespace jitsu --timeout 10m
```

### 5. Setup Local Access

Run the setup script to add the DNS entry and verify the deployment:

```bash
./examples/local-kind/setup-access.sh
```

Or manually add to `/etc/hosts`:

```bash
echo "127.0.0.1 jitsu.local" | sudo tee -a /etc/hosts
```

## Accessing Jitsu

### Web Console

Open your browser and navigate to:

```
http://jitsu.local
```

**Default Login Credentials:**
- Email: `admin@jitsu.local`
- Password: `admin123`

### API Endpoints

- **Console**: http://jitsu.local/
- **Ingest API**: http://jitsu.local/api/
- **Bulker API**: Accessible via internal services

## Verifying the Deployment

Check all pods are running:

```bash
kubectl get pods -n jitsu
```

Expected output should show all pods in `Running` or `Completed` status:

```
NAME                                   READY   STATUS      RESTARTS   AGE
jitsu-bulker-*                         1/1     Running     0          *
jitsu-clickhouse-shard0-0              1/1     Running     0          *
jitsu-console-*                        1/1     Running     0          *
jitsu-event-log-init-*                 0/1     Completed   0          *
jitsu-ingest-*                         1/1     Running     0          *
jitsu-kafka-controller-0               1/1     Running     0          *
jitsu-migration-*                      0/1     Completed   0          *
jitsu-postgresql-0                     1/1     Running     0          *
jitsu-rotor-*                          1/1     Running     0          *
jitsu-syncctl-*                        1/1     Running     0          *
jitsu-token-generator-*                0/1     Completed   0          *
mongodb-*                              1/1     Running     0          *
```

Check ingress:

```bash
kubectl get ingress -n jitsu
```

## Resource Configuration

The local setup uses minimal resources suitable for development:

- **Console**: 100m CPU / 128Mi RAM (limit: 500m / 512Mi)
- **Rotor**: 100m CPU / 128Mi RAM (limit: 500m / 512Mi)
- **Syncctl**: 100m CPU / 128Mi RAM (limit: 500m / 512Mi)
- **Bulker**: 100m CPU / 256Mi RAM (limit: 500m / 1Gi)
- **Ingest**: 100m CPU / 128Mi RAM (limit: 500m / 512Mi)

Dependencies also use reduced resources for local development.

## Database Credentials

### PostgreSQL
- Host: `jitsu-postgresql.jitsu.svc.cluster.local`
- Port: `5432`
- Database: `jitsu`
- Username: `postgres`
- Password: `jitsu123`

### MongoDB
- Host: `mongodb.jitsu.svc.cluster.local`
- Port: `27017`
- Username: `admin`
- Password: `jitsu123`
- Database: `jitsu`
- Auth Source: `admin`

### ClickHouse
- HTTP Host: `jitsu-clickhouse.jitsu.svc.cluster.local:8123`
- TCP Host: `jitsu-clickhouse.jitsu.svc.cluster.local:9000`
- Username: `default`
- Password: `jitsu123`
- Database: `newjitsu_metrics`

### Kafka
- Bootstrap Servers: `jitsu-kafka.jitsu.svc.cluster.local:9092`

## Troubleshooting

### Pods in CrashLoopBackOff

Check the logs of the failing pod:

```bash
kubectl logs -n jitsu <pod-name> --previous
```

### Ingress Not Working

Verify the ingress controller is running:

```bash
kubectl get pods -n ingress-nginx
```

Check ingress configuration:

```bash
kubectl describe ingress -n jitsu jitsu
```

### MongoDB Connection Issues

Verify MongoDB is running and accessible:

```bash
kubectl exec -it -n jitsu mongodb-<pod-id> -- mongosh -u admin -p jitsu123
```

### Resetting the Installation

To completely remove and reinstall:

```bash
# Delete the Helm release
helm uninstall jitsu -n jitsu

# Delete the MongoDB deployment
kubectl delete -f examples/local-kind/mongodb-deployment.yaml

# Delete the namespace (optional - removes all data)
kubectl delete namespace jitsu

# Recreate
kubectl create namespace jitsu
kubectl apply -f examples/local-kind/mongodb-deployment.yaml
helm install jitsu . -f examples/local-kind/values.yaml -n jitsu --timeout 10m
```

## Deleting the Cluster

When you're done:

```bash
kind delete cluster --name jitsu-local
```

## Configuration Files

All local development files are in `examples/local-kind/`:

- `kind-config.yaml` - Kind cluster configuration
- `values.yaml` - Jitsu Helm values for local development
- `mongodb-deployment.yaml` - Custom MongoDB deployment for ARM64 compatibility
- `setup-access.sh` - Quick setup script

## Notes

- This setup is optimized for local development on Apple Silicon (ARM64)
- The Bitnami dependency images have ARM64 compatibility issues, which is why MongoDB is deployed separately
- TLS/HTTPS is disabled for local development
- SignUp is enabled by default for testing
- Resource limits are set low to work on development machines

## Upgrading Jitsu

To upgrade to a newer version:

```bash
# Update dependencies
helm dependency update

# Upgrade the release
helm upgrade jitsu . -f examples/local-kind/values.yaml -n jitsu --timeout 10m
```

## Monitoring

View logs from all Jitsu components:

```bash
# Console logs
kubectl logs -f -n jitsu -l app.kubernetes.io/component=console

# Ingest logs
kubectl logs -f -n jitsu -l app.kubernetes.io/component=ingest

# Bulker logs
kubectl logs -f -n jitsu -l app.kubernetes.io/component=bulker

# Rotor logs
kubectl logs -f -n jitsu -l app.kubernetes.io/component=rotor
```

## Support

For issues specific to this Helm chart, see the [main README](../README.md) or check the [GitHub repository](https://github.com/stafftastic/jitsu-chart).
