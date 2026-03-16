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
  curl

# 3. Install AWS CLI v2
echo "--- Installing AWS CLI v2 ---"

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws   # Clean up installation files

aws --version

# 4. Install kubectl
#    Stable version from official Kubernetes release endpoint
#    Ensure it matches EKS cluster minor version (skew policy: ±1)
echo "--- Installing kubectl ---"

KUBECTL_VERSION=$(curl -fsSL "https://dl.k8s.io/release/stable.txt")
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

kubectl version --client

# Finish - kubeconfig will be configured manually after SSHing in:
#   aws eks update-kubeconfig --region <region> --name <cluster-name>

# 5. Install and Register GitHub Actions Self-Hosted Runner
echo "--- Automating GitHub Actions Runner Registration ---"

# Settings (injected by Terraform template)
GITHUB_PAT="${github_pat}"
OWNER="${owner}"
REPO="${repo}"

if [ -n "$GITHUB_PAT" ]; then
  # Fetch a short-lived registration token
  echo "Fetching GitHub Runner Registration Token..."
  REG_TOKEN=$(curl -sX POST -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$OWNER/$REPO/actions/runners/registration-token" | jq -r .token)

  if [ "$REG_TOKEN" != "null" ] && [ -n "$REG_TOKEN" ]; then
    echo "Successfully retrieved registration token."
    
    # Create a user for the runner (it shouldn't run as root)
    useradd -m github-runner || true
    su - github-runner -c "
      mkdir -p actions-runner && cd actions-runner
      
      # Download the latest runner package
      echo 'Downloading runner...'
      curl -o actions-runner-linux-x64-2.322.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.322.0/actions-runner-linux-x64-2.322.0.tar.gz
      
      # Extract
      tar xzf ./actions-runner-linux-x64-2.322.0.tar.gz
      
      # Configure the runner with specific labels
      ./config.sh --url https://github.com/$OWNER/$REPO --token $REG_TOKEN --name \"bastion-runner-$(hostname)\" --labels \"self-hosted,bastion,$(hostname)\" --unattended --replace
    "

    # Install and start the runner as a service (must be done as root)
    cd /home/github-runner/actions-runner
    ./svc.sh install github-runner
    ./svc.sh start
    echo "GitHub Actions runner successfully installed and started."
  else
    echo "Failed to retrieve GitHub runner registration token. Check your PAT scopes."
  fi
else
  echo "No github_pat provided; skipping runner registration."
fi

echo "=== Bootstrap finished at $(date) ==="
