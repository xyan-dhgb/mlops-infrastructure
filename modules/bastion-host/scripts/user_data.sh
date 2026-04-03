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

# Download key into file with loop retry using wget (using GnuTLS) to bypass OpenSSL 3.0 "unexpected eof" error of curl on Ubuntu 22.04
for i in {1..5}; do
  echo "Downloading Helm signing key (Attempt $i)..."
  if wget -qO /tmp/helm.asc https://baltocdn.com/helm/signing.asc; then
    if [ -s /tmp/helm.asc ]; then
      echo "Key downloaded successfully."
      break
    fi
  fi
  sleep 3
done

if [ ! -s /tmp/helm.asc ]; then
  echo "ERROR: Failed to download Helm signing key after 5 attempts."
  exit 1
fi

cat /tmp/helm.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
rm -f /tmp/helm.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
apt-get update -y
apt-get install -y helm

helm version

echo "=== Bootstrap finished at $(date) ==="
echo "NOTE: To configure kubectl after SSH-ing in:"
echo "  aws eks update-kubeconfig --region <region> --name <cluster-name>"

## Xem user_data đã xong chưa
## cloud-init status --wait