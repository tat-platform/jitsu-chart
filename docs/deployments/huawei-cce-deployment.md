# Deploying Jitsu on Huawei Cloud CCE

This guide provides a complete, production-ready deployment of Jitsu on Huawei Cloud Container Engine (CCE).

## Overview

This deployment includes:
- CCE cluster with managed node pools
- Elastic Load Balancer (ELB) for ingress
- External managed databases (RDS, DDS, Kafka, GaussDB)
- SSL/TLS certificates
- Auto-scaling and high availability
- Monitoring and logging

## Prerequisites

### Required Tools

```bash
# Huawei Cloud CLI
# Download from: https://support.huaweicloud.com/intl/en-us/clientogw-hcli/hcli_02_001.html
# Or install via:
wget https://hcli.obs.cn-north-1.myhuaweicloud.com/hcloud_installer.sh
bash hcloud_installer.sh

# Configure authentication
hcloud configure set
# Enter your Access Key ID, Secret Access Key, and Region

# kubectl
brew install kubectl

# Helm
brew install helm
```

### Huawei Cloud Resources Needed

- Huawei Cloud Account with appropriate permissions
- VPC with public and private subnets
- DNS service (for custom domain)
- Certificate Manager (for SSL/TLS)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   NAT Gateway                           │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│         Elastic Load Balancer (ELB)                     │
│           (with SSL Certificate)                        │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              CCE Cluster (Kubernetes)                   │
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
┌───▼────┐    ┌─────▼──────┐   ┌────▼──────┐
│  RDS   │    │    DDS     │   │   Kafka   │
│(Postgres)    │  (MongoDB) │   │  (DMS)    │
└────────┘    └────────────┘   └───────────┘
                     │
              ┌──────▼─────┐
              │  GaussDB   │
              │(ClickHouse)│
              └────────────┘
```

---

## Step 1: Create VPC and Subnets

### 1.1 Create VPC

```bash
# Create VPC via Huawei Cloud Console or CLI
hcloud vpc create \
  --name jitsu-vpc \
  --cidr 10.0.0.0/16 \
  --region ap-southeast-3

# Get VPC ID
VPC_ID=$(hcloud vpc list --name jitsu-vpc --query 'vpcs[0].id' --output text)
echo $VPC_ID
```

### 1.2 Create Subnets

```bash
# Create private subnet for nodes
hcloud vpc subnet create \
  --vpc-id $VPC_ID \
  --name jitsu-private-subnet \
  --cidr 10.0.1.0/24 \
  --gateway 10.0.1.1 \
  --availability-zone ap-southeast-3a

# Create private subnet for databases
hcloud vpc subnet create \
  --vpc-id $VPC_ID \
  --name jitsu-db-subnet \
  --cidr 10.0.2.0/24 \
  --gateway 10.0.2.1 \
  --availability-zone ap-southeast-3a

# Get subnet IDs
SUBNET_ID=$(hcloud vpc subnet list --vpc-id $VPC_ID --name jitsu-private-subnet --query 'subnets[0].id' --output text)
```

---

## Step 2: Create CCE Cluster

### Option A: Using Huawei Cloud Console (Recommended)

1. Navigate to **CCE Console** → **Clusters** → **Create Cluster**
2. Configure cluster:
   - **Cluster Name**: `jitsu-production`
   - **Cluster Type**: CCE Standard
   - **Kubernetes Version**: 1.28
   - **VPC**: Select `jitsu-vpc`
   - **Subnet**: Select `jitsu-private-subnet`
   - **Network Model**: VPC network
   - **Container CIDR**: 172.16.0.0/16
   - **Service CIDR**: 10.247.0.0/16
   - **High Availability**: Yes (Multi-AZ)

### Option B: Using Huawei Cloud CLI

```bash
# Create CCE cluster
hcloud cce cluster create \
  --name jitsu-production \
  --version v1.28 \
  --flavor cce.s1.large \
  --vpc-id $VPC_ID \
  --subnet-id $SUBNET_ID \
  --container-network-mode vpc-router \
  --container-cidr 172.16.0.0/16 \
  --service-cidr 10.247.0.0/16 \
  --cluster-type VirtualMachine \
  --region ap-southeast-3

