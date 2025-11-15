# Jitsu Helm Chart Documentation

Complete documentation for deploying and managing Jitsu on Kubernetes.

## 📚 Documentation Structure

```
docs/
├── README.md                    # This file
├── guides/                      # Setup and configuration guides
│   ├── local-setup.md          # Local development with Kind
│   ├── production-deployment.md # Production best practices
│   └── adding-airbyte-connectors.md # Extend with 300+ connectors
└── deployments/                # Cloud platform deployments
    ├── deployment-comparison.md     # 🏆 Cost vs 🚀 Performance
    ├── digitalocean-deployment.md   # $480-1,200/mo - Best value
    ├── huawei-cce-deployment.md    # $1,400/mo - Asia/China
    ├── aws-baremetal-deployment.md # $2,700/mo - Full control
    ├── aws-eks-deployment.md       # $3,900/mo - Enterprise AWS
    └── cloudflare-hybrid-deployment.md # Add to ANY deployment
```

---

## 🚀 Quick Start

### Local Development (FREE)

```bash
# Create Kind cluster
kind create cluster --config examples/local-kind/kind-config.yaml

# Install Nginx Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s

# Install Jitsu
helm dependency update
helm install jitsu . -f examples/local-kind/values.yaml --create-namespace --namespace jitsu --timeout 10m

# Access
kubectl port-forward -n jitsu svc/jitsu-console 4000:3000 &
```

Open **http://localhost:4000** (admin@jitsu.local / admin123)

📖 **Guide**: [guides/local-setup.md](guides/local-setup.md)

---

## 🏆 Best Cost vs 🚀 Best Performance

### 💰 Best Cost: $480/month

**DigitalOcean + Cloudflare Tunnel**
- 88% cheaper than AWS EKS
- Free SSL, DDoS protection, CDN
- Handles 5K-15K requests/second
- Perfect for startups and MVPs

📖 **Guide**: [deployments/digitalocean-deployment.md](deployments/digitalocean-deployment.md)

### 🚀 Best Performance: <50ms Global Latency

**Multi-Region AWS + Cloudflare Enterprise** ($8,500/mo)
- Active-active across 3 regions
- 99.99% uptime
- 100K+ requests/second
- Perfect for global SaaS

📖 **Guide**: [deployments/aws-eks-deployment.md](deployments/aws-eks-deployment.md)

### 🎯 Best Value: $1,200/month

**DigitalOcean Premium + Cloudflare**
- 90% of enterprise performance
- Handles 100K-500K users
- Simple to manage
- **Recommended for most production workloads**

📖 **Full Comparison**: [deployments/deployment-comparison.md](deployments/deployment-comparison.md)

---

## 📖 Guides

### [Local Setup](guides/local-setup.md)
Run Jitsu locally on your Mac with Kind and OrbStack

**What's included:**
- Kind cluster configuration
- ARM64/Apple Silicon MongoDB support
- Port-forward access setup
- Troubleshooting guide

**Perfect for:** Development, testing, learning Jitsu

---

### [Production Deployment](guides/production-deployment.md)
General production configuration and best practices

**What's covered:**
- Helm installation
- High availability setup
- Resource management
- Ingress and TLS
- Scaling strategies
- Security best practices

**Perfect for:** Understanding production requirements

---

### [Adding Airbyte Connectors](guides/adding-airbyte-connectors.md)
Extend Jitsu with 300+ data source connectors

**What you'll learn:**
- Quick start (Google Analytics example)
- Helper script usage
- 30+ popular connector examples
- Manual database insertion
- Troubleshooting

**Perfect for:** Extending beyond the 4 default connectors

---

## ☁️ Cloud Deployments

### [Deployment Comparison](deployments/deployment-comparison.md)
**📊 Compare all deployment options side-by-side**

| Deployment | Cost/Mo | Latency | Throughput | Best For |
|------------|---------|---------|------------|----------|
| DigitalOcean + CF | **$480** | 200-500ms | 5K rps | Startups |
| Huawei CCE | $1,400 | 50-300ms | 10K rps | China/APAC |
| DO Premium + CF | **$1,200** | <200ms | 30K rps | **Most Prod** |
| AWS Bare + CF | $2,700 | 100-200ms | 20K rps | Full control |
| AWS EKS + CF Pro | $4,200 | <200ms | 50K rps | Enterprise |
| Multi-Region AWS | **$8,500** | **<50ms** | **100K+ rps** | Global SaaS |

**Includes:**
- Detailed cost breakdowns
- Performance benchmarks
- Configuration examples
- Migration paths
- Decision framework

---

### [DigitalOcean Deployment](deployments/digitalocean-deployment.md)
**💰 Most cost-effective: $480-1,200/month**

**Why choose DigitalOcean:**
- Free managed control plane
- Simple, predictable pricing
- Developer-friendly interface
- Built-in monitoring
- Fast setup (15 minutes)

**What you get:**
- DOKS cluster setup
- Managed databases (PostgreSQL, MongoDB)
- Load Balancer with Let's Encrypt SSL
- Auto-scaling configuration
- Complete doctl CLI automation

**Perfect for:** Startups, small-medium businesses, cost-conscious deployments

---

### [Huawei Cloud CCE Deployment](deployments/huawei-cce-deployment.md)
**🌏 Best for Asia-Pacific: $1,400/month**

**Why choose Huawei Cloud:**
- Excellent China/APAC performance
- 60% cheaper than AWS
- ICP-friendly for China
- Complete managed services

**What you get:**
- CCE cluster with managed node pools
- Managed databases (RDS, DDS, DMS Kafka, GaussDB ClickHouse)
- Elastic Load Balancer
- Complete hcloud CLI automation

**Perfect for:** China market, Asia-Pacific deployments, cost optimization

---

### [AWS Bare Metal Deployment](deployments/aws-baremetal-deployment.md)
**🔧 Full Kubernetes control: $2,700/month**

**Why choose Bare Metal:**
- Save $1,000/month vs EKS
- Full Kubernetes control
- No vendor lock-in
- Learn Kubernetes internals

**What you get:**
- Self-managed K8s with kubeadm
- 3-node HA control plane
- Auto Scaling Groups
- Managed databases (RDS, DocumentDB, MSK)
- Complete setup scripts

**Perfect for:** Teams with K8s expertise, avoiding vendor lock-in, learning

---

### [AWS EKS Deployment](deployments/aws-eks-deployment.md)
**🏢 Enterprise AWS: $3,900/month**

**Why choose EKS:**
- Fully managed control plane
- AWS ecosystem integration
- Enterprise support
- Advanced features

**What you get:**
- eksctl cluster configuration
- AWS Load Balancer Controller
- External DNS, Cluster Autoscaler
- Managed databases (RDS, DocumentDB, MSK, ClickHouse)
- Production Helm values with HA

**Perfect for:** Enterprise deployments, AWS-centric infrastructure, compliance needs

---

### [Cloudflare Hybrid Deployment](deployments/cloudflare-hybrid-deployment.md)
**🌐 Add to ANY deployment: Save 60-80% bandwidth**

**Why add Cloudflare:**
- Works with any backend
- Free SSL/TLS
- Free DDoS protection (unlimited)
- Global CDN (300+ locations)
- Free WAF and bot protection

**What's included:**
- DNS and SSL configuration
- Cloudflare Tunnel (zero-trust access)
- Page Rules for caching
- WAF setup
- Workers for edge computing
- R2 for object storage (no egress fees)

**Perfect for:** Adding enterprise features to any deployment, global distribution, cost optimization

---

## 🎯 Choose Your Deployment

### By Budget

| Budget | Recommendation | Monthly Cost |
|--------|---------------|--------------|
| <$1,000 | [DigitalOcean + CF Tunnel](deployments/digitalocean-deployment.md) | $480 |
| $1,000-$3,000 | [DigitalOcean Premium + CF](deployments/digitalocean-deployment.md) or [Huawei CCE](deployments/huawei-cce-deployment.md) | $1,200-1,400 |
| $3,000-$6,000 | [AWS EKS Single Region](deployments/aws-eks-deployment.md) | $4,200 |
| $6,000+ | [Multi-Region AWS](deployments/aws-eks-deployment.md) | $8,500 |

### By Use Case

| Use Case | Recommendation |
|----------|----------------|
| **Startup/MVP** | [DigitalOcean + CF](deployments/digitalocean-deployment.md) |
| **Small Business** | [DigitalOcean Premium](deployments/digitalocean-deployment.md) |
| **Medium Business** | [AWS EKS](deployments/aws-eks-deployment.md) or [DO Premium](deployments/digitalocean-deployment.md) |
| **Enterprise** | [AWS EKS Multi-Region](deployments/aws-eks-deployment.md) |
| **China/APAC** | [Huawei Cloud CCE](deployments/huawei-cce-deployment.md) |
| **Full K8s Control** | [AWS Bare Metal](deployments/aws-baremetal-deployment.md) |
| **Global SaaS** | [Multi-Region + CF Enterprise](deployments/aws-eks-deployment.md) |

### By Performance Needs

| Requirement | Recommendation |
|-------------|----------------|
| **<500ms latency** | Any deployment + [Cloudflare](deployments/cloudflare-hybrid-deployment.md) |
| **<200ms latency** | [DigitalOcean Premium](deployments/digitalocean-deployment.md) or [AWS Single Region](deployments/aws-eks-deployment.md) |
| **<100ms latency** | [AWS EKS](deployments/aws-eks-deployment.md) |
| **<50ms global** | [Multi-Region AWS](deployments/aws-eks-deployment.md) |
| **99.9% uptime** | Any managed K8s |
| **99.99% uptime** | [Multi-Region](deployments/aws-eks-deployment.md) |

---

## 📊 Cost Comparison Summary

| Platform | Setup Time | Monthly Cost | Annual Cost | Savings vs AWS |
|----------|-----------|--------------|-------------|----------------|
| **DigitalOcean + CF** | 1 hour | $480 | $5,760 | **$41,040** |
| **Huawei Cloud CCE** | 2 hours | $1,400 | $16,800 | $30,000 |
| **DO Premium + CF** | 2 hours | $1,200 | $14,400 | $32,400 |
| **AWS Bare Metal** | 4 hours | $2,700 | $32,400 | $14,400 |
| **AWS EKS + CF** | 3 hours | $4,200 | $50,400 | Baseline |
| **Multi-Region AWS** | 8 hours | $8,500 | $102,000 | Premium |

---

## 🛠️ Common Tasks

### Start Locally

```bash
kind create cluster --config examples/local-kind/kind-config.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s
helm dependency update
helm install jitsu . -f examples/local-kind/values.yaml --create-namespace --namespace jitsu --timeout 10m
kubectl port-forward -n jitsu svc/jitsu-console 4000:3000 &
```

📖 Full guide: [guides/local-setup.md](guides/local-setup.md)

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

📖 Full guide: [guides/adding-airbyte-connectors.md](guides/adding-airbyte-connectors.md)

### Deploy to Production

See [deployments/deployment-comparison.md](deployments/deployment-comparison.md) to choose your platform, then follow the specific guide.

---

## 🏗️ Architecture

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

---

## ✨ Key Features

- ✅ **Complete Stack** - All Jitsu services included
- ✅ **Airbyte Integration** - 300+ data source connectors
- ✅ **ARM64 Support** - Optimized for Apple Silicon
- ✅ **Production Ready** - HA, scaling, security best practices
- ✅ **Cost Optimized** - Options from $480-$8,500/month
- ✅ **Global Edge** - Cloudflare integration for any deployment
- ✅ **Easy Local Development** - Kind + OrbStack setup
- ✅ **Flexible Configuration** - Helm values + secrets

---

## 📚 Additional Resources

- **Jitsu Documentation**: https://jitsu.com/docs
- **Jitsu GitHub**: https://github.com/jitsucom/jitsu
- **Airbyte Connectors**: https://docs.airbyte.com/integrations/
- **Helm Chart Repository**: https://github.com/[your-repo]

---

## 📋 Version Information

- **Chart Version**: 0.0.0 (development)
- **Jitsu Version**: 2.11.0
- **Kubernetes**: 1.24+
- **Helm**: 3.0+

---

## 🤝 Contributing

Found an issue or have a suggestion? Please open an issue or submit a pull request!

---

## 📄 License

This Helm chart is provided under the same license as Jitsu. See LICENSE for details.
