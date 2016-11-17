#!/bin/bash

set -e
set -o pipefail

(which jq   > /dev/null 2>&1) || (echo "jq not found."; exit 1)
(which peco > /dev/null 2>&1) || (echo "peco not found."; exit 1)

show_help () {
  echo "ecs-container-login.sh [options] [command]"
  echo "Run a command in a Docker container managed by ECS"
  echo "Valid options:"
  echo "  -h          Show this help"
  echo "  -c name     Set the ECS cluster name (default: default)"
  echo "  -p          Use public IP address for SSH (default: private)"
  echo "  -u          SSH user (default: ec2-user)"
  echo ""
  echo "Environment variables:"
  echo "  SSH         The SSH command to use (useful if you need a ssh "
  echo "              tunnel or nonstandard port, etc"
  echo "  PECO_CONFIG Path to custom peco config file"
}

OPTIND=1
CLUSTER="default"
USE_PRIVATE=1
SSH_USER="ec2-user"

while getopts "hpc:u:" opt; do
  case "$opt" in
    h)
      show_help
      exit 0
      ;;
    c)
      CLUSTER="$OPTARG"
      ;;
    p)
      USE_PRIVATE=0
      ;;
    u)
      SSH_USER="$OPTARG"
      ;;
  esac
done

shift $((OPTIND-1))

: ${SSH:="ssh"}
REMOTE_CMD=$@
: ${REMOTE_CMD:="bash"}

: ${PECO_CONFIG:=`dirname $0`/peco_config.json}
PECO="peco --rcfile=${PECO_CONFIG}"

SERVICE_ARN=`\
  aws ecs list-services --cluster "$CLUSTER" --output json | \
  jq -r '.serviceArns | join("\n")' | \
  $PECO`

# SERVICE_ARN is in ARN format. However, list-tasks takes service name.
# Does it take service ARN as well?

TASK_ARN=`\
  aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE_ARN" --output json | \
  jq -r '.taskArns | join("\n")' | \
  $PECO`

CONTAINER_INSTANCE_ARN=`\
  aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --output json | \
  jq -r '.tasks[0].containerInstanceArn'`

EC2_INSTANCE_ID=`\
  aws ecs describe-container-instances --cluster "$CLUSTER" --container-instances "$CONTAINER_INSTANCE_ARN" --output json | \
  jq -r '.containerInstances[0].ec2InstanceId'`

INSTANCE_DETAILS=`aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --output json`

CONN_IP=`\
  echo "$INSTANCE_DETAILS" | \
  jq -r '.Reservations[0].Instances[0].PrivateIpAddress'`

if [[ "$USE_PRIVATE" = "0" ]]; then
  CONN_IP=`\
    echo "$INSTANCE_DETAILS" | \
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'`
fi

echo "Connecting to $SSH_USER@$CONN_IP..."

SSHCMD="$SSH $SSH_USER@$CONN_IP"

DOCKER_CONTAINER_NAME=`\
  $SSHCMD curl -s "http://localhost:51678/v1/tasks?taskarn=$TASK_ARN" | \
  jq -r '.Containers[0].DockerName'`

$SSHCMD -t "docker exec -it $DOCKER_CONTAINER_NAME $REMOTE_CMD"