# Wait for cluster creation (takes ~10-15 minutes)
CLUSTER_ID=$(hcloud cce cluster list --name jitsu-production --query 'clusters[0].metadata.uid' --output text)
echo "Cluster ID: $CLUSTER_ID"
```

### 2.1 Configure kubectl Access

```bash
# Download kubeconfig
hcloud cce cluster kubeconfig download \
  --cluster-id $CLUSTER_ID \
  --output ~/.kube/config-jitsu

# Set KUBECONFIG
export KUBECONFIG=~/.kube/config-jitsu

# Verify connection
kubectl cluster-info
kubectl get nodes
```

---

## Step 3: Create Node Pools

### 3.1 Application Node Pool

```bash
# Create node pool for application workloads
hcloud cce nodepool create \
  --cluster-id $CLUSTER_ID \
  --name jitsu-apps \
  --flavor c6.xlarge.2 \
  --os EulerOS2.9 \
  --initial-node-count 3 \
  --autoscaling-enabled true \
  --min-node-count 3 \
  --max-node-count 6 \
  --root-volume-size 100 \
  --root-volume-type SSD \
  --data-volume-size 100 \
  --data-volume-type SSD \
  --labels role=apps
```

### 3.2 Data Processing Node Pool

```bash
# Create node pool for data processing workloads
hcloud cce nodepool create \
  --cluster-id $CLUSTER_ID \
  --name jitsu-data \
  --flavor m6.xlarge.8 \
  --os EulerOS2.9 \
  --initial-node-count 2 \
  --autoscaling-enabled true \
  --min-node-count 2 \
  --max-node-count 4 \
  --root-volume-size 100 \
  --root-volume-type SSD \
  --data-volume-size 200 \
  --data-volume-type SSD \
  --labels role=data \
  --taints dedicated=data:NoSchedule
```

**Instance Types:**
- `c6.xlarge.2` - 4 vCPU, 8GB RAM (General purpose - Apps)
- `m6.xlarge.8` - 4 vCPU, 32GB RAM (Memory optimized - Data)

---

## Step 4: Install Required Add-ons

### 4.1 Install CoreDNS (Usually pre-installed)

```bash
# Verify CoreDNS is running
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

### 4.2 Install CCE Cloud Controller Manager

```bash
# Usually pre-installed with CCE, verify:
kubectl get pods -n kube-system -l app=cloud-controller-manager
```

### 4.3 Install Metrics Server

```bash
# Install via Huawei CCE Add-ons or manually:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify
kubectl get deployment metrics-server -n kube-system
```

### 4.4 Install Autoscaler

```bash
# Enable autoscaler via CCE Console
# Navigate to CCE → Clusters → Your Cluster → Add-ons → Install "autoscaler"

# Or verify if already enabled:
kubectl get pods -n kube-system -l app=cluster-autoscaler
```

---

## Step 5: Setup External Databases

For production, use Huawei Cloud managed database services.

### 5.1 RDS for PostgreSQL

```bash
# Create RDS PostgreSQL instance via Console or CLI
hcloud rds instance create \
  --name jitsu-postgres \
  --flavor rds.pg.c6.xlarge.2 \
  --engine PostgreSQL \
  --engine-version 15 \
  --volume-type ULTRAHIGH \
  --volume-size 100 \
  --vpc-id $VPC_ID \
  --subnet-id $SUBNET_ID \
  --security-group-id $SG_ID \
  --availability-zone ap-southeast-3a,ap-southeast-3b \
  --ha-mode ha \
  --password 'YOUR_SECURE_PASSWORD' \
  --port 5432 \
  --backup-keep-days 7

# Get connection endpoint
RDS_ENDPOINT=$(hcloud rds instance show --name jitsu-postgres --query 'instance.private_ips[0]' --output text)
echo "PostgreSQL endpoint: $RDS_ENDPOINT"
```

**Cost**: ~$200-400/month (depending on specs)

### 5.2 Document Database Service (DDS) for MongoDB

```bash
# Create DDS MongoDB instance
hcloud dds instance create \
  --name jitsu-mongodb \
  --mode ReplicaSet \
  --flavor dds.mongodb.c6.xlarge.2.repset \
  --engine-version 4.4 \
  --volume-type ULTRAHIGH \
  --volume-size 100 \
  --vpc-id $VPC_ID \
  --subnet-id $SUBNET_ID \
  --security-group-id $SG_ID \
  --availability-zone ap-southeast-3a \
  --password 'YOUR_SECURE_PASSWORD' \
  --backup-keep-days 7

# Get connection string
DDS_ENDPOINT=$(hcloud dds instance show --name jitsu-mongodb --query 'instance.private_ip' --output text)
echo "MongoDB endpoint: $DDS_ENDPOINT"
```

**Cost**: ~$150-300/month

### 5.3 Distributed Message Service (DMS) for Kafka

```bash
# Create Kafka instance via Console
# Navigate to: DMS → Kafka → Create Instance

# Configuration:
# - Name: jitsu-kafka
# - Version: 2.7 or 3.x
# - Flavor: kafka.2u4g.cluster (2 vCPU, 4GB RAM per broker)
# - Brokers: 3
# - Storage: 300GB per broker
# - VPC: jitsu-vpc
# - Availability Zone: Multi-AZ

# Or via CLI:
hcloud dms kafka create \
  --name jitsu-kafka \
  --engine-version 3.3.1 \
  --specification kafka.2u4g.cluster \
  --broker-num 3 \
  --storage-space 300 \
  --vpc-id $VPC_ID \
  --subnet-id $SUBNET_ID \
  --security-group-id $SG_ID \
  --availability-zones ap-southeast-3a,ap-southeast-3b,ap-southeast-3c

# Get Kafka connection addresses
KAFKA_BROKERS=$(hcloud dms kafka show --name jitsu-kafka --query 'connect_address' --output text)
echo "Kafka brokers: $KAFKA_BROKERS"
```

**Cost**: ~$300-500/month (3 brokers)

### 5.4 GaussDB for ClickHouse

```bash
# Create GaussDB instance for ClickHouse
# Navigate to: GaussDB → ClickHouse → Create Instance

# Configuration:
# - Name: jitsu-clickhouse
# - Flavor: gaussdb.clickhouse.xlarge.4 (4 vCPU, 16GB RAM)
# - Nodes: 3 (for HA)
# - Storage: 500GB SSD per node
# - VPC: jitsu-vpc

# Or use self-hosted ClickHouse on ECS instances
# Alternative: Deploy ClickHouse on CCE with StatefulSet
```

**Cost**: ~$600-900/month (managed) or ~$200-400/month (self-hosted on ECS)

---

## Step 6: Create Kubernetes Secrets

```bash
# Create namespace
kubectl create namespace jitsu

# PostgreSQL connection
kubectl create secret generic jitsu-postgres \
  -n jitsu \
  --from-literal=url="postgresql://root:YOUR_PASSWORD@${RDS_ENDPOINT}:5432/jitsu"

# MongoDB connection
kubectl create secret generic jitsu-mongodb \
  -n jitsu \
  --from-literal=url="mongodb://rwuser:YOUR_PASSWORD@${DDS_ENDPOINT}:8635/jitsu?authSource=admin"

# ClickHouse connection
kubectl create secret generic jitsu-clickhouse \
  -n jitsu \
  --from-literal=host='jitsu-clickhouse.cluster.gaussdb.myhuaweicloud.com' \
  --from-literal=username='jitsu' \
  --from-literal=password='YOUR_PASSWORD'

# Kafka connection
kubectl create secret generic jitsu-kafka \
  -n jitsu \
  --from-literal=brokers="${KAFKA_BROKERS}"
```

---

## Step 7: Create SSL Certificate

### Option A: Huawei Cloud Certificate Manager

```bash
# Upload or create certificate via Console
# Navigate to: CCM (Cloud Certificate Manager) → SSL Certificates → Create/Upload

# Note the certificate ID for later use
CERT_ID="your-certificate-id"
```

### Option B: Use Let's Encrypt with cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create ClusterIssuer for Let's Encrypt
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

---

## Step 8: Create Jitsu Helm Values

Create `jitsu-huawei-values.yaml`:

```yaml
# Global Configuration
global:
  domain: jitsu.example.com

# Disable embedded databases (use Huawei Cloud managed services)
postgresql:
  enabled: false

mongodb:
  enabled: false

clickhouse:
  enabled: false

kafka:
  enabled: false

redis:
  enabled: true
  master:
    persistence:
      enabled: true
      storageClass: csi-disk-ssd
      size: 20Gi
    resources:
      requests:
        memory: "256Mi"
        cpu: "250m"
      limits:
        memory: "512Mi"
        cpu: "500m"

# Console (UI) Configuration
console:
  replicaCount: 3

  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80

  config:
    # Database connections from secrets
    databaseUrlFrom:
      secretKeyRef:
        name: jitsu-postgres
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

  # Pod placement on apps nodes
  nodeSelector:
    role: apps

  tolerations: []

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
  replicaCount: 3

  resources:
    requests:
      memory: "1Gi"
      cpu: "1000m"
    limits:
      memory: "2Gi"
      cpu: "2000m"

  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 20
    targetCPUUtilizationPercentage: 70

  nodeSelector:
    role: apps

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
      memory: "2Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "2000m"

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
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
      memory: "2Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "2000m"

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 8
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
  replicaCount: 2

  resources:
    requests:
      memory: "2Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "2000m"

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
    # Huawei Cloud ELB annotations
    kubernetes.io/elb.class: performance
    kubernetes.io/elb.autocreate: |
      {
        "type": "public",
        "bandwidth_name": "cce-bandwidth-jitsu",
        "bandwidth_chargemode": "bandwidth",
        "bandwidth_size": 100,
        "bandwidth_sharetype": "PER",
        "eip_type": "5_bgp",
        "available_zone": ["ap-southeast-3a"],
        "elb_virsubnet_ids": ["${SUBNET_ID}"],
        "l7_flavor_name": "L7_flavor.elb.s2.medium"
      }

    # SSL/TLS
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

# Storage Classes
storageClass: csi-disk-ssd

# Monitoring
serviceMonitor:
  enabled: true
  interval: 30s
```

---

## Step 9: Install Nginx Ingress Controller

```bash
# Install Nginx Ingress via Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."kubernetes\.io/elb\.class"=performance \
  --set controller.service.annotations."kubernetes\.io/elb\.autocreate"="{\"type\":\"public\",\"bandwidth_name\":\"nginx-bandwidth\",\"bandwidth_chargemode\":\"bandwidth\",\"bandwidth_size\":100,\"bandwidth_sharetype\":\"PER\",\"eip_type\":\"5_bgp\"}"

# Wait for ELB to be provisioned
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

# Get ELB IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"
```

---

## Step 10: Deploy Jitsu

```bash
# Update Helm dependencies
helm dependency update

# Install Jitsu
helm install jitsu . \
  -n jitsu \
  -f jitsu-huawei-values.yaml \
  --timeout 15m

# Watch deployment
kubectl get pods -n jitsu -w
```

---

## Step 11: Configure DNS

```bash
# Get ELB IP address
ELB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Configure DNS A record:"
echo "  Name: jitsu.example.com"
echo "  Type: A"
echo "  Value: $ELB_IP"
```

In Huawei Cloud DNS Console:
1. Navigate to **DNS** → **Public Zones**
2. Select your domain
3. Add A record: `jitsu` → `$ELB_IP`

---

## Step 12: Add Airbyte Connectors

