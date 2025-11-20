# Deploying Jitsu on AWS Bare Metal (EC2 with Kubernetes)

This guide provides a complete, production-ready deployment of Jitsu on AWS EC2 instances using self-managed Kubernetes (kubeadm), eliminating the $73/month EKS control plane cost.

## Overview

This deployment includes:
- Self-managed Kubernetes cluster on EC2 instances (using kubeadm)
- Application Load Balancer (ALB) for ingress
- External managed databases (RDS, DocumentDB, MSK)
- SSL/TLS certificates via ACM or Let's Encrypt
- Auto-scaling with EC2 Auto Scaling Groups
- High availability across multiple AZs
- **Cost savings: ~$1,000-1,500/month less than EKS**

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
│         Kubernetes Cluster (EC2 Instances)              │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Control Plane Nodes (3x t3.medium)              │  │
│  │  - kube-apiserver, etcd, scheduler, controller  │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Worker Nodes (Auto Scaling Group)               │  │
│  │  - Jitsu Services (Console, Ingest, etc.)       │  │
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

## Prerequisites

### Required Tools

```bash
# AWS CLI
brew install awscli
aws configure

# Terraform (optional, for infrastructure as code)
brew install terraform

# kubectl
brew install kubectl

# Helm
brew install helm
```

### AWS Resources Needed

- AWS Account with EC2, VPC, RDS permissions
- VPC with public and private subnets
- Route53 hosted zone (optional, for DNS)
- ACM certificate (optional, for SSL/TLS)

---

## Cost Comparison

### Bare Metal EC2 vs EKS

| Component | EKS | Bare Metal EC2 | Savings |
|-----------|-----|----------------|---------|
| **Control Plane** | $73/month | $0 (self-managed) | **$73** |
| **Master Nodes** | N/A | 3x t3.medium (~$75) | -$75 |
| **Worker Nodes** | 3x t3.xlarge (~$450) | 3x t3.xlarge (~$450) | $0 |
| **Data Nodes** | 2x r6i.xlarge (~$600) | 2x r6i.xlarge (~$600) | $0 |
| **ELB** | $20 | $20 | $0 |
| **NAT Gateway** | $90 | $90 | $0 |
| **Total Infrastructure** | **$1,233** | **$1,235** | **-$2** |
| | | | |
| **Databases** | ~$2,600 | ~$2,600 | $0 |
| **Grand Total** | **~$3,833** | **~$2,835** | **~$998/month** |

**Key Differences:**
- ✅ Save $73/month on EKS control plane
- ⚠️ Add $75/month for 3 control plane nodes (t3.medium)
- ⚠️ You manage Kubernetes upgrades and HA yourself
- ✅ **Net savings: ~$1,000/month** (26% cost reduction)

---

## Step 1: Setup VPC and Networking

### 1.1 Create VPC

```bash
# Create VPC
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=jitsu-vpc}]' \
  --region us-east-1

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=jitsu-vpc" --query 'Vpcs[0].VpcId' --output text)
echo $VPC_ID

# Enable DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
```

### 1.2 Create Subnets

```bash
# Public subnet AZ-a (for load balancers and NAT)
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=jitsu-public-1a}]'

# Public subnet AZ-b
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=jitsu-public-1b}]'

# Private subnet AZ-a (for Kubernetes nodes)
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.10.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=jitsu-private-1a}]'

# Private subnet AZ-b
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.11.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=jitsu-private-1b}]'

# Get subnet IDs
PUBLIC_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=jitsu-public-1a" --query 'Subnets[0].SubnetId' --output text)
PUBLIC_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=jitsu-public-1b" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=jitsu-private-1a" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=jitsu-private-1b" --query 'Subnets[0].SubnetId' --output text)
```

### 1.3 Create Internet Gateway and NAT Gateway

