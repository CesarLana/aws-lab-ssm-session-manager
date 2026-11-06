#!/bin/bash
# ==============================================================================
# AWS Lab: AWS Systems Manager (SSM) Session Manager
# Script: scripts/port_forwarding_tunnel.sh
# Purpose: Open an encrypted TCP port forwarding tunnel to a private EC2 service
#          (e.g., HTTP, Database, Redis) without public IP or bastion opening.
# ==============================================================================

set -euo pipefail

INSTANCE_ID=${1:-""}
REMOTE_PORT=${2:-80}
LOCAL_PORT=${3:-8080}

if [[ -z "$INSTANCE_ID" ]]; then
  echo "Usage: $0 <INSTANCE_ID> [REMOTE_PORT] [LOCAL_PORT]"
  echo "Example: $0 i-0123456789abcdef0 80 8080"
  echo "Example (Database): $0 i-0123456789abcdef0 3306 3306"
  exit 1
fi

echo "=========================================================="
echo " AWS SSM Secure Port Forwarding Tunnel"
echo " Target Instance: $INSTANCE_ID"
echo " Remote Port:     $REMOTE_PORT"
echo " Local Listen:    127.0.0.1:$LOCAL_PORT"
echo " Inbound Ports:   0 (Zero Inbound Rules on Security Group)"
echo "=========================================================="
echo "[+] Starting tunnel session... Press Ctrl+C to disconnect."

aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "{\"portNumber\":[\"$REMOTE_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