```bash
# Port-forward to PostgreSQL (if needed for direct access)
# Or connect via RDS endpoint directly

# Add Google Analytics connector
kubectl run -it --rm psql-client \
  --image=postgres:15 \
  --restart=Never \
  -n jitsu -- \
  psql "postgresql://root:YOUR_PASSWORD@${RDS_ENDPOINT}:5432/jitsu" \
  -c "INSERT INTO newjitsu.\"ConnectorPackage\" (id, \"packageId\", \"packageType\", meta) \
      VALUES ('airbyte-google-analytics-data-api', \
              'airbyte/source-google-analytics-data-api', \
              'airbyte', \
              '{\"name\": \"Google Analytics (GA4)\", \"license\": \"MIT\"}');"

# Add more connectors using the helper script (modify for RDS)
# See: docs/adding-airbyte-connectors.md
```

---

## Step 13: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n jitsu

# Check ingress
kubectl get ingress -n jitsu

# Check ELB was created
hcloud elb loadbalancer list | grep jitsu

# Test public access
curl -I https://jitsu.example.com/api/health

# Access UI
echo "Access Jitsu at: https://jitsu.example.com"
echo "Login: admin@example.com / [your-password]"
```

---

## Cost Estimation

### CCE Cluster Costs

| Resource | Type | Monthly Cost (CNY) | Monthly Cost (USD) |
|----------|------|-------------------|-------------------|
| CCE Control Plane | - | ¥0 (Free) | $0 |
| ECS Nodes (3x c6.xlarge.2) | Apps | ~¥900 | ~$125 |
| ECS Nodes (2x m6.xlarge.8) | Data | ~¥1,600 | ~$225 |
| ELB (Performance) | Public | ~¥150 | ~$20 |
| Bandwidth (100 Mbps) | Public | ~¥500 | ~$70 |
| **CCE Total** | | **~¥3,150** | **~$440** |

### Database Costs

| Resource | Type | Monthly Cost (CNY) | Monthly Cost (USD) |
|----------|------|-------------------|-------------------|
| RDS PostgreSQL (c6.xlarge.2) | HA | ~¥1,200 | ~$170 |
| DDS MongoDB (c6.xlarge.2) | ReplicaSet | ~¥900 | ~$125 |
| DMS Kafka (3 brokers) | Cluster | ~¥1,800 | ~$250 |
| GaussDB ClickHouse | 3 nodes | ~¥3,600 | ~$500 |
| **Database Total** | | **~¥7,500** | **~$1,045** |

### Additional Costs

- EVS Volumes (SSD): ~¥300 ($42/month)
- NAT Gateway: ~¥150 ($20/month)
- DNS Service: ~¥10 ($1.5/month)
- Monitoring (AOM): ~¥100 ($14/month)

**Total Estimated Cost: ~¥11,200/month (~$1,560/month)**

### Cost Optimization Tips

1. **Use Spot Instances** for non-critical data nodes (up to 70% savings)
2. **Enable Auto Scaling** to scale down during low usage periods
3. **Use Yearly/Monthly Billing** instead of pay-per-use (20-30% discount)
4. **Optimize Bandwidth** - Start with 50 Mbps and scale up as needed
5. **Use Cloud Backup Service (CSBS)** for cost-effective backups
6. **Monitor with AOM** and set up alerts to avoid over-provisioning

---

## Monitoring & Logging

### Application Operations Management (AOM)

```bash
# AOM is automatically integrated with CCE
# Access via: Huawei Cloud Console → AOM

# Enable log collection
# Navigate to: AOM → Log → Log Collection Rules → Create
```

### Install Prometheus Stack (Optional)

```bash
# Install kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=csi-disk-ssd \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi

# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
# Default credentials: admin / prom-operator
```

---

## Backup Strategy

### Database Backups

- **RDS PostgreSQL**: Automated backups (1-732 days retention)
- **DDS MongoDB**: Automated backups (1-732 days retention)
- **DMS Kafka**: Manual snapshots
- **GaussDB**: Automated backups with PITR

### Application Backup with Velero

```bash
# Install Velero
# Create OBS bucket first
hcloud obs create-bucket --bucket jitsu-backups --region ap-southeast-3

# Install Velero with Huawei Cloud OBS
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

