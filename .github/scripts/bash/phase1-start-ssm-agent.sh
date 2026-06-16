#!/usr/bin/env bash
# Phase 1: Find bastion → Send SSH key via EC2 Instance Connect → Start SSM Agent → Wait for SSM Online.
# Env vars required: AWS_REGION
# Env vars set to $GITHUB_ENV: INSTANCE_ID, AZ, BASTION_IP
set -euo pipefail

# Find bastion Instance ID
echo "🔍 Looking for running bastion instance..."
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=KLTN-Bastion-Host-2" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)

if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
  echo "❌ ERROR: No running bastion instance found!"
  exit 1
fi
echo "🔵 Bastion: ${INSTANCE_ID}"

# Get AZ and Public IP
AZ=$(aws ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].Placement.AvailabilityZone" \
  --output text)

BASTION_IP=$(aws ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "🔵 AZ=${AZ}, IP=${BASTION_IP}"

# Export to GITHUB_ENV for next steps
{
  echo "INSTANCE_ID=${INSTANCE_ID}"
  echo "AZ=${AZ}"
  echo "BASTION_IP=${BASTION_IP}"
} >> "${GITHUB_ENV}"

# Write private key from GitHub Secret to temp file
echo "🔑 Writing bastion private key from secret..."
printf '%s\n' "${BASTION_PRIVATE_KEY}" > /tmp/bastion-host
chmod 400 /tmp/bastion-host

# SSH into bastion → Install and start SSM Agent
echo "🚀 Starting SSM Agent on bastion via SSH..."
ssh -i /tmp/bastion-host \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    ubuntu@"ec2-${BASTION_IP//./-}.ap-southeast-1.compute.amazonaws.com" \
    'bash -s' <<'REMOTE'
if ! sudo snap services amazon-ssm-agent | grep -q active; then
  echo "Installing SSM Agent via snap..."
  sudo snap install amazon-ssm-agent --classic
else
  echo "SSM Agent snap already installed"
fi
sudo snap start amazon-ssm-agent
sudo snap services amazon-ssm-agent
REMOTE

echo "✅ SSM Agent started"

# Wait for SSM Agent to come ONLINE (max 3 minutes)
echo "⏳ Waiting for SSM Agent to come Online..."
STATUS="Unknown"
for i in $(seq 1 18); do
  STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
    --query  "InstanceInformationList[0].PingStatus" \
    --output text 2>/dev/null || echo "None")

  if [ "${STATUS}" = "Online" ]; then
    echo "✅ SSM Agent is Online (attempt ${i})"
    break
  fi

  echo "  Attempt ${i}/18: status=${STATUS}, waiting 10s..."
  sleep 10
done

if [ "${STATUS}" != "Online" ]; then
  echo "❌ ERROR: SSM Agent did not come Online within 3 minutes"
  exit 1
fi