#!/bin/bash

set -euo pipefail   # Stop immediately if there is an error, an unset variable, or a pipe error

# Log to file for debugging
exec > /var/log/user_data_bootstrap.log 2>&1
echo "=== Bootstrap started at $$(date) ==="

# 1. Update package list
apt-get update -y

# 2. Install basic dependencies
apt-get install -y \
  unzip \
  curl \
  jq

# 3. Install AWS CLI v2
echo "--- Installing AWS CLI v2 ---"

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws   # Clean up installation files

aws --version

# 4. Install kubectl
#    Ensure it matches EKS cluster minor version (skew policy: ±1)
echo "--- Installing kubectl ---"

KUBECTL_VERSION=$$(curl -fsSL "https://dl.k8s.io/release/stable.txt")
curl -fsSL "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

kubectl version --client

# 5. Install Helm
#    Required for bootstrapping: aws-load-balancer-controller, ingress-nginx, argocd
echo "--- Installing Helm ---"

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm version

echo "=== Bootstrap finished at $(date) ==="
echo "NOTE: To configure kubectl after SSH-ing in:"
echo "  aws eks update-kubeconfig --region <region> --name <cluster-name>"
