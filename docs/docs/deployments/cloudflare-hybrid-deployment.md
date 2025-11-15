# Cloudflare Hybrid Deployment for Jitsu

This guide shows how to deploy Jitsu using **any cloud provider** enhanced with **Cloudflare's global network** for CDN, DDoS protection, caching, and SSL/TLS at the edge.

## Overview

**Cloudflare Hybrid Approach** combines:
- **Backend**: Any cloud provider (DigitalOcean, AWS, Huawei, etc.)
- **Edge**: Cloudflare global CDN, WAF, DDoS protection, and SSL
- **Cost**: Significant savings on bandwidth, SSL certificates, and security

## Benefits

✅ **Free SSL/TLS** - No need for ACM, Let's Encrypt, or cert-manager
✅ **DDoS Protection** - Enterprise-grade protection on free tier
✅ **Global CDN** - Cache static assets at 300+ edge locations
✅ **Zero-rating bandwidth** - Cloudflare-to-origin traffic is free on many clouds
✅ **WAF** - Web Application Firewall with managed rulesets
✅ **Analytics** - Free analytics and insights
✅ **Cost savings** - Reduce origin bandwidth costs by 60-80%

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Cloudflare Edge Network               │
│              (300+ Global Data Centers)                 │
│                                                         │
│  ✓ SSL/TLS Termination    ✓ DDoS Protection           │
│  ✓ WAF & Firewall         ✓ CDN & Caching             │
│  ✓ Rate Limiting          ✓ Bot Management             │
└────────────────────┬────────────────────────────────────┘
                     │ (Encrypted tunnel or direct)
┌────────────────────▼────────────────────────────────────┐
│              Origin Cloud Provider                      │
│         (DigitalOcean / AWS / Huawei / etc.)           │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Kubernetes Cluster                              │  │
│  │  - Jitsu Services                                │  │
│  │  - Databases                                     │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Deployment Options

### Option 1: Cloudflare + DigitalOcean (Most Cost-Effective)

**Total Cost: ~$520/month** (same as standard DOKS, but with Cloudflare benefits)

- Backend: DigitalOcean DOKS
- Edge: Cloudflare Free Plan
- **Bandwidth savings**: 60-80% reduction on DO bandwidth

### Option 2: Cloudflare + Huawei Cloud (Asia-Pacific)

**Total Cost: ~$1,490/month** (save $70/month on bandwidth)

- Backend: Huawei Cloud CCE
- Edge: Cloudflare (China network available)
- **Ideal for**: China + Global traffic

### Option 3: Cloudflare + AWS (Enterprise with Global Edge)

**Total Cost: ~$3,200/month** (save ~$700/month on bandwidth + ALB)

- Backend: AWS EKS or Bare Metal
- Edge: Cloudflare Pro Plan ($20/month)
- **Remove**: AWS ALB ($20/mo) + CloudFront costs

### Option 4: Cloudflare + Cloudflare Workers (Serverless Edge)

**Total Cost: ~$450/month** (ultra-low cost)

- Backend: Minimal compute (just for databases)
- Edge: Cloudflare Workers for application logic
- **Best for**: API-heavy workloads

---

## Setup Guide: Cloudflare + DigitalOcean

This example uses DigitalOcean as the backend, but works with any provider.

### Step 1: Deploy Jitsu on Your Cloud Provider

Follow the appropriate guide:
- [DigitalOcean Deployment](digitalocean-deployment.md)
- [AWS EKS Deployment](aws-eks-deployment.md)
- [Huawei Cloud CCE Deployment](huawei-cce-deployment.md)

**Important**: Configure ingress to use **HTTP only** (no SSL) - Cloudflare handles SSL at the edge.

### Step 2: Update Helm Values for Cloudflare

Create `jitsu-cloudflare-values.yaml`:

```yaml
# ... (same as your cloud provider values)

ingress:
  enabled: true
  className: nginx

  annotations:
    # Remove cert-manager (Cloudflare handles SSL)
    # cert-manager.io/cluster-issuer: "letsencrypt-prod"  # REMOVE THIS

    # Cloudflare-specific annotations
    nginx.ingress.kubernetes.io/ssl-redirect: "false"  # Cloudflare handles redirect
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"

    # Trust Cloudflare IPs
    nginx.ingress.kubernetes.io/whitelist-source-range: "173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22,2400:cb00::/32,2606:4700::/32,2803:f800::/32,2405:b500::/32,2405:8100::/32,2a06:98c0::/29,2c0f:f248::/32"

    # Get real client IP from Cloudflare
    nginx.ingress.kubernetes.io/configuration-snippet: |
      real_ip_header CF-Connecting-IP;
      set_real_ip_from 173.245.48.0/20;
      set_real_ip_from 103.21.244.0/22;
      set_real_ip_from 103.22.200.0/22;
      set_real_ip_from 103.31.4.0/22;
      set_real_ip_from 141.101.64.0/18;
      set_real_ip_from 108.162.192.0/18;
      set_real_ip_from 190.93.240.0/20;
      set_real_ip_from 188.114.96.0/20;
      set_real_ip_from 197.234.240.0/22;
      set_real_ip_from 198.41.128.0/17;
      set_real_ip_from 162.158.0.0/15;
      set_real_ip_from 104.16.0.0/13;
      set_real_ip_from 104.24.0.0/14;
      set_real_ip_from 172.64.0.0/13;
      set_real_ip_from 131.0.72.0/22;

  hosts:
    - host: jitsu.example.com
      paths:
        - path: /
          pathType: Prefix

  # No TLS section - Cloudflare handles SSL
  # tls: []  # Remove TLS configuration
```

### Step 3: Setup Cloudflare

#### 3.1 Add Domain to Cloudflare

1. Go to https://dash.cloudflare.com/
2. Click **Add a Site**
3. Enter your domain (e.g., `example.com`)
4. Choose **Free Plan**
5. Update your domain's nameservers to Cloudflare's

#### 3.2 Create DNS Record

```bash
# Get your origin server IP
ORIGIN_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Origin IP: $ORIGIN_IP"
```

In Cloudflare Dashboard:
1. Go to **DNS** → **Records**
2. Add **A record**:
   - **Type**: A
   - **Name**: jitsu (or @ for root domain)
   - **IPv4 address**: `$ORIGIN_IP`
   - **Proxy status**: **Proxied** 🟠 (orange cloud)
   - **TTL**: Auto

#### 3.3 Configure SSL/TLS

1. Go to **SSL/TLS** → **Overview**
2. Set encryption mode: **Full (strict)** or **Full**
   - **Full (strict)**: Requires valid certificate on origin (use if you have Let's Encrypt on origin)
   - **Full**: Accepts self-signed certificate on origin (easier)

3. Go to **SSL/TLS** → **Edge Certificates**
   - **Always Use HTTPS**: ON
   - **HTTP Strict Transport Security (HSTS)**: Enable (optional)
   - **Minimum TLS Version**: TLS 1.2
   - **Automatic HTTPS Rewrites**: ON

#### 3.4 Configure Page Rules (Free: 3 rules)

Create page rules for caching:

**Rule 1: Cache Static Assets**
- **URL**: `jitsu.example.com/static/*`
- Settings:
  - Cache Level: Cache Everything
  - Edge Cache TTL: 1 month
  - Browser Cache TTL: 1 day

**Rule 2: Bypass Cache for API**
- **URL**: `jitsu.example.com/api/*`
- Settings:
  - Cache Level: Bypass

**Rule 3: Bypass Cache for Admin**
- **URL**: `jitsu.example.com/admin/*`
- Settings:
  - Cache Level: Bypass

#### 3.5 Configure Firewall Rules (Optional)

Go to **Security** → **WAF**:

1. **Enable WAF Managed Rules** (Free on Free plan)
2. **Enable Bot Fight Mode** (Free)
3. **Enable Security Level**: Medium or High

Create custom rules:
```
# Block known malicious IPs
(cf.threat_score gt 10) - Challenge

# Rate limit API endpoints
(http.request.uri.path contains "/api/") and (rate(1m) gt 100) - Block

# Allow only specific countries (optional)
(ip.geoip.country ne "US" and ip.geoip.country ne "GB") - Challenge
```

---

## Advanced: Cloudflare Tunnel (Argo Tunnel)

**Cloudflare Tunnel** creates a secure, outbound-only connection from your origin to Cloudflare, eliminating the need for public IPs or open inbound ports.

### Benefits

- ✅ No public IP needed (saves $12/month on DO Load Balancer)
- ✅ No inbound firewall rules needed
- ✅ DDoS protection without exposing origin
- ✅ Automatic failover and load balancing

### Setup Cloudflare Tunnel

#### 1. Install cloudflared in Kubernetes

```bash
# Create namespace
kubectl create namespace cloudflare

# Create Cloudflare tunnel
# First, authenticate locally
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create jitsu-tunnel

# Get tunnel credentials
TUNNEL_ID=$(cloudflared tunnel list | grep jitsu-tunnel | awk '{print $1}')
echo "Tunnel ID: $TUNNEL_ID"

# Create config
cat > /tmp/tunnel-credentials.json <<EOF
{
  "AccountTag": "YOUR_ACCOUNT_ID",
  "TunnelSecret": "YOUR_TUNNEL_SECRET",
  "TunnelID": "$TUNNEL_ID"
}
EOF

# Create Kubernetes secret
kubectl create secret generic tunnel-credentials \
  -n cloudflare \
  --from-file=credentials.json=/tmp/tunnel-credentials.json

# Create ConfigMap for tunnel config
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared-config
  namespace: cloudflare
data:
  config.yaml: |
    tunnel: $TUNNEL_ID
    credentials-file: /etc/cloudflared/credentials.json
    metrics: 0.0.0.0:2000
    no-autoupdate: true
    ingress:
      - hostname: jitsu.example.com
        service: http://jitsu-console.jitsu.svc.cluster.local:3000
      - hostname: jitsu.example.com
        path: /api/*
        service: http://jitsu-ingest.jitsu.svc.cluster.local:8001
      - service: http_status:404
EOF
```

#### 2. Deploy cloudflared

```yaml
# cloudflared-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: cloudflare
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:latest
        args:
        - tunnel
        - --config
        - /etc/cloudflared/config.yaml
        - run
        livenessProbe:
          httpGet:
            path: /ready
            port: 2000
          initialDelaySeconds: 10
          periodSeconds: 10
        volumeMounts:
        - name: config
          mountPath: /etc/cloudflared
          readOnly: true
        - name: credentials
          mountPath: /etc/cloudflared/credentials.json
          subPath: credentials.json
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: cloudflared-config
      - name: credentials
        secret:
          secretName: tunnel-credentials
```

```bash
kubectl apply -f cloudflared-deployment.yaml
```

#### 3. Route DNS through Tunnel

```bash
# Create DNS CNAME to tunnel
cloudflared tunnel route dns $TUNNEL_ID jitsu.example.com
```

**Cost Savings with Tunnel**:
- DigitalOcean Load Balancer: -$12/month (not needed)
- Public IP: Free (no IP needed)
- **Total savings**: $12/month + improved security

---

## Cloudflare Workers for Edge Computing

Use Cloudflare Workers to handle logic at the edge (300+ locations globally).

### Use Cases

- API rate limiting at the edge
- Request/response transformation
- A/B testing
- Geo-based routing
- API caching and optimization

### Example: Rate Limiting Worker

```javascript
// rate-limit-worker.js
const RATE_LIMIT = 100; // requests per minute
const WINDOW = 60; // seconds

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const ip = request.headers.get('CF-Connecting-IP')
  const key = `rate_limit:${ip}`

  // Get current count from KV
  const count = await RATE_LIMIT_KV.get(key)

  if (count && parseInt(count) > RATE_LIMIT) {
    return new Response('Rate limit exceeded', {
      status: 429,
      headers: {
        'Retry-After': '60'
      }
    })
  }

  // Increment counter
  const newCount = count ? parseInt(count) + 1 : 1
  await RATE_LIMIT_KV.put(key, newCount.toString(), { expirationTtl: WINDOW })

  // Forward to origin
  return fetch(request)
}
```

Deploy:
```bash
wrangler publish rate-limit-worker.js
```

**Cost**: $5/month for 10M requests (Cloudflare Workers Paid plan)

---

## Cloudflare R2 for Object Storage

Replace S3/Spaces with Cloudflare R2 (no egress fees!).

### Setup R2 for Backups

```bash
# Install rclone
brew install rclone

# Configure R2
rclone config
# Choose: Cloudflare R2
# Enter: Access Key ID and Secret Access Key from Cloudflare dashboard

# Backup to R2
rclone sync /local/backups r2:jitsu-backups
```

**Cost**: $0.015/GB/month (vs $0.02 for DO Spaces, $0.023 for S3)
**Egress**: FREE (vs $0.01/GB for DO, $0.09/GB for AWS)

---

## Performance Optimization

### 1. Enable Argo Smart Routing (Optional - $5/month + $0.10/GB)

Argo routes traffic through less congested paths:
- **30% faster** average time-to-first-byte
- **27% fewer connection errors**

```bash
# Enable via Cloudflare Dashboard
# Traffic → Argo → Enable
```

### 2. Configure Caching Rules

```yaml
# Cache static assets aggressively
rules:
  - expression: '(http.request.uri.path matches "^/static/.*")'
    action: cache
    cache_settings:
      edge_ttl: 2592000  # 30 days
      browser_ttl: 86400  # 1 day

  # Cache API responses with short TTL
  - expression: '(http.request.uri.path matches "^/api/public/.*")'
    action: cache
    cache_settings:
      edge_ttl: 60       # 1 minute
      browser_ttl: 30    # 30 seconds
```

### 3. Enable HTTP/3 and QUIC

Go to **Network** → **HTTP/3 (with QUIC)** → Enable

### 4. Enable 0-RTT Connection Resumption

Go to **Network** → **0-RTT Connection Resumption** → Enable

---

## Security Best Practices

### 1. Enable IP Firewall

Restrict access to origin servers:

```bash
# On your cloud provider, allow only Cloudflare IPs
# DigitalOcean Firewall example
doctl compute firewall create \
  --name cloudflare-only \
  --inbound-rules "protocol:tcp,ports:80,sources:addresses:173.245.48.0/20,103.21.244.0/22" \
  --inbound-rules "protocol:tcp,ports:443,sources:addresses:173.245.48.0/20,103.21.244.0/22"
```

### 2. Authenticated Origin Pulls

Ensure requests to origin come from Cloudflare:

1. Go to **SSL/TLS** → **Origin Server**
2. Enable **Authenticated Origin Pulls**
3. Download Cloudflare Origin CA certificate
4. Configure nginx ingress to require client certificate

```yaml
# nginx ingress config
nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
nginx.ingress.kubernetes.io/auth-tls-secret: "cloudflare/origin-ca"
```

### 3. Enable WAF Managed Rules

Go to **Security** → **WAF** → Enable all recommended rulesets:
- Cloudflare Managed Ruleset
- Cloudflare OWASP Core Ruleset
- Cloudflare Exposed Credentials Check

---

## Monitoring and Analytics

### Cloudflare Analytics (Free)

Access via Dashboard:
- **Traffic**: Requests, bandwidth, unique visitors
- **Security**: Threats blocked, challenges issued
- **Performance**: Origin response time, cache hit rate
- **Errors**: 4xx and 5xx error rates

### GraphQL Analytics API

```graphql
query {
  viewer {
    zones(filter: {zoneTag: "YOUR_ZONE_ID"}) {
      httpRequests1dGroups(
        orderBy: [date_ASC]
        limit: 30
        filter: {date_gt: "2024-01-01"}
      ) {
        sum {
          requests
          bytes
          cachedRequests
          cachedBytes
        }
        dimensions {
          date
        }
      }
    }
  }
}
```

### Integrate with External Monitoring

Export logs to external services:

```bash
# Logpush to S3/R2/GCS
curl -X POST "https://api.cloudflare.com/client/v4/zones/ZONE_ID/logpush/jobs" \
  -H "X-Auth-Email: YOUR_EMAIL" \
  -H "X-Auth-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{
    "destination_conf": "s3://YOUR_BUCKET/logs?region=us-east-1",
    "dataset": "http_requests",
    "logpull_options": "fields=ClientIP,EdgeStartTimestamp,RayID"
  }'
```

---

## Cost Optimization

### Monthly Cost Breakdown with Cloudflare

**Example: DigitalOcean + Cloudflare**

| Component | Without Cloudflare | With Cloudflare | Savings |
|-----------|-------------------|-----------------|---------|
| Compute | $348 | $348 | $0 |
| Databases | $150 | $150 | $0 |
| Load Balancer | $12 | $0 (with Tunnel) | **$12** |
| Storage | $25 | $25 | $0 |
| Bandwidth | ~$50 | ~$10 (80% reduction) | **$40** |
| SSL Certificates | $0 (Let's Encrypt) | $0 (Cloudflare) | $0 |
| DDoS Protection | N/A | Free | **+Value** |
| CDN | N/A | Free | **+Value** |
| WAF | N/A | Free | **+Value** |
| **Total** | **$585** | **$533** | **$52/mo** |

**Additional value**: Global CDN, DDoS protection, WAF - typically $200-500/month on other platforms

---

## Disaster Recovery with Cloudflare

### Load Balancing (Paid - $5/monitor)

Configure origin pools with automatic failover:

```yaml
# Primary origin
origin_pool_1:
  name: "jitsu-do-primary"
  origins:
    - address: "primary-ip-address"
      weight: 1
  health_check:
    path: "/api/health"
    interval: 60

# Backup origin (different cloud)
origin_pool_2:
  name: "jitsu-aws-backup"
  origins:
    - address: "backup-ip-address"
      weight: 0.5
  health_check:
    path: "/api/health"
    interval: 60

load_balancer:
  name: "jitsu.example.com"
  default_pools:
    - origin_pool_1
    - origin_pool_2
  fallback_pool: origin_pool_2
  steering_policy: "dynamic_latency"
```

### Geo-Steering

Route users to nearest origin:

```yaml
# US users → DigitalOcean NYC
# EU users → AWS Frankfurt
# Asia users → Huawei Cloud Singapore

load_balancer:
  geo_steering:
    - region: "WNAM"  # Western North America
      pool: "do-nyc"
    - region: "EEUR"  # Eastern Europe
      pool: "aws-frankfurt"
    - region: "SEAS"  # Southeast Asia
      pool: "huawei-singapore"
```

---

## Migration Strategy

### Step 1: Add Cloudflare (No Downtime)

1. Keep existing setup running
2. Add domain to Cloudflare
3. Update nameservers
4. Configure DNS (proxied)
5. Test via Cloudflare

### Step 2: Optimize Origin (Gradual)

1. Remove origin SSL certificate (if using Cloudflare Tunnel)
2. Remove origin load balancer (if using Cloudflare Load Balancing)
3. Restrict origin firewall to Cloudflare IPs only
4. Remove CDN (if using another CDN)

### Step 3: Monitor and Adjust

1. Monitor Cloudflare analytics
2. Adjust cache rules based on hit rate
3. Fine-tune WAF rules
4. Optimize worker scripts

---

## Troubleshooting

### Issue 1: 502 Bad Gateway

**Cause**: Origin server not reachable or returning errors

**Fix**:
```bash
# Check origin health
curl -I http://ORIGIN_IP

# Check Cloudflare logs
# Dashboard → Analytics → Logs

# Verify DNS
dig jitsu.example.com
```

### Issue 2: Infinite Redirect Loop

**Cause**: Both Cloudflare and origin trying to redirect HTTP→HTTPS

**Fix**:
```yaml
# In Helm values, disable origin SSL redirect
nginx.ingress.kubernetes.io/ssl-redirect: "false"
nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
```

Or set Cloudflare to **Flexible SSL** (not recommended for production)

### Issue 3: Real IP Not Showing

**Cause**: Nginx not configured to trust Cloudflare IPs

**Fix**: Already included in Helm values above (`real_ip_header CF-Connecting-IP`)

### Issue 4: Cloudflare Tunnel Disconnects

**Cause**: Network issues or tunnel replica failure

**Fix**:
```bash
# Scale tunnel replicas
kubectl scale deployment cloudflared -n cloudflare --replicas=3

# Check logs
kubectl logs -n cloudflare deployment/cloudflared
```

---

## Best Practices Summary

### ✅ Do

- Use **Full (strict)** SSL mode for production
- Enable **Always Use HTTPS**
- Configure **Authenticated Origin Pulls**
- Set up **Page Rules** for optimal caching
- Use **Cloudflare Tunnel** for maximum security
- Monitor **Analytics** regularly
- Enable **WAF** and **Bot Fight Mode**

### ❌ Don't

- Use **Flexible SSL** (insecure)
- Cache authenticated endpoints
- Expose origin IP publicly (if using Cloudflare)
- Bypass Cloudflare for critical traffic
- Ignore security alerts

---

## Recommended Cloudflare Plans

| Plan | Cost | Best For | Key Features |
|------|------|----------|--------------|
| **Free** | $0 | Startups, testing | Unlimited DDoS, Basic WAF, CDN, 3 Page Rules |
| **Pro** | $20/month | Small business | Advanced DDoS, 20 Page Rules, Image optimization |
| **Business** | $200/month | Enterprise | Custom WAF, 50 Page Rules, PCI compliance |
| **Workers** | $5/month | Edge compute | 10M requests, KV storage |

**Recommendation**: Start with **Free + Workers ($5)** = $5/month for most use cases

---

## Next Steps

1. **Deploy backend** using any cloud provider guide
2. **Add domain to Cloudflare** (free)
3. **Configure DNS** with proxied records
4. **Setup SSL/TLS** mode to Full or Full (strict)
5. **Configure Page Rules** for caching
6. **Enable WAF** and security features
7. **Optional**: Setup Cloudflare Tunnel for extra security
8. **Monitor** via Cloudflare Analytics

---

## Resources

- [Cloudflare Documentation](https://developers.cloudflare.com/)
- [Cloudflare Tunnel Setup](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Workers](https://workers.cloudflare.com/)
- [Cloudflare R2](https://developers.cloudflare.com/r2/)
- [Page Rules Guide](https://support.cloudflare.com/hc/en-us/articles/218411427)

---

## Support

For Cloudflare-specific issues:
- **Community**: https://community.cloudflare.com/
- **Documentation**: https://developers.cloudflare.com/
- **Support**: Available on Pro+ plans
