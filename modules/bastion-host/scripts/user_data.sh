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

# 4. Install kubectl
# Ensure it matches EKS cluster minor version (skew policy: ±1)
echo "--- Installing kubectl ---"

KUBECTL_VERSION=$(curl -fsSL "https://dl.k8s.io/release/stable.txt")
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /tmp/kubectl
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" -o /tmp/kubectl.sha256
echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum --check
install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm -f /tmp/kubectl /tmp/kubectl.sha256

kubectl version --client

# 5. Install Helm
echo "--- Installing Helm ---"

HELM_VERSION=$(curl -s --http1.1 https://api.github.com/repos/helm/helm/releases/latest \
  | grep '"tag_name"' | cut -d'"' -f4)

echo "Helm version to install: ${HELM_VERSION}"

# Add --http1.1 to download tar.gz
curl -L --http1.1 "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
  -o /tmp/helm.tar.gz

# Verify file download success before extract
if [ ! -s /tmp/helm.tar.gz ]; then
  echo "ERROR: helm.tar.gz is empty or missing"
  exit 1
fi

tar -zxvf /tmp/helm.tar.gz -C /tmp
mv /tmp/linux-amd64/helm /usr/local/bin/helm
rm -rf /tmp/helm.tar.gz /tmp/linux-amd64

helm version

echo "=== Bootstrap finished at $(date) ==="
echo "NOTE: To configure kubectl after SSH-ing in:"
echo "  aws eks update-kubeconfig --region <region> --name <cluster-name>"

## Xem user_data đã xong chưa
## cloud-init status --wait