#!/bin/bash

set -euo pipefail   # Stop immediately if there is an error, an unset variable, or a pipe error

# Log to file for debugging
exec > /var/log/user_data_bootstrap.log 2>&1
echo "=== Bootstrap started at $(date) ==="

# 1. Update package list
apt-get update -y

# 2. Install basic dependencies
apt-get install -y \
  unzip \
  wget \
  curl \
  jq \
  gpg \
  apt-transport-https

# 3. Install AWS CLI v2
echo "--- Installing AWS CLI v2 ---"

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

aws --version
aws eks update-kubeconfig --region ${aws_region} --name ${cluster_name}

# 4. Install kubectl
# Ensure it matches EKS cluster minor version (skew policy: ±1)
echo "--- Installing kubectl ---"

KUBECTL_VERSION=$(curl -fsSL "https://dl.k8s.io/release/stable.txt")
curl -fsSL "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /tmp/kubectl
curl -fsSL "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" -o /tmp/kubectl.sha256
echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum --check
install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm -f /tmp/kubectl /tmp/kubectl.sha256

kubectl version --client

# 5. Install Helm
echo "--- Installing Helm ---"

HELM_VERSION=$(curl -fsSL --http1.1 https://api.github.com/repos/helm/helm/releases/latest \
  | jq -r '.tag_name')

echo "Installing Helm $${HELM_VERSION}..."

curl -fsSL --http1.1 \
  "https://get.helm.sh/helm-$${HELM_VERSION}-linux-amd64.tar.gz" \
  -o /tmp/helm.tar.gz

# Verify file không rỗng
if [ ! -s /tmp/helm.tar.gz ]; then
  echo "ERROR: helm.tar.gz download failed"
  exit 1
fi

tar -zxf /tmp/helm.tar.gz -C /tmp
mv /tmp/linux-amd64/helm /usr/local/bin/helm
rm -rf /tmp/helm.tar.gz /tmp/linux-amd64

helm version

# 6. Install ArgoCD CLI
echo "--- Installing ArgoCD CLI ---"

# Get latest ArgoCD version
ARGOCD_VERSION=$(curl -fsSL --http1.1 https://api.github.com/repos/argoproj/argo-cd/releases/latest \
  | jq -r '.tag_name')

echo "Installing ArgoCD CLI $${ARGOCD_VERSION}..."

# Download ArgoCD CLI
curl -fsSL \
  "https://github.com/argoproj/argo-cd/releases/download/$${ARGOCD_VERSION}/argocd-linux-amd64" \
  -o /tmp/argocd

# Verify file is not empty
if [ ! -s /tmp/argocd ]; then
  echo "ERROR: argocd binary download failed"
  exit 1
fi

# Make executable and move to /usr/local/bin
install -o root -g root -m 0755 /tmp/argocd /usr/local/bin/argocd
rm -f /tmp/argocd

# Verify installation
argocd version --client

echo "=== Bootstrap finished at $(date) ==="

## Check if user_data has completed
cloud-init status --wait