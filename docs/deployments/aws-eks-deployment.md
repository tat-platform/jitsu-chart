# Deploying Jitsu on AWS EKS

This guide provides a complete, production-ready deployment of Jitsu on Amazon Elastic Kubernetes Service (EKS).

## Overview

This deployment includes:
- EKS cluster with managed node groups
- Application Load Balancer (ALB) for ingress
- External databases (RDS, DocumentDB, MSK, etc.)
- SSL/TLS certificates via ACM
- Auto-scaling and high availability
- Monitoring and logging

## Prerequisites

### Required Tools

```bash
# AWS CLI
brew install awscli
aws configure

# eksctl (EKS cluster management)
brew tap weaveworks/tap
brew install weaveworks/tap/eksctl

# kubectl
brew install kubectl

# Helm
brew install helm
```

### AWS Resources Needed

- AWS Account with appropriate permissions
- VPC with public and private subnets
- Route53 hosted zone (for DNS)
- ACM certificate (for SSL/TLS)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Internet Gateway                      │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              Application Load Balancer                  │
│           (with ACM SSL Certificate)                    │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                  EKS Cluster                            │
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
│  RDS   │    │ DocumentDB │   │    MSK    │
│(Postgres)    │  (MongoDB) │   │  (Kafka)  │
└────────┘    └────────────┘   └───────────┘
```

---

## Step 1: Create EKS Cluster

### Option A: Using eksctl (Recommended)

Create `eks-cluster-config.yaml`:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: jitsu-production
  region: us-east-1
  version: "1.28"

# VPC Configuration
vpc:
  cidr: 10.0.0.0/16
  nat:
    gateway: HighlyAvailable

# IAM Configuration
iam:
  withOIDC: true
  serviceAccounts:
  - metadata:
      name: aws-load-balancer-controller
      namespace: kube-system
    wellKnownPolicies:
      awsLoadBalancerController: true
  - metadata:
      name: ebs-csi-controller-sa
      namespace: kube-system
    wellKnownPolicies:
      ebsCSIController: true
  - metadata:
      name: external-dns
      namespace: kube-system
    wellKnownPolicies:
      externalDNS: true

# Managed Node Groups
managedNodeGroups:
  - name: jitsu-apps
    instanceType: t3.xlarge
    desiredCapacity: 3
    minSize: 3
    maxSize: 6
    volumeSize: 100
    volumeType: gp3
    labels:
      role: apps
    tags:
      k8s.io/cluster-autoscaler/enabled: "true"
      k8s.io/cluster-autoscaler/jitsu-production: "owned"
    iam:
      withAddonPolicies:
        imageBuilder: true
        autoScaler: true
        externalDNS: true
        certManager: true
        albIngress: true
        ebs: true
        efs: true
        cloudWatch: true

  - name: jitsu-data
    instanceType: r6i.xlarge  # Memory-optimized for data processing
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    volumeSize: 200
    volumeType: gp3
    labels:
      role: data
    taints:
      dedicated: data:NoSchedule
    tags:
      k8s.io/cluster-autoscaler/enabled: "true"
      k8s.io/cluster-autoscaler/jitsu-production: "owned"

# Add-ons
addons:
- name: vpc-cni
  version: latest
- name: coredns
  version: latest
- name: kube-proxy
  version: latest
- name: aws-ebs-csi-driver
  version: latest

cloudWatch:
  clusterLogging:
    enableTypes: ["*"]
```

Create the cluster:

```bash
eksctl create cluster -f eks-cluster-config.yaml
```

This takes about 15-20 minutes.

### Option B: Using AWS Console / Terraform

See [AWS EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/create-cluster.html)

---

## Step 2: Install Required Add-ons

### 2.1 AWS Load Balancer Controller

```bash
# Add EKS Helm chart repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=jitsu-production \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 2.2 External DNS (Optional but Recommended)

```bash
# Create external-dns values
cat > external-dns-values.yaml <<EOF
provider: aws
domainFilters:
  - example.com  # Your domain
policy: sync
txtOwnerId: jitsu-production
serviceAccount:
  create: false
  name: external-dns
EOF