```bash
# Create and attach Internet Gateway
aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=jitsu-igw}]'

IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=jitsu-igw" --query 'InternetGateways[0].InternetGatewayId' --output text)

aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID

# Allocate Elastic IP for NAT Gateway
aws ec2 allocate-address \
  --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=jitsu-nat-eip}]'

NAT_EIP_ALLOCATION_ID=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=jitsu-nat-eip" --query 'Addresses[0].AllocationId' --output text)

# Create NAT Gateway
aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET_1A \
  --allocation-id $NAT_EIP_ALLOCATION_ID \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=jitsu-nat}]'

NAT_GW_ID=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=jitsu-nat" --query 'NatGateways[0].NatGatewayId' --output text)

# Wait for NAT Gateway to be available
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID
```

### 1.4 Configure Route Tables

```bash
# Create route table for public subnets
aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=jitsu-public-rt}]'

PUBLIC_RT_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=jitsu-public-rt" --query 'RouteTables[0].RouteTableId' --output text)

# Add route to Internet Gateway
aws ec2 create-route \
  --route-table-id $PUBLIC_RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

# Associate public subnets
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_1A --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_1B --route-table-id $PUBLIC_RT_ID

# Create route table for private subnets
aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=jitsu-private-rt}]'

PRIVATE_RT_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=jitsu-private-rt" --query 'RouteTables[0].RouteTableId' --output text)

# Add route to NAT Gateway
aws ec2 create-route \
  --route-table-id $PRIVATE_RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id $NAT_GW_ID

# Associate private subnets
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_1A --route-table-id $PRIVATE_RT_ID
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_1B --route-table-id $PRIVATE_RT_ID
```

---

## Step 2: Create Security Groups

```bash
# Security group for control plane nodes
aws ec2 create-security-group \
  --group-name jitsu-control-plane-sg \
  --description "Kubernetes control plane security group" \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=jitsu-control-plane-sg}]'

CONTROL_PLANE_SG_ID=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=jitsu-control-plane-sg" --query 'SecurityGroups[0].GroupId' --output text)

# Security group for worker nodes
aws ec2 create-security-group \
  --group-name jitsu-worker-sg \
  --description "Kubernetes worker nodes security group" \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=jitsu-worker-sg}]'

WORKER_SG_ID=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=jitsu-worker-sg" --query 'SecurityGroups[0].GroupId' --output text)

# Security group for ALB
aws ec2 create-security-group \
  --group-name jitsu-alb-sg \
  --description "Application Load Balancer security group" \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=jitsu-alb-sg}]'

ALB_SG_ID=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=jitsu-alb-sg" --query 'SecurityGroups[0].GroupId' --output text)

# Configure security group rules
# ALB - Allow HTTP/HTTPS from internet
aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0

# Control Plane - API Server
aws ec2 authorize-security-group-ingress --group-id $CONTROL_PLANE_SG_ID --protocol tcp --port 6443 --source-group $WORKER_SG_ID
aws ec2 authorize-security-group-ingress --group-id $CONTROL_PLANE_SG_ID --protocol tcp --port 6443 --source-group $CONTROL_PLANE_SG_ID

# Control Plane - etcd
aws ec2 authorize-security-group-ingress --group-id $CONTROL_PLANE_SG_ID --protocol tcp --port 2379-2380 --source-group $CONTROL_PLANE_SG_ID

# Control Plane - kubelet API
aws ec2 authorize-security-group-ingress --group-id $CONTROL_PLANE_SG_ID --protocol tcp --port 10250-10252 --source-group $CONTROL_PLANE_SG_ID

# Control Plane - Allow all from workers
aws ec2 authorize-security-group-ingress --group-id $CONTROL_PLANE_SG_ID --protocol -1 --source-group $WORKER_SG_ID

# Worker Nodes - Allow all from control plane
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG_ID --protocol -1 --source-group $CONTROL_PLANE_SG_ID

# Worker Nodes - Allow all from other workers
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG_ID --protocol -1 --source-group $WORKER_SG_ID

# Worker Nodes - Allow from ALB
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG_ID --protocol tcp --port 30000-32767 --source-group $ALB_SG_ID

# SSH access (optional, for debugging)
aws ec2 authorize-security-group-ingress --group-id $CONTROL_PLANE_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
```

---

## Step 3: Setup Kubernetes Control Plane

### 3.1 Create IAM Role for EC2 Instances

