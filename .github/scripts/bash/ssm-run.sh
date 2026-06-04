#!/usr/bin/env bash
# Helper together with ssm-run.sh: Send 1 SSM command, wait for completion, print log, exit if error.
# Usage: ssm_run <timeout_seconds> <step_label> "cmd1" "cmd2" ...
# Env vars required before calling: INSTANCE_ID, AWS_REGION (set in $GITHUB_ENV)
set -euo pipefail

# SSM Poll Function
# Monitor the execution status of an AWS Systems Manager (SSM) command until it completes or times out
wait_ssm() {
  local cmd_id="$1" # The ID for the SSM command has been sent
  local instance="$2" # The ID of the EC2 instance
  local max_wait="${3:-600}" # The maximum time to wait for the command to complete
  local interval=15 # The time to wait between each poll
  local elapsed=0 # The time that has elapsed since the command was sent

  while [ "$elapsed" -lt "$max_wait" ]; do
    local status
    # Get state from AWS CLI
    status=$(aws ssm get-command-invocation \
      --command-id "$cmd_id" \
      --instance-id "$instance" \
      --query "Status" --output text 2>/dev/null || echo "Pending")

    echo "  [${elapsed}s] Status: ${status}"

    case "$status" in
      Success)                              return 0 ;;
      Failed|Cancelled|TimedOut|Undeliverable)
        echo "❌ SSM command failed with status: ${status}"
        return 1 ;;
    esac

    sleep "$interval" # Minimize the risk of being subject to rate limits
    elapsed=$((elapsed + interval)) # Update the total time waited
  done

  echo "❌ ERROR: Timed out after ${max_wait}s"
  return 1
}

# Main Function
# The main controller (orchestrator) is responsible for sending commands to AWS, collecting results, and displaying logs
ssm_run() {
  local timeout="$1"
  local label="$2"
  shift 2 # Remove the first two parameters, and turn all the remaining parameters into an array of shell commands that the developer wants to run on the server
  local -a cmds=("$@")

  # Build JSON from command args while preserving each argument as one command.
  # Some callers pass multi-line command blocks; line-based jq would split those
  # into invalid SSM commands such as "--namespace prometheus".
  local json_cmds parameters_json
  json_cmds=$(jq -cn --args '$ARGS.positional' "${cmds[@]}")
  parameters_json=$(jq -cn --argjson commands "${json_cmds}" '{commands: $commands}')

  echo "🔵 [${label}] Sending SSM command (timeout: ${timeout}s)..."

  local cmd_id
  cmd_id=$(aws ssm send-command \
    --instance-ids "${INSTANCE_ID}" \
    --document-name "AWS-RunShellScript" \
    --timeout-seconds "${timeout}" \
    --parameters "${parameters_json}" \
    --query "Command.CommandId" --output text)

  echo "🔵 CommandId: ${cmd_id}"

  local failed=0
  wait_ssm "${cmd_id}" "${INSTANCE_ID}" $((timeout + 90)) || failed=1

  echo "=== STDOUT ==="
  aws ssm get-command-invocation \
    --command-id "${cmd_id}" --instance-id "${INSTANCE_ID}" \
    --query "StandardOutputContent" --output text

  echo "=== STDERR ==="
  aws ssm get-command-invocation \
    --command-id "${cmd_id}" --instance-id "${INSTANCE_ID}" \
    --query "StandardErrorContent" --output text

  if [ "$failed" = "1" ]; then
    echo "❌ [${label}] FAILED"
    exit 1
  fi

  echo "✅ [${label}] OK"
}

# Export for sub-scripts
export -f wait_ssm ssm_run