# Install External DNS
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install external-dns bitnami/external-dns \
  -n kube-system \
  -f external-dns-values.yaml
```

### 2.3 Cluster Autoscaler

```bash
# Install Cluster Autoscaler
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

# Set cluster name
kubectl -n kube-system \
  set env deployment/cluster-autoscaler \
  AWS_REGION=us-east-1 \
  CLUSTER_NAME=jitsu-production
```

### 2.4 Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## Step 3: Setup External Databases

For production, use managed AWS services instead of running databases in Kubernetes.

### 3.1 Amazon RDS (PostgreSQL)

```bash
# Create RDS PostgreSQL instance via AWS Console or CLI
aws rds create-db-instance \
  --db-instance-identifier jitsu-postgres \
  --db-instance-class db.r6g.xlarge \
  --engine postgres \
  --engine-version 15.4 \
  --master-username jitsuadmin \
  --master-user-password 'YOUR_SECURE_PASSWORD' \
  --allocated-storage 100 \
  --storage-type gp3 \
  --vpc-security-group-ids sg-xxxxxxxxx \
  --db-subnet-group-name jitsu-db-subnet \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "Mon:04:00-Mon:05:00" \
  --multi-az \
  --publicly-accessible false \
  --tags Key=Environment,Value=production
```

### 3.2 Amazon DocumentDB (MongoDB)

```bash
# Create DocumentDB cluster
aws docdb create-db-cluster \
  --db-cluster-identifier jitsu-docdb \
  --engine docdb \
  --engine-version 5.0.0 \
  --master-username jitsuadmin \
  --master-user-password 'YOUR_SECURE_PASSWORD' \
  --vpc-security-group-ids sg-xxxxxxxxx \
  --db-subnet-group-name jitsu-db-subnet \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --tags Key=Environment,Value=production

# Create DocumentDB instances
aws docdb create-db-instance \
  --db-instance-identifier jitsu-docdb-instance-1 \
  --db-instance-class db.r6g.large \
  --engine docdb \
  --db-cluster-identifier jitsu-docdb

aws docdb create-db-instance \
  --db-instance-identifier jitsu-docdb-instance-2 \
  --db-instance-class db.r6g.large \
  --engine docdb \
  --db-cluster-identifier jitsu-docdb
```

### 3.3 Amazon MSK (Kafka)

```bash
# Create MSK cluster via AWS Console or CLI
aws kafka create-cluster \
  --cluster-name jitsu-kafka \
  --broker-node-group-info file://broker-info.json \
  --kafka-version 3.5.1 \
  --number-of-broker-nodes 3
```

### 3.4 Amazon ClickHouse (Self-Hosted on EC2 or use Altinity.Cloud)

Option 1: Use [Altinity.Cloud](https://altinity.com/) (Managed ClickHouse)

Option 2: Deploy ClickHouse on EC2:
- Use c6i.4xlarge or larger instances
- EBS gp3 volumes (500GB+)
- Configure in private subnet
- Use Application Load Balancer for HA

---

## Step 4: Create Kubernetes Secrets

### 4.1 Database Connection Secrets

```bash
# Create namespace
kubectl create namespace jitsu

# PostgreSQL connection
kubectl create secret generic jitsu-postgres \
  -n jitsu \
  --from-literal=url='postgresql://jitsuadmin:PASSWORD@jitsu-postgres.xxxxx.us-east-1.rds.amazonaws.com:5432/jitsu'

# MongoDB connection
kubectl create secret generic jitsu-mongodb \
  -n jitsu \
  --from-literal=url='mongodb://jitsuadmin:PASSWORD@jitsu-docdb.cluster-xxxxx.us-east-1.docdb.amazonaws.com:27017/jitsu?tls=true&replicaSet=rs0'

# ClickHouse connection
kubectl create secret generic jitsu-clickhouse \
  -n jitsu \
  --from-literal=host='clickhouse.example.com' \
  --from-literal=username='jitsu' \
  --from-literal=password='PASSWORD'

# Kafka connection
kubectl create secret generic jitsu-kafka \
  -n jitsu \
  --from-literal=brokers='b-1.jitsu-kafka.xxxxx.kafka.us-east-1.amazonaws.com:9092,b-2.jitsu-kafka.xxxxx.kafka.us-east-1.amazonaws.com:9092,b-3.jitsu-kafka.xxxxx.kafka.us-east-1.amazonaws.com:9092'
```

### 4.2 TLS Certificates

If using ACM (recommended):
- Create certificate in ACM for your domain
- Certificate ARN will be used in ingress annotation

---

## Step 5: Create Jitsu Helm Values

Create `jitsu-eks-values.yaml`:

```yaml
# Global Configuration
global:
  domain: jitsu.example.com

# Disable embedded databases (use external services)
postgresql:
  enabled: false

mongodb:
  enabled: false

clickhouse:
  enabled: false

kafka:
  enabled: false

redis:
  enabled: true  # Can use ElastiCache or embedded
  master:
    persistence:
      enabled: true
      storageClass: gp3
      size: 20Gi

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
  className: alb

  annotations:
    # AWS Load Balancer Controller annotations
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERT_ID
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-path: /api/health
    alb.ingress.kubernetes.io/success-codes: "200"
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=60

    # External DNS annotation
    external-dns.alpha.kubernetes.io/hostname: jitsu.example.com

  hosts:
    - host: jitsu.example.com
      paths:
        - path: /
          pathType: Prefix

  tls:
    - hosts:
        - jitsu.example.com

# Storage Classes
storageClass: gp3

# Monitoring
serviceMonitor:
  enabled: true
  interval: 30s
```

---

## Step 6: Deploy Jitsu

```bash
# Add Helm repository (if using published chart)
helm repo add jitsu https://charts.jitsu.com
helm repo update

# Or use local chart
cd /path/to/jitsu-chart

# Install Jitsu
helm install jitsu . \
  -n jitsu \
  -f jitsu-eks-values.yaml \
  --timeout 15m

# Watch deployment
kubectl get pods -n jitsu -w
```

---

## Step 7: Add Airbyte Connectors

```bash
# Port-forward to access console temporarily
kubectl port-forward -n jitsu svc/jitsu-console 8080:3000 &

