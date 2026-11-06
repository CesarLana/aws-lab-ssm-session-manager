#!/bin/bash
# ==============================================================================
# AWS Lab: AWS Systems Manager (SSM) Session Manager
# Script: scripts/run_command_example.sh
# Purpose: Execute remote shell scripts across EC2 instances without SSH
#          using AWS Systems Manager Run Command (AWS-RunShellScript).
# ==============================================================================

set -euo pipefail

TARGET_INSTANCE_ID=${1:-""}

if [[ -z "$TARGET_INSTANCE_ID" ]]; then
  echo "Usage: $0 <INSTANCE_ID_OR_TAG>"
  echo "Example: $0 i-0123456789abcdef0"
  echo "Example with Tag: $0 'Key=tag:Environment,Values=Production'"
  exit 1
fi

COMMANDS_TO_RUN=$(cat <<'EOF'
echo "=== System Information ==="
uname -a
echo "=== Memory Usage ==="
free -m
echo "=== Disk Space ==="
df -h /
echo "=== Installed Packages Update Check ==="
dnf check-update --security || true
echo "=== SSM Agent Status ==="
systemctl status amazon-ssm-agent --no-pager | head -n 5
EOF
)

echo "[+] Dispatching SSM Run Command to target: $TARGET_INSTANCE_ID..."

if [[ "$TARGET_INSTANCE_ID" == i-* ]]; then
  TARGET_PARAM="--instance-ids $TARGET_INSTANCE_ID"
else
  TARGET_PARAM="--targets $TARGET_INSTANCE_ID"
fi

COMMAND_OUTPUT=$(aws ssm send-command \
  $TARGET_PARAM \
  --document-name "AWS-RunShellScript" \
  --comment "Audited health and patch check via Systems Manager" \
  --parameters "commands=[\"$COMMANDS_TO_RUN\"]" \
  --output json)

COMMAND_ID=$(echo "$COMMAND_OUTPUT" | grep -o '"CommandId": "[^"]*' | head -1 | cut -d'"' -f4)

echo "[✓] Command successfully queued! CommandId: $COMMAND_ID"
echo "[*] Polling execution status..."

# Wait for command completion
STATUS="Pending"
while [[ "$STATUS" == "Pending" || "$STATUS" == "InProgress" || "$STATUS" == "Delayed" ]]; do
  sleep 2
  STATUS=$(aws ssm list-command-invocations \
    --command-id "$COMMAND_ID" \
    --details \
    --query "CommandInvocations[0].Status" \
    --output text 2>/dev/null || echo "Pending")
  echo "    Current status: $STATUS"
done

echo "=========================================================="
echo " Execution Result (Status: $STATUS)"
echo "=========================================================="

aws ssm list-command-invocations \
  --command-id "$COMMAND_ID" \
  --details \
  --query "CommandInvocations[0].CommandPlugins[0].Output" \
  --output text