helm install velero vmware-tanzu/velero \
  -n velero \
  --create-namespace \
  --set configuration.provider=huaweicloud \
  --set configuration.backupStorageLocation.bucket=jitsu-backups \
  --set configuration.backupStorageLocation.config.region=ap-southeast-3 \
  --set credentials.secretContents.cloud="[default]\naws_access_key_id=YOUR_AK\naws_secret_access_key=YOUR_SK"

# Create backup schedule
velero schedule create daily-backup --schedule="@daily" --ttl 720h0m0s
```

---

## Security Best Practices

### 1. Network Security

```bash
# Configure Security Groups
# Allow only necessary ports:
# - 443 (HTTPS) from Internet
# - 5432 (PostgreSQL) from CCE nodes only
# - 27017 (MongoDB) from CCE nodes only
# - 9092 (Kafka) from CCE nodes only

# Create security group for databases
hcloud vpc secgroup create --name jitsu-db-sg --vpc-id $VPC_ID

# Add rules
hcloud vpc secgroup-rule create \
  --secgroup-id $DB_SG_ID \
  --direction ingress \
  --protocol tcp \
  --port 5432 \
  --remote-ip-prefix 10.0.1.0/24
```

### 2. Access Control

```bash
# Enable RBAC (enabled by default in CCE)
kubectl get clusterrolebindings

# Create service accounts with minimal permissions
# Use Huawei Cloud IAM for fine-grained access control
```

### 3. Secrets Management

```bash
# Option 1: Use Kubernetes Secrets (Basic)
# Already configured in Step 6

# Option 2: Use Huawei Cloud Data Encryption Workshop (DEW)
# Navigate to: DEW Console → Secrets Manager
```

### 4. Pod Security

```yaml
# Enable Pod Security Standards
apiVersion: v1
kind: Namespace
metadata:
  name: jitsu
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

---

## Scaling

### Horizontal Pod Autoscaling (HPA)

Already configured in values.yaml:
- Console: 3-10 pods
- Ingest: 3-20 pods
- Rotor: 2-10 pods
- Bulker: 2-8 pods

### Cluster Autoscaling

```bash
# Verify autoscaler is running
kubectl get pods -n kube-system -l app=cluster-autoscaler

# Check autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50
```

### Database Scaling

- **RDS**: Upgrade flavor or add read replicas
- **DDS**: Add more replica nodes
- **DMS Kafka**: Add more brokers (horizontal scaling)
- **GaussDB**: Scale vertically or add more shards

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
kubectl describe node <node-name>
```

### ELB Not Created

```bash
# Check service annotations
kubectl get svc -n ingress-nginx ingress-nginx-controller -o yaml

# Check CCE cloud controller logs
kubectl logs -n kube-system -l app=cloud-controller-manager

# Verify VPC and subnet configuration
hcloud vpc show --vpc-id $VPC_ID
```

### Database Connection Issues

```bash
# Test RDS connection from pod
kubectl run -it --rm debug \
  --image=postgres:15 \
  --restart=Never \
  -n jitsu -- \
  psql "postgresql://root:PASSWORD@${RDS_ENDPOINT}:5432/jitsu"

# Test DDS MongoDB connection
kubectl run -it --rm debug \
  --image=mongo:7.0 \
  --restart=Never \
  -n jitsu -- \
  mongosh "mongodb://rwuser:PASSWORD@${DDS_ENDPOINT}:8635/jitsu?authSource=admin"

# Check security group rules
hcloud vpc secgroup-rule list --secgroup-id $DB_SG_ID
```

### SSL Certificate Issues

```bash
# Check cert-manager logs (if using Let's Encrypt)
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate status
kubectl get certificate -n jitsu
kubectl describe certificate -n jitsu jitsu-tls

# Manually create certificate if needed
kubectl create secret tls jitsu-tls \
  --cert=path/to/cert.crt \
  --key=path/to/cert.key \
  -n jitsu
```

---

## Maintenance

### Upgrading Jitsu

```bash
# Update Helm values if needed
vim jitsu-huawei-values.yaml

# Upgrade release
helm upgrade jitsu . \
  -n jitsu \
  -f jitsu-huawei-values.yaml \
  --timeout 15m

# Monitor rollout
kubectl rollout status deployment -n jitsu -l app.kubernetes.io/name=jitsu
```

### Upgrading CCE Cluster

```bash
# Upgrade Kubernetes version via Console
# Navigate to: CCE → Clusters → Your Cluster → Upgrade

# Or via CLI
hcloud cce cluster upgrade \
  --cluster-id $CLUSTER_ID \
  --version v1.29

# Upgrade node pools
hcloud cce nodepool upgrade \
  --cluster-id $CLUSTER_ID \
  --nodepool-id $NODEPOOL_ID
```

### Database Maintenance

```bash
# RDS maintenance window configuration
hcloud rds instance update \
  --instance-id $RDS_ID \
  --maintenance-window "Mon:03:00-Mon:04:00"

# DDS maintenance window
hcloud dds instance update \
  --instance-id $DDS_ID \
  --maintenance-window "Mon:03:00-Mon:04:00"
```

---

## Performance Tuning

### 1. Optimize Resource Limits

```bash
# Monitor actual resource usage
kubectl top pods -n jitsu

# Adjust resource requests/limits in values.yaml based on real usage
```

### 2. Use SSD Storage

```yaml
# Already configured in values.yaml
storageClass: csi-disk-ssd  # Ultra-high I/O
```

### 3. Enable Connection Pooling

Configure PgBouncer for PostgreSQL:

```yaml
# Add to values.yaml
postgresql:
  pgbouncer:
    enabled: true
    poolMode: transaction
    maxClientConn: 1000
```

---

## High Availability

### Multi-AZ Deployment

```yaml
# Ensure pods are distributed across availability zones
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
        topologyKey: topology.kubernetes.io/zone
```

### Database HA

- **RDS**: Multi-AZ deployment (automatic failover)
- **DDS**: ReplicaSet with multiple nodes
- **DMS Kafka**: 3 brokers across AZs
- **GaussDB**: Multi-node cluster with automatic failover

---

## Disaster Recovery

### Backup Strategy

1. **Application State**: Velero daily backups to OBS
2. **Database Backups**:
   - RDS automated backups (7-day retention)
   - DDS automated backups (7-day retention)
   - Manual snapshots for long-term retention

### Recovery Procedures

```bash
# Restore from Velero backup
velero restore create --from-backup daily-backup-20240115

# Restore RDS from snapshot
hcloud rds backup restore \
  --instance-id $NEW_RDS_ID \
  --backup-id $BACKUP_ID

# Restore DDS from snapshot
hcloud dds backup restore \
  --instance-id $NEW_DDS_ID \
  --backup-id $BACKUP_ID
```

---

## Next Steps

1. **Configure Monitoring**: Set up AOM dashboards and alarms
2. **Add Connectors**: Use the [Adding Airbyte Connectors guide](adding-airbyte-connectors.md)
3. **Configure Backups**: Set up Velero backup schedules
4. **Security Hardening**: Implement Pod Security Standards and Network Policies
5. **Performance Tuning**: Adjust resource limits based on actual usage
6. **Setup CI/CD**: Integrate with Huawei Cloud CodeArts for automated deployments

---

## Resources

- [Huawei Cloud CCE Documentation](https://support.huaweicloud.com/intl/en-us/cce/index.html)
- [Huawei Cloud RDS Documentation](https://support.huaweicloud.com/intl/en-us/rds/index.html)
- [Huawei Cloud DDS Documentation](https://support.huaweicloud.com/intl/en-us/dds/index.html)
- [Huawei Cloud DMS Kafka Documentation](https://support.huaweicloud.com/intl/en-us/kafka/index.html)
- [Jitsu Documentation](https://jitsu.com/docs)
- [Kubernetes on Huawei Cloud Best Practices](https://support.huaweicloud.com/intl/en-us/bestpractice-cce/index.html)

---

## Support

For issues specific to:
- **CCE/Huawei Cloud**: Contact Huawei Cloud Support
- **Jitsu**: See [Jitsu GitHub Issues](https://github.com/jitsucom/jitsu/issues)
- **This Helm Chart**: Open an issue in the chart repository