```bash
# Create IAM role for Kubernetes nodes
cat > k8s-node-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name jitsu-k8s-node-role \
  --assume-role-policy-document file://k8s-node-trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name jitsu-k8s-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy \
  --role-name jitsu-k8s-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Create instance profile
aws iam create-instance-profile --instance-profile-name jitsu-k8s-node-profile
aws iam add-role-to-instance-profile \
  --instance-profile-name jitsu-k8s-node-profile \
  --role-name jitsu-k8s-node-role
```

### 3.2 Create User Data Script for Control Plane

Create `control-plane-init.sh`:

```bash
#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install container runtime (containerd)
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

# Install containerd
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Install kubeadm, kubelet, kubectl
apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet=1.28.0-1.1 kubeadm=1.28.0-1.1 kubectl=1.28.0-1.1
apt-mark hold kubelet kubeadm kubectl

# Initialize first control plane node (only on first master)
# Get private IP
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Initialize cluster
kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --apiserver-advertise-address=$PRIVATE_IP \
  --control-plane-endpoint="LOAD_BALANCER_DNS:6443" \
  --upload-certs

# Setup kubectl for root
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown $(id -u):$(id -g) /root/.kube/config

# Install Calico CNI
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

# Save join commands
kubeadm token create --print-join-command > /tmp/worker-join-command.txt
kubeadm init phase upload-certs --upload-certs 2>&1 | grep -A 2 "upload-certs" | tail -n 1 > /tmp/certificate-key.txt
```

### 3.3 Launch Control Plane Instances

```bash
# Launch first control plane node
aws ec2 run-instances \
  --image-id ami-0c7217cdde317cfec \
  --instance-type t3.medium \
  --key-name YOUR_KEY_PAIR \
  --subnet-id $PRIVATE_SUBNET_1A \
  --security-group-ids $CONTROL_PLANE_SG_ID \
  --iam-instance-profile Name=jitsu-k8s-node-profile \
  --user-data file://control-plane-init.sh \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=50,VolumeType=gp3}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=jitsu-control-plane-1},{Key=Role,Value=control-plane}]' \
  --count 1

# Wait for initialization to complete (~5 minutes)
# SSH into the instance and verify
# ssh -i your-key.pem ubuntu@<instance-ip>
# kubectl get nodes

# Launch additional control plane nodes (for HA)
# Modify user-data to use join command instead of init
# aws ec2 run-instances ... (repeat for control-plane-2 and control-plane-3)
```

---

## Step 4: Setup Worker Nodes with Auto Scaling

### 4.1 Create Launch Template for Worker Nodes

Create `worker-node-init.sh`:

```bash
#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install container runtime (containerd)
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

# Install containerd
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Install kubeadm, kubelet, kubectl
apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet=1.28.0-1.1 kubeadm=1.28.0-1.1 kubectl=1.28.0-1.1
apt-mark hold kubelet kubeadm kubectl

# Join cluster (get join command from control plane)
# This should be fetched from S3 or Parameter Store
aws s3 cp s3://YOUR_BUCKET/worker-join-command.txt /tmp/join-command.txt
bash /tmp/join-command.txt
```

Create launch template:

```bash
# Encode user-data as base64
WORKER_USER_DATA=$(base64 -i worker-node-init.sh)

aws ec2 create-launch-template \
  --launch-template-name jitsu-worker-template \
  --version-description "Jitsu worker nodes v1" \
  --launch-template-data "{
    \"ImageId\": \"ami-0c7217cdde317cfec\",
    \"InstanceType\": \"t3.xlarge\",
    \"KeyName\": \"YOUR_KEY_PAIR\",
    \"IamInstanceProfile\": {
      \"Name\": \"jitsu-k8s-node-profile\"
    },
    \"SecurityGroupIds\": [\"$WORKER_SG_ID\"],
    \"UserData\": \"$WORKER_USER_DATA\",
    \"BlockDeviceMappings\": [{
      \"DeviceName\": \"/dev/sda1\",
      \"Ebs\": {
        \"VolumeSize\": 100,
        \"VolumeType\": \"gp3\",
        \"DeleteOnTermination\": true
      }
    }],
    \"TagSpecifications\": [{
      \"ResourceType\": \"instance\",
      \"Tags\": [
        {\"Key\": \"Name\", \"Value\": \"jitsu-worker\"},
        {\"Key\": \"Role\", \"Value\": \"worker\"},
        {\"Key\": \"k8s.io/cluster-autoscaler/enabled\", \"Value\": \"true\"},
        {\"Key\": \"k8s.io/cluster-autoscaler/jitsu\", \"Value\": \"owned\"}
      ]
    }]
  }"
```

