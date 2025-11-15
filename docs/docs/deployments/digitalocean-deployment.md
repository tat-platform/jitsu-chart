# Deploying Jitsu on DigitalOcean Kubernetes (DOKS)

This guide provides a complete, production-ready deployment of Jitsu on DigitalOcean Kubernetes Service (DOKS).

## Overview

This deployment includes:
- DOKS (DigitalOcean Kubernetes Service) managed cluster
- DigitalOcean Load Balancer for ingress
- Managed databases (PostgreSQL, MongoDB, Kafka)
- SSL/TLS certificates via Let's Encrypt
- Auto-scaling and high availability
- Block storage for persistent volumes
- **Cost: ~$500-800/month** (significantly cheaper than AWS/Huawei Cloud)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              DigitalOcean Load Balancer                 │
│           (with Let's Encrypt SSL)                      │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│         DOKS Cluster (Managed Kubernetes)               │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Jitsu Services                                  │  │
│  │  - Console (UI)                                  │  │
│  │  - Ingest (Event Collection)                     │  │
│  │  - Rotor (Stream Processing)                     │  │
│  │  - Bulker (Data Loading)                         │  │
│  │  - Syncctl (Airbyte Connectors)                  │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                     │
    ┌────────────────┼────────────────┐
    │                │                │
┌───▼─────┐   ┌─────▼──────┐   ┌────▼──────┐
│Managed  │   │  Managed   │   │  Kafka    │
│PostgreSQL   │  MongoDB   │   │ (Upstash) │
└─────────┘   └────────────┘   └───────────┘
```

---

## Prerequisites

### Required Tools

```bash
# Install doctl (DigitalOcean CLI)
brew install doctl

# Authenticate
doctl auth init
# Enter your DigitalOcean API token

# Install kubectl
brew install kubectl

# Install Helm
brew install helm
```

### DigitalOcean Account Requirements

- DigitalOcean account with billing enabled
- API token with read/write permissions
- Domain name (optional, for custom domain)

---

## Cost Comparison

### DigitalOcean DOKS vs AWS EKS vs Huawei CCE

| Component | DigitalOcean | AWS EKS | Huawei CCE |
|-----------|-------------|---------|------------|
| **Control Plane** | Free | $73 | Free |
| **Worker Nodes (3x)** | $120 (4GB/2vCPU) | $450 (t3.xlarge) | $125 (c6.xlarge.2) |
| **Data Nodes (2x)** | $192 (16GB/4vCPU) | $600 (r6i.xlarge) | $225 (m6.xlarge.8) |
| **Load Balancer** | $12 | $20 | $20 |
| **Managed PostgreSQL** | $60 (2GB) | $600 (r6g.xlarge) | $170 (c6.xlarge.2) |
| **Managed MongoDB** | $60 (2GB) | $800 (DocumentDB) | $125 (DDS) |
| **Kafka** | $20 (Upstash) | $700 (MSK) | $250 (DMS) |
| **ClickHouse** | $96 (self-hosted) | $500 (EC2) | $500 (GaussDB) |
| **Block Storage** | $20 (200GB) | $40 (EBS) | $42 (EVS) |
| **Bandwidth** | Free (1TB) | Variable | $70 (100Mbps) |
| **Total** | **~$580/month** | **~$3,783/month** | **~$1,527/month** |

**DigitalOcean saves you ~$3,200/month vs AWS EKS!** (85% cost reduction)

---

## Step 1: Create DOKS Cluster

### 1.1 Using DigitalOcean Console (Recommended)

1. Navigate to **Kubernetes** → **Create Cluster**
2. Configure:
   - **Datacenter Region**: Choose closest to your users (e.g., `nyc3`, `sfo3`, `sgp1`)
   - **Kubernetes Version**: 1.28.x (latest stable)
   - **Node Pool**:
     - **Name**: `jitsu-apps`
     - **Machine Type**: `s-4vcpu-8gb` (4 vCPU, 8GB RAM - $48/month each)
     - **Node Count**: 3 nodes
     - **Auto-scaling**: Enabled (3-6 nodes)
   - **Additional Node Pool**:
     - **Name**: `jitsu-data`
     - **Machine Type**: `g-4vcpu-16gb` (4 vCPU, 16GB RAM - $96/month each)
     - **Node Count**: 2 nodes
     - **Labels**: `role=data`
     - **Taints**: `dedicated=data:NoSchedule`
   - **Cluster Name**: `jitsu-production`

### 1.2 Using doctl CLI

```bash
# Create cluster
doctl kubernetes cluster create jitsu-production \
  --region nyc3 \
  --version 1.28.2-do.0 \
  --node-pool "name=jitsu-apps;size=s-4vcpu-8gb;count=3;auto-scale=true;min-nodes=3;max-nodes=6" \
  --wait

# Add data processing node pool
doctl kubernetes cluster node-pool create jitsu-production \
  --name jitsu-data \
  --size g-4vcpu-16gb \
  --count 2 \
  --auto-scale \
  --min-nodes 2 \
  --max-nodes 4 \
  --label role=data \
  --taint dedicated=data:NoSchedule

# Get cluster ID
CLUSTER_ID=$(doctl kubernetes cluster list --format ID,Name --no-header | grep jitsu-production | awk '{print $1}')
echo "Cluster ID: $CLUSTER_ID"
```

### 1.3 Configure kubectl

```bash
# Download kubeconfig
doctl kubernetes cluster kubeconfig save jitsu-production

# Verify connection
kubectl cluster-info
kubectl get nodes
```

---

## Step 2: Setup Managed Databases

### 2.1 Managed PostgreSQL Database

```bash
# Create PostgreSQL database via Console or CLI
doctl databases create jitsu-postgres \
  --engine pg \
  --version 15 \
  --region nyc3 \
  --size db-s-2vcpu-4gb \
  --num-nodes 1

# Wait for database to be ready
doctl databases get jitsu-postgres

# Get connection details
DB_ID=$(doctl databases list --format ID,Name --no-header | grep jitsu-postgres | awk '{print $1}')
DB_HOST=$(doctl databases get $DB_ID --format Host --no-header)
DB_PORT=$(doctl databases get $DB_ID --format Port --no-header)
DB_USER=$(doctl databases get $DB_ID --format User --no-header)
DB_PASSWORD=$(doctl databases get $DB_ID --format Password --no-header)
DB_DATABASE=$(doctl databases get $DB_ID --format Database --no-header)

# Create database for Jitsu
doctl databases db create $DB_ID jitsu

# Connection string
POSTGRES_URL="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/jitsu?sslmode=require"
echo $POSTGRES_URL
```

**Cost**: $60/month (db-s-2vcpu-4gb) - can scale to $240/month for production

**Available sizes**:
- `db-s-1vcpu-1gb` - $15/month (dev/test)
- `db-s-2vcpu-4gb` - $60/month (small production)
- `db-s-4vcpu-8gb` - $120/month (medium production)
- `db-s-8vcpu-16gb` - $240/month (large production)

### 2.2 Managed MongoDB Database

```bash
# Create MongoDB database
doctl databases create jitsu-mongodb \
  --engine mongodb \
  --version 6 \
  --region nyc3 \
  --size db-s-2vcpu-4gb \
  --num-nodes 1

# Get connection details
MONGO_DB_ID=$(doctl databases list --format ID,Name --no-header | grep jitsu-mongodb | awk '{print $1}')
MONGO_HOST=$(doctl databases get $MONGO_DB_ID --format Host --no-header)
MONGO_PORT=$(doctl databases get $MONGO_DB_ID --format Port --no-header)
MONGO_USER=$(doctl databases get $MONGO_DB_ID --format User --no-header)
MONGO_PASSWORD=$(doctl databases get $MONGO_DB_ID --format Password --no-header)

# Connection string
MONGODB_URL="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/jitsu?tls=true&authSource=admin"
echo $MONGODB_URL
```

**Cost**: $60/month (db-s-2vcpu-4gb)

### 2.3 Kafka (Upstash Alternative)

DigitalOcean doesn't offer managed Kafka yet. Use **Upstash Kafka** (serverless, pay-per-use):

1. Sign up at https://upstash.com/
2. Create Kafka cluster:
   - **Region**: Choose closest to your DOKS region
   - **Type**: Pay as you go
3. Get connection details:
   - **Bootstrap servers**
   - **Username**
   - **Password**

**Cost**: ~$20-50/month (based on usage)

**Alternative**: Deploy Kafka on DOKS with StatefulSet (~$96/month for 3 nodes)

### 2.4 ClickHouse (Self-Hosted on DOKS)

Since DigitalOcean doesn't offer managed ClickHouse, we'll deploy it on DOKS:

```bash
# Add Altinity ClickHouse Operator repo
helm repo add clickhouse-operator https://docs.altinity.com/clickhouse-operator/
helm repo update

# Install ClickHouse Operator
helm install clickhouse-operator clickhouse-operator/altinity-clickhouse-operator \
  -n kube-system

# Create ClickHouse cluster
cat <<EOF | kubectl apply -f -
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: jitsu-clickhouse
  namespace: jitsu
spec:
  defaults:
    templates:
      serviceTemplate: service-template
      podTemplate: pod-template
      dataVolumeClaimTemplate: data-volume-template
  configuration:
    clusters:
      - name: jitsu
        layout:
          shardsCount: 1
          replicasCount: 2
  templates:
    serviceTemplates:
      - name: service-template
        spec:
          type: ClusterIP
    podTemplates:
      - name: pod-template
        spec:
          containers:
            - name: clickhouse
              image: clickhouse/clickhouse-server:23.8
              resources:
                requests:
                  memory: "4Gi"
                  cpu: "2"
                limits:
                  memory: "8Gi"
                  cpu: "4"
    volumeClaimTemplates:
      - name: data-volume-template
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 100Gi
          storageClassName: do-block-storage
EOF
```

**Cost**: ~$96/month (2x g-2vcpu-8gb nodes dedicated to ClickHouse)

---

## Step 3: Create Kubernetes Secrets

```bash
# Create namespace
kubectl create namespace jitsu

# PostgreSQL connection
kubectl create secret generic jitsu-postgres \
  -n jitsu \
  --from-literal=url="${POSTGRES_URL}"

# MongoDB connection
kubectl create secret generic jitsu-mongodb \
  -n jitsu \
  --from-literal=url="${MONGODB_URL}"

# ClickHouse connection
kubectl create secret generic jitsu-clickhouse \
  -n jitsu \
  --from-literal=host='jitsu-clickhouse.jitsu.svc.cluster.local' \
  --from-literal=username='default' \
  --from-literal=password=''

# Kafka connection (Upstash)
kubectl create secret generic jitsu-kafka \
  -n jitsu \
  --from-literal=brokers='YOUR_UPSTASH_ENDPOINT:9092'
```

---

## Step 4: Install Required Add-ons

### 4.1 Install Nginx Ingress Controller

```bash
# Install Nginx Ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/do-loadbalancer-name"=jitsu-lb \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/do-loadbalancer-protocol"=http

# Wait for Load Balancer to be provisioned
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

# Get Load Balancer IP
LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Load Balancer IP: $LB_IP"
```

**Cost**: $12/month for Load Balancer

### 4.2 Install cert-manager for SSL

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=180s

# Create Let's Encrypt ClusterIssuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### 4.3 Install Metrics Server

```bash
# Usually pre-installed on DOKS, verify:
kubectl get deployment metrics-server -n kube-system

# If not installed:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 4.4 Install Cluster Autoscaler

```bash
# DigitalOcean automatically handles autoscaling based on node pool settings
# Verify autoscaler is running
kubectl get pods -n kube-system -l app=cluster-autoscaler

# DOKS comes with autoscaler pre-configured
```

---

## Step 5: Create Jitsu Helm Values

Create `jitsu-digitalocean-values.yaml`:

```yaml
# Global Configuration
global:
  domain: jitsu.example.com

# Disable embedded databases (use DigitalOcean managed databases)
postgresql:
  enabled: false

mongodb:
  enabled: false

kafka:
  enabled: false

# Enable ClickHouse (running on DOKS)
clickhouse:
  enabled: false  # We're using custom ClickHouse installation

redis:
  enabled: true
  master:
    persistence:
      enabled: true
      storageClass: do-block-storage
      size: 10Gi
    resources:
      requests:
        memory: "256Mi"
        cpu: "250m"
      limits:
        memory: "512Mi"
        cpu: "500m"

# Console (UI) Configuration
console:
  replicaCount: 2

  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80

  config:
    # Database connections from secrets
    databaseUrlFrom:
      secretKeyRef:
        name: jitsu-postgres
        key: url

    mongodbUrlFrom:
      secretKeyRef:
        name: jitsu-mongodb
        key: url

    clickhouseHostFrom:
      secretKeyRef:
        name: jitsu-clickhouse
        key: host

    clickhouseUsernameFrom:
      secretKeyRef:
        name: jitsu-clickhouse
        key: username

    clickhousePasswordFrom:
      secretKeyRef:
        name: jitsu-clickhouse
        key: password

    kafkaBrokersFrom:
      secretKeyRef:
        name: jitsu-kafka
        key: brokers

    # Public URLs
    nextauthUrl: "https://jitsu.example.com"
    jitsuPublicUrl: "https://jitsu.example.com"
    jitsuIngestPublicUrl: "https://jitsu.example.com"

    # Admin user
    seedUserEmail: "admin@example.com"
    seedUserPassword: "CHANGE_ME_SECURE_PASSWORD"
    disableSignup: true

    # Environment
    logFormat: "json"

  # No node selector (DigitalOcean handles placement)
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/component
              operator: In
              values:
              - console
          topologyKey: kubernetes.io/hostname

# Ingest Service Configuration
ingest:
  replicaCount: 2

  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70

  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/component
              operator: In
              values:
              - ingest
          topologyKey: kubernetes.io/hostname

# Rotor (Stream Processing) Configuration
rotor:
  replicaCount: 2

  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70

  nodeSelector:
    role: data

  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "data"
    effect: "NoSchedule"

# Bulker (Data Loading) Configuration
bulker:
  replicaCount: 2

  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70

  nodeSelector:
    role: data

  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "data"
    effect: "NoSchedule"

# Syncctl (Airbyte Connectors) Configuration
syncctl:
  replicaCount: 1

  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

  nodeSelector:
    role: data

  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "data"
    effect: "NoSchedule"

# Ingress Configuration
ingress:
  enabled: true
  className: nginx

  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

  hosts:
    - host: jitsu.example.com
      paths:
        - path: /
          pathType: Prefix

  tls:
    - secretName: jitsu-tls
      hosts:
        - jitsu.example.com

# Storage Class (DigitalOcean Block Storage)
storageClass: do-block-storage

# Monitoring
serviceMonitor:
  enabled: false  # Enable if you install Prometheus
```

---

## Step 6: Deploy Jitsu

```bash
# From repository root
cd /path/to/jitsu-chart

# Update Helm dependencies
helm dependency update

# Install Jitsu
helm install jitsu . \
  -n jitsu \
  -f jitsu-digitalocean-values.yaml \
  --timeout 15m

# Watch deployment
kubectl get pods -n jitsu -w
```

---

## Step 7: Configure DNS

```bash
# Get Load Balancer IP
LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Configure DNS A record:"
echo "  Name: jitsu.example.com"
echo "  Type: A"
echo "  Value: $LB_IP"
```

### Using DigitalOcean DNS (Recommended)

```bash
# Create domain in DigitalOcean
doctl compute domain create example.com

# Add A record
doctl compute domain records create example.com \
  --record-type A \
  --record-name jitsu \
  --record-data $LB_IP \
  --record-ttl 300
```

---

## Step 8: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n jitsu

# Check ingress
kubectl get ingress -n jitsu

# Check certificate
kubectl get certificate -n jitsu

# Test HTTPS access
curl -I https://jitsu.example.com/api/health

# Access UI
echo "Access Jitsu at: https://jitsu.example.com"
echo "Login: admin@example.com / [your-password]"
```

---

## Step 9: Add Airbyte Connectors

```bash
# Connect to managed PostgreSQL
kubectl run -it --rm psql-client \
  --image=postgres:15 \
  --restart=Never \
  -n jitsu -- \
  psql "${POSTGRES_URL}" \
  -c "INSERT INTO newjitsu.\"ConnectorPackage\" (id, \"packageId\", \"packageType\", meta) \
      VALUES ('airbyte-google-analytics-data-api', \
              'airbyte/source-google-analytics-data-api', \
              'airbyte', \
              '{\"name\": \"Google Analytics (GA4)\", \"license\": \"MIT\"}');"

# See docs/adding-airbyte-connectors.md for more connectors
```

---

## Monitoring and Logging

### Install Prometheus & Grafana (Optional)

```bash
# Install kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=do-block-storage \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi

# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
# Default: admin / prom-operator
```

### DigitalOcean Monitoring (Built-in)

- Automatic metrics collection for DOKS clusters
- Access via DigitalOcean Console → Kubernetes → Your Cluster → Insights
- Free monitoring included

---

## Backup Strategy

### Database Backups

**DigitalOcean Managed Databases**:
- Automated daily backups (7-day retention included)
- Can extend to 35 days for additional cost
- Point-in-time recovery available

```bash
# Create manual backup
doctl databases backup create $DB_ID

# List backups
doctl databases backup list $DB_ID

# Restore from backup
doctl databases create-from-backup jitsu-postgres-restored \
  --backup-restore-id BACKUP_ID
```

### Application Backup with Velero

```bash
# Install Velero with DigitalOcean Spaces
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Create DigitalOcean Space first (via Console or doctl)

helm install velero vmware-tanzu/velero \
  -n velero \
  --create-namespace \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=jitsu-backups \
  --set configuration.backupStorageLocation.config.region=nyc3 \
  --set configuration.backupStorageLocation.config.s3Url=https://nyc3.digitaloceanspaces.com \
  --set credentials.secretContents.cloud="[default]\naws_access_key_id=YOUR_SPACES_KEY\naws_secret_access_key=YOUR_SPACES_SECRET"

# Create backup schedule
velero schedule create daily-backup --schedule="@daily" --ttl 168h
```

**Cost**: DigitalOcean Spaces: $5/month for 250GB

---

## Cost Breakdown (Monthly)

### Compute Resources

| Resource | Type | Quantity | Unit Cost | Total |
|----------|------|----------|-----------|-------|
| DOKS Control Plane | Managed | 1 | $0 | $0 |
| App Nodes | s-4vcpu-8gb | 3 | $48 | $144 |
| Data Nodes | g-4vcpu-16gb | 2 | $96 | $192 |
| Load Balancer | Small | 1 | $12 | $12 |
| **Compute Total** | | | | **$348** |

### Managed Databases

| Resource | Type | Quantity | Unit Cost | Total |
|----------|------|----------|-----------|-------|
| PostgreSQL | db-s-2vcpu-4gb | 1 | $60 | $60 |
| MongoDB | db-s-2vcpu-4gb | 1 | $60 | $60 |
| Kafka (Upstash) | Pay-as-you-go | - | ~$30 | $30 |
| ClickHouse (self-hosted) | Included in nodes | - | $0 | $0 |
| **Database Total** | | | | **$150** |

### Storage & Backup

| Resource | Amount | Cost |
|----------|--------|------|
| Block Storage | 200GB | $20 |
| Spaces (Backups) | 250GB | $5 |
| **Storage Total** | | **$25** |

### Total Monthly Cost: ~$523

**Compared to other platforms**:
- **vs AWS EKS**: Save ~$3,260/month (86% reduction)
- **vs Huawei Cloud CCE**: Save ~$1,004/month (66% reduction)
- **vs AWS Bare Metal**: Save ~$2,312/month (82% reduction)

---

## Scaling

### Horizontal Pod Autoscaling (HPA)

Already configured in values.yaml:
- Console: 2-6 pods
- Ingest: 2-10 pods
- Rotor: 2-6 pods
- Bulker: 2-6 pods

### Cluster Autoscaling

```bash
# Update node pool autoscaling settings
doctl kubernetes cluster node-pool update $CLUSTER_ID $NODE_POOL_ID \
  --auto-scale \
  --min-nodes 3 \
  --max-nodes 10

# Check autoscaler status
kubectl get pods -n kube-system -l app=cluster-autoscaler
```

### Database Scaling

```bash
# Resize managed database
doctl databases resize $DB_ID --size db-s-4vcpu-8gb

# Available sizes and pricing:
# db-s-1vcpu-1gb: $15/month
# db-s-2vcpu-4gb: $60/month
# db-s-4vcpu-8gb: $120/month
# db-s-8vcpu-16gb: $240/month
```

---

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod -n jitsu <pod-name>

# Check logs
kubectl logs -n jitsu <pod-name> --previous

# Check node resources
kubectl top nodes
```

### Load Balancer Not Created

```bash
# Check service
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Check events
kubectl describe svc -n ingress-nginx ingress-nginx-controller

# Verify LoadBalancer in DigitalOcean Console
doctl compute load-balancer list
```

### Database Connection Issues

```bash
# Test PostgreSQL connection
kubectl run -it --rm psql-test \
  --image=postgres:15 \
  --restart=Never \
  -n jitsu -- \
  psql "${POSTGRES_URL}"

# Test MongoDB connection
kubectl run -it --rm mongo-test \
  --image=mongo:7.0 \
  --restart=Never \
  -n jitsu -- \
  mongosh "${MONGODB_URL}"

# Check database firewall settings
doctl databases firewalls list $DB_ID
```

### SSL Certificate Issues

```bash
# Check certificate status
kubectl get certificate -n jitsu
kubectl describe certificate -n jitsu jitsu-tls

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check Let's Encrypt challenge
kubectl get challenges -n jitsu
```

---

## Security Best Practices

### 1. Database Security

```bash
# Configure database firewall (allow only DOKS cluster)
# Get DOKS cluster VPC CIDR
CLUSTER_VPC=$(doctl kubernetes cluster get $CLUSTER_ID --format VPCUUID --no-header)

# Add firewall rule
doctl databases firewalls append $DB_ID --rule "k8s:$CLUSTER_ID"

# Remove public access
doctl databases firewalls remove $DB_ID --uuid <public-rule-uuid>
```

### 2. Network Policies

```yaml
# Create network policy for jitsu namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: jitsu-network-policy
  namespace: jitsu
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  - to:
    - namespaceSelector: {}
  - to:
    - podSelector: {}
```

### 3. Secrets Management

```bash
# Use Sealed Secrets for GitOps
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Or use DigitalOcean App Platform Secrets
```

---

## Upgrading

### Upgrade Jitsu

```bash
# Update Helm values if needed
vim jitsu-digitalocean-values.yaml

# Upgrade release
helm upgrade jitsu . \
  -n jitsu \
  -f jitsu-digitalocean-values.yaml \
  --timeout 15m

# Monitor rollout
kubectl rollout status deployment -n jitsu -l app.kubernetes.io/name=jitsu
```

### Upgrade Kubernetes

```bash
# List available versions
doctl kubernetes options versions

# Upgrade cluster
doctl kubernetes cluster upgrade $CLUSTER_ID --version 1.29.0

# Monitor upgrade
doctl kubernetes cluster get $CLUSTER_ID
```

### Upgrade Managed Databases

```bash
# Check available versions
doctl databases options engines

# Upgrade PostgreSQL
doctl databases migrate $DB_ID --version 16

# Monitor migration
doctl databases get $DB_ID
```

---

## High Availability

### Multi-Region Setup (Optional)

For critical workloads, deploy across multiple DigitalOcean regions:

1. **Primary Region**: `nyc3` (New York)
2. **Secondary Region**: `sfo3` (San Francisco)
3. **Tertiary Region**: `sgp1` (Singapore)

Use DigitalOcean Spaces with CDN for static assets and cross-region replication.

### HA Considerations

- ✅ DOKS control plane is automatically HA
- ✅ Load Balancer has automatic failover
- ✅ Managed databases have automated backups
- ✅ Node pools auto-heal unhealthy nodes
- ⚠️ Consider multi-region for critical workloads

---

## Performance Optimization

### 1. Use DigitalOcean CDN

```bash
# Enable CDN for static assets via Spaces
# Access via Console: Spaces → Your Space → Settings → CDN
```

### 2. Optimize Block Storage

```bash
# Use high-performance volumes for databases
# storageClass: do-block-storage (already default, NVMe-backed)
```

### 3. Regional Placement

Choose datacenter region closest to your users:
- **US East**: `nyc1`, `nyc3`
- **US West**: `sfo2`, `sfo3`
- **Europe**: `ams3`, `lon1`, `fra1`
- **Asia**: `sgp1`, `blr1`

---

## Disaster Recovery

### Recovery Procedure

```bash
# 1. Create new DOKS cluster
doctl kubernetes cluster create jitsu-recovery \
  --region nyc3 \
  --version 1.28.2-do.0 \
  --node-pool "name=jitsu-apps;size=s-4vcpu-8gb;count=3"

# 2. Restore databases from backup
doctl databases create-from-backup jitsu-postgres-restored \
  --backup-restore-id LATEST_BACKUP_ID

# 3. Restore application from Velero
velero restore create --from-backup daily-backup-20240115

# 4. Update DNS to point to new cluster
```

---

## Cost Optimization Tips

1. **Right-size node pools**: Start small (s-2vcpu-4gb) and scale up based on actual usage
2. **Use spot instances**: Not available on DOKS yet, but use smaller instances
3. **Optimize database sizing**: Start with db-s-1vcpu-1gb for dev/test
4. **Enable autoscaling**: Let cluster scale down during low usage
5. **Use Spaces CDN**: Reduce bandwidth costs for static content
6. **Monitor with built-in tools**: Free DigitalOcean monitoring instead of third-party
7. **Single-region deployment**: Unless you need multi-region HA

---

## When to Use DigitalOcean

**✅ Use DigitalOcean When:**
- Cost is a primary concern (85% cheaper than AWS)
- You want simple, developer-friendly interface
- You need predictable pricing
- You're a startup or small-to-medium business
- You value simplicity over advanced features
- Your traffic is primarily in US/Europe/Asia major cities

**⚠️ Consider Alternatives When:**
- You need global edge locations (use AWS)
- You require advanced AWS services integration
- You need enterprise support SLAs
- Compliance requires specific certifications
- You need multi-region active-active setup

---

## Next Steps

1. **Setup Monitoring**: Install Prometheus/Grafana or use DO built-in monitoring
2. **Add Connectors**: Follow [Adding Airbyte Connectors](adding-airbyte-connectors.md)
3. **Configure Backups**: Set up Velero backup schedules
4. **Setup Alerts**: Configure alerts in DigitalOcean Console
5. **Performance Tuning**: Adjust resource limits based on actual usage

---

## Resources

- [DigitalOcean Kubernetes Documentation](https://docs.digitalocean.com/products/kubernetes/)
- [DOKS Pricing](https://www.digitalocean.com/pricing/kubernetes)
- [DigitalOcean Managed Databases](https://docs.digitalocean.com/products/databases/)
- [doctl CLI Reference](https://docs.digitalocean.com/reference/doctl/)
- [Jitsu Documentation](https://jitsu.com/docs)

---

## Support

For issues:
- **DigitalOcean**: Community forums, tickets, or live chat
- **Jitsu**: [GitHub Issues](https://github.com/jitsucom/jitsu/issues)
- **This Helm Chart**: Open an issue in the chart repository