# Add Google Analytics connector
kubectl exec -n jitsu deploy/jitsu-postgresql-0 -- bash -c \
  'export PGPASSWORD=YOUR_PASSWORD && psql -U jitsuadmin -h jitsu-postgres.xxxxx.rds.amazonaws.com -d jitsu -c \
  "INSERT INTO newjitsu.\"ConnectorPackage\" (id, \"packageId\", \"packageType\", meta) \
   VALUES ('\''airbyte-google-analytics-data-api'\'', \
           '\''airbyte/source-google-analytics-data-api'\'', \
           '\''airbyte'\'', \
           '\''{\"name\": \"Google Analytics (GA4)\", \"license\": \"MIT\"}'\''::jsonb);"'

# Or use the helper script (modify for RDS connection)
```

---

## Step 8: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n jitsu

# Check ingress
kubectl get ingress -n jitsu

# Check ALB was created
aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'jitsu')]"

# Test public access
curl -I https://jitsu.example.com/api/health
```

---

## Step 9: Configure DNS

If not using External DNS:

```bash
# Get ALB DNS name
ALB_DNS=$(kubectl get ingress -n jitsu jitsu -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Create CNAME record:"
echo "  Name: jitsu.example.com"
echo "  Type: CNAME"
echo "  Value: $ALB_DNS"
```

---

## Cost Optimization

### EKS Cluster Costs

| Resource | Type | Monthly Cost (USD) |
|----------|------|-------------------|
| EKS Control Plane | - | $73 |
| EC2 Nodes (3x t3.xlarge) | Apps | ~$450 |
| EC2 Nodes (2x r6i.xlarge) | Data | ~$600 |
| **EKS Total** | | **~$1,123** |

### Database Costs

| Resource | Type | Monthly Cost (USD) |
|----------|------|-------------------|
| RDS PostgreSQL (db.r6g.xlarge) | Multi-AZ | ~$600 |
| DocumentDB (2x db.r6g.large) | Cluster | ~$800 |
| MSK (3 brokers, kafka.m5.large) | Cluster | ~$700 |
| ClickHouse (c6i.4xlarge) | EC2 | ~$500 |
| **Database Total** | | **~$2,600** |

### Additional Costs

- ALB: ~$20/month
- EBS Volumes: ~$100/month
- Data Transfer: Variable
- CloudWatch Logs: ~$50/month

**Total Estimated Cost: ~$3,900/month**

### Cost Savings Tips

1. **Use Spot Instances** for data nodes (50-70% savings)
2. **Enable Cluster Autoscaler** to scale down during low usage
3. **Use Savings Plans** for EC2 and RDS
4. **Enable S3 Lifecycle** for log archival
5. **Use Reserved Instances** for predictable workloads

---

## Monitoring & Logging

### CloudWatch Container Insights

```bash
# Install CloudWatch agent
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml
```

### Prometheus & Grafana (Optional)

```bash
# Install kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace
```

---

## Backup Strategy

### Database Backups

- **RDS**: Automated snapshots (7-35 days retention)
- **DocumentDB**: Automated snapshots (7-35 days retention)
- **ClickHouse**: Regular snapshots to S3

### Application Backup

```bash
# Install Velero for Kubernetes backup
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set configuration.backupStorageLocation[0].bucket=jitsu-backups \
  --set configuration.provider=aws \
  --set serviceAccount.server.create=true
```

---

## Security Best Practices

1. **Network Security**
   - Use private subnets for all data services
   - Configure Security Groups with minimal required access
   - Enable VPC Flow Logs

2. **Access Control**
   - Use IAM Roles for Service Accounts (IRSA)
   - Enable Pod Security Standards
   - Implement Network Policies

3. **Secrets Management**
   - Use AWS Secrets Manager or Parameter Store
   - Rotate credentials regularly
   - Enable encryption at rest

4. **Compliance**
   - Enable audit logging
   - Use AWS Config for compliance monitoring
   - Implement regular security scans

---

## Scaling

### Horizontal Pod Autoscaling (HPA)

Already configured in values.yaml for:
- Console (3-10 pods)
- Ingest (3-20 pods)
- Rotor (2-10 pods)
- Bulker (2-8 pods)

### Cluster Autoscaling

Already configured via eksctl to scale nodes based on demand.

### Database Scaling

- **RDS**: Use read replicas for read-heavy workloads
- **DocumentDB**: Add more instances to cluster
- **ClickHouse**: Scale vertically or add shards
- **MSK**: Add more brokers

---

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod -n jitsu <pod-name>

# Check logs
kubectl logs -n jitsu <pod-name> --previous
```

### ALB Not Created

```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Verify IAM permissions
eksctl get iamserviceaccount --cluster jitsu-production
```

### Database Connection Issues

```bash
# Test connection from pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -n jitsu -- \
  psql postgresql://jitsuadmin:PASSWORD@jitsu-postgres.xxxxx.rds.amazonaws.com:5432/jitsu
```

---

## Maintenance

### Upgrading Jitsu

```bash
# Update Helm values if needed
vim jitsu-eks-values.yaml

# Upgrade release
helm upgrade jitsu . \
  -n jitsu \
  -f jitsu-eks-values.yaml \
  --timeout 15m

# Monitor rollout
kubectl rollout status deployment -n jitsu -l app.kubernetes.io/name=jitsu
```

### Upgrading EKS

```bash
# Upgrade control plane
eksctl upgrade cluster --name jitsu-production --version 1.29 --approve

# Upgrade node groups
eksctl upgrade nodegroup --cluster jitsu-production --name jitsu-apps
```

---

## Next Steps

1. **Configure Monitoring**: Set up CloudWatch dashboards and alarms
2. **Add Connectors**: Use the [Adding Airbyte Connectors guide](adding-airbyte-connectors.md)
3. **Configure Backups**: Set up Velero backup schedules
4. **Security Hardening**: Implement Pod Security Standards and Network Policies
5. **Performance Tuning**: Adjust resource limits based on actual usage

## Resources

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Jitsu Documentation](https://jitsu.com/docs)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [eksctl Documentation](https://eksctl.io/)
