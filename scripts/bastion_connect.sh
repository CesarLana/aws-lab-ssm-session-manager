#!/bin/bash
# ==============================================================================
# AWS Lab: AWS Systems Manager (SSM) Session Manager
# Script: scripts/bastion_connect.sh
# Purpose: Start an interactive terminal session with an EC2 instance without SSH,
#          bastion host public IPs, or open inbound ports.
# ==============================================================================

set -euo pipefail

INSTANCE_ID=${1:-""}

# If no instance ID provided, list available managed instances
if [[ -z "$INSTANCE_ID" ]]; then
  echo "[-] No Instance ID supplied. Discovering online SSM managed instances..."
  echo "------------------------------------------------------------------"
  aws ssm describe-instance-information \
    --query "InstanceInformationList[*].[InstanceId,PingStatus,PlatformName,IPAddress]" \
    --output table

  echo "------------------------------------------------------------------"
  read -r -p "Enter Target Instance ID: " INSTANCE_ID
fi

if [[ -z "$INSTANCE_ID" ]]; then
  echo "[!] Error: Instance ID cannot be empty."
  exit 1
fi

# Verify AWS CLI Session Manager Plugin is installed
if ! command -v session-manager-plugin &>/dev/null; then
  echo "[!] Warning: 'session-manager-plugin' not found in PATH."
  echo "    Install the plugin to start interactive CLI sessions:"
  echo "    https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
  echo "    Proceeding with AWS CLI invocation..."
fi

echo "[+] Initiating secure Session Manager connection to $INSTANCE_ID..."
echo "[+] Security Profile: Inbound port 22 CLOSED | Auth via IAM | End-to-end encrypted"

aws ssm start-session --target "$INSTANCE_ID"