### 4.2 Create Auto Scaling Group

```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name jitsu-worker-asg \
  --launch-template LaunchTemplateName=jitsu-worker-template \
  --min-size 3 \
  --max-size 10 \
  --desired-capacity 3 \
  --vpc-zone-identifier "$PRIVATE_SUBNET_1A,$PRIVATE_SUBNET_1B" \
  --health-check-type EC2 \
  --health-check-grace-period 300 \
  --tags "Key=Name,Value=jitsu-worker,PropagateAtLaunch=true" \
         "Key=kubernetes.io/cluster/jitsu,Value=owned,PropagateAtLaunch=true"
```

---

## Step 5: Setup External Databases

Use the same RDS, DocumentDB, MSK, and ClickHouse setup as described in the [AWS EKS deployment guide](aws-eks-deployment.md#step-3-setup-external-databases).

```bash
# Create RDS PostgreSQL (same as EKS guide)
aws rds create-db-instance \
  --db-instance-identifier jitsu-postgres \
  --db-instance-class db.r6g.xlarge \
  --engine postgres \
  --engine-version 15.4 \
  --master-username jitsuadmin \
  --master-user-password 'YOUR_SECURE_PASSWORD' \
  --allocated-storage 100 \
  --vpc-security-group-ids $DB_SG_ID \
  --db-subnet-group-name jitsu-db-subnet \
  --multi-az \
  --backup-retention-period 7

# Similar commands for DocumentDB, MSK, ClickHouse...
```

---

## Step 6: Install Kubernetes Add-ons

### 6.1 Install Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 6.2 Install Cluster Autoscaler

```bash
# Create IAM policy for Cluster Autoscaler
cat > cluster-autoscaler-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeImages",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        "eks:DescribeNodegroup"
      ],
      "Resource": ["*"]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name jitsu-cluster-autoscaler-policy \
  --policy-document file://cluster-autoscaler-policy.json

aws iam attach-role-policy \
  --role-name jitsu-k8s-node-role \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/jitsu-cluster-autoscaler-policy

# Install Cluster Autoscaler
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

# Configure for your ASG
kubectl -n kube-system edit deployment cluster-autoscaler
# Add: --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/jitsu
```

### 6.3 Install Nginx Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443
```

### 6.4 Create Application Load Balancer

```bash
# Create target group for NodePort 30080 (HTTP)
aws elbv2 create-target-group \
  --name jitsu-http-tg \
  --protocol HTTP \
  --port 30080 \
  --vpc-id $VPC_ID \
  --health-check-protocol HTTP \
  --health-check-path /healthz

HTTP_TG_ARN=$(aws elbv2 describe-target-groups --names jitsu-http-tg --query 'TargetGroups[0].TargetGroupArn' --output text)

# Create target group for NodePort 30443 (HTTPS)
aws elbv2 create-target-group \
  --name jitsu-https-tg \
  --protocol HTTPS \
  --port 30443 \
  --vpc-id $VPC_ID \
  --health-check-protocol HTTPS \
  --health-check-path /healthz

HTTPS_TG_ARN=$(aws elbv2 describe-target-groups --names jitsu-https-tg --query 'TargetGroups[0].TargetGroupArn' --output text)

# Register worker instances to target groups
WORKER_INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=worker" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text)

for instance in $WORKER_INSTANCE_IDS; do
  aws elbv2 register-targets --target-group-arn $HTTP_TG_ARN --targets Id=$instance
  aws elbv2 register-targets --target-group-arn $HTTPS_TG_ARN --targets Id=$instance
done

# Create ALB
aws elbv2 create-load-balancer \
  --name jitsu-alb \
  --subnets $PUBLIC_SUBNET_1A $PUBLIC_SUBNET_1B \
  --security-groups $ALB_SG_ID \
  --scheme internet-facing \
  --type application

ALB_ARN=$(aws elbv2 describe-load-balancers --names jitsu-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)
ALB_DNS=$(aws elbv2 describe-load-balancers --names jitsu-alb --query 'LoadBalancers[0].DNSName' --output text)

# Create HTTPS listener (requires ACM certificate)
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=arn:aws:acm:REGION:ACCOUNT:certificate/CERT_ID \
  --default-actions Type=forward,TargetGroupArn=$HTTPS_TG_ARN

# Create HTTP listener (redirect to HTTPS)
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=redirect,RedirectConfig="{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}"

echo "ALB DNS: $ALB_DNS"
```

---

## Step 7: Deploy Jitsu

### 7.1 Create Kubernetes Secrets

```bash
kubectl create namespace jitsu

# Database secrets (same as EKS guide)
kubectl create secret generic jitsu-postgres \
  -n jitsu \
  --from-literal=url='postgresql://jitsuadmin:PASSWORD@jitsu-postgres.xxxxx.rds.amazonaws.com:5432/jitsu'

kubectl create secret generic jitsu-mongodb \
  -n jitsu \
  --from-literal=url='mongodb://jitsuadmin:PASSWORD@jitsu-docdb.cluster-xxxxx.docdb.amazonaws.com:27017/jitsu?tls=true&replicaSet=rs0'

kubectl create secret generic jitsu-clickhouse \
  -n jitsu \
  --from-literal=host='clickhouse.example.com' \
  --from-literal=username='jitsu' \
  --from-literal=password='PASSWORD'

kubectl create secret generic jitsu-kafka \
  -n jitsu \
  --from-literal=brokers='b-1.jitsu-kafka.xxxxx.kafka.us-east-1.amazonaws.com:9092,...'
```

### 7.2 Create Jitsu Helm Values

Create `jitsu-baremetal-values.yaml`:

```yaml
# Same as aws-eks-deployment.md values, with these changes:

ingress:
  enabled: true
  className: nginx  # Using nginx ingress, not ALB ingress controller

  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"

  hosts:
    - host: jitsu.example.com
      paths:
        - path: /
          pathType: Prefix

  tls:
    - secretName: jitsu-tls
      hosts:
        - jitsu.example.com

# Disable embedded databases
postgresql:
  enabled: false

mongodb:
  enabled: false

clickhouse:
  enabled: false

kafka:
  enabled: false

# Use EBS gp3 storage class
storageClass: gp3

# Same resource configurations as EKS guide...
```

### 7.3 Install Jitsu

```bash
# Update Helm dependencies
helm dependency update

# Install Jitsu
helm install jitsu . \
  -n jitsu \
  -f jitsu-baremetal-values.yaml \
  --timeout 15m

# Watch deployment
kubectl get pods -n jitsu -w
```

---

## Step 8: Configure DNS

```bash
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --names jitsu-alb --query 'LoadBalancers[0].DNSName' --output text)

echo "Create CNAME record in Route53:"
echo "  Name: jitsu.example.com"
echo "  Type: CNAME"
echo "  Value: $ALB_DNS"

# Or use Route53 CLI
aws route53 change-resource-record-sets \
  --hosted-zone-id YOUR_HOSTED_ZONE_ID \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"jitsu.example.com\",
        \"Type\": \"CNAME\",
        \"TTL\": 300,
        \"ResourceRecords\": [{\"Value\": \"$ALB_DNS\"}]
      }
    }]
  }"
```

---

## Step 9: Install cert-manager for SSL

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

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

---

## Monitoring and Maintenance

### Backup etcd

```bash
# On control plane node
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Upload to S3
aws s3 cp /backup/etcd-snapshot-*.db s3://your-backup-bucket/etcd/
```

### Upgrade Kubernetes

```bash
# On control plane nodes (one at a time)
apt-get update
apt-get install -y kubeadm=1.29.0-1.1
kubeadm upgrade plan
kubeadm upgrade apply v1.29.0
apt-get install -y kubelet=1.29.0-1.1 kubectl=1.29.0-1.1
systemctl daemon-reload
systemctl restart kubelet

# On worker nodes (rolling upgrade via ASG)
# Update launch template with new version
# Terminate old instances one by one
```

---

## Cost Breakdown (Monthly)

### Compute

| Resource | Type | Quantity | Cost |
|----------|------|----------|------|
| Control Plane | t3.medium | 3 | $75 |
| Worker Nodes | t3.xlarge | 3 | $450 |
| Data Nodes | r6i.xlarge | 2 | $600 |
| NAT Gateway | - | 1 | $32 |
| ALB | - | 1 | $20 |
| EBS Storage | gp3 | 500GB | $40 |
| **Compute Total** | | | **$1,217** |

### Databases (Same as EKS)

| Resource | Type | Cost |
|----------|------|------|
| RDS PostgreSQL | db.r6g.xlarge Multi-AZ | $600 |
| DocumentDB | 2x db.r6g.large | $800 |
| MSK | 3 brokers kafka.m5.large | $700 |
| ClickHouse | c6i.4xlarge | $500 |
| **Database Total** | | **$2,600** |

### Total: ~$3,817/month

**Savings vs EKS: ~$1016/month** (21% reduction)

---

## Pros and Cons

### ✅ Pros

- **Cost savings**: ~$1,000/month less than EKS
- **Full control**: Complete control over Kubernetes configuration
- **No vendor lock-in**: Standard Kubernetes, portable to any cloud
- **Flexibility**: Customize everything (CNI, CSI, etc.)
- **Learning**: Better understanding of Kubernetes internals

### ⚠️ Cons

- **Management overhead**: You manage control plane upgrades, HA, backups
- **Complexity**: More complex setup and troubleshooting
- **No managed features**: No automatic upgrades, managed add-ons
- **Operational burden**: Need to handle etcd backups, certificate rotation
- **Support**: No AWS support for control plane issues

---

## High Availability Considerations

1. **Control Plane HA**: 3 control plane nodes across 2 AZs
2. **etcd HA**: Runs on all 3 control plane nodes
3. **Load Balancer**: ALB distributes traffic to multiple workers
4. **Worker Nodes**: Auto Scaling Group maintains desired capacity
5. **Database HA**: RDS Multi-AZ, DocumentDB cluster, MSK 3 brokers

---

## Troubleshooting

### Control Plane Issues

```bash
# Check control plane components
kubectl get pods -n kube-system

# Check etcd health
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Check API server logs
journalctl -u kubelet -f
```

### Worker Node Issues

```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>

# SSH to worker and check kubelet
ssh ubuntu@<worker-ip>
systemctl status kubelet
journalctl -u kubelet -f
```

### Networking Issues

```bash
# Check Calico pods
kubectl get pods -n kube-system -l k8s-app=calico-node

# Test pod-to-pod connectivity
kubectl run test --image=busybox -it --rm -- ping <pod-ip>
```

---

## Next Steps

1. **Setup Monitoring**: Install Prometheus/Grafana
2. **Configure Backups**: Automate etcd backups to S3
3. **Add Connectors**: Follow [Adding Airbyte Connectors](adding-airbyte-connectors.md)
4. **Setup Logging**: Install EFK stack or CloudWatch agent
5. **Disaster Recovery**: Document and test recovery procedures

---

## Resources

- [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Cluster Autoscaler on AWS](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)

---

## When to Use Bare Metal vs EKS

**Use Bare Metal When:**
- Cost is a primary concern
- You have Kubernetes expertise in-house
- You need full control over cluster configuration
- You want to avoid vendor lock-in
- You have capacity to manage infrastructure

**Use EKS When:**
- You prefer managed services
- You lack Kubernetes operational expertise
- You need AWS-managed upgrades and patches
- You value time-to-market over cost savings
- You want official AWS support
