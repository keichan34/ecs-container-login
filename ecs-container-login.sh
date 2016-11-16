#!/bin/bash

set -e
set -o pipefail

CLUSTER=$1
: ${CLUSTER:="default"}

: ${SSH:="ssh"}

SERVICE_ARN=`\
  aws ecs list-services --cluster "$CLUSTER" --output json | \
  jq -r '.serviceArns | join("\n")' | \
  peco`

# SERVICE_ARN is in ARN format. However, list-tasks takes service name.
# Does it take service ARN as well?

TASK_ARN=`\
  aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE_ARN" --output json | \
  jq -r '.taskArns | join("\n")' | \
  peco`

CONTAINER_INSTANCE_ARN=`\
  aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --output json | \
  jq -r '.tasks[0].containerInstanceArn'`

EC2_INSTANCE_ID=`\
  aws ecs describe-container-instances --cluster "$CLUSTER" --container-instances "$CONTAINER_INSTANCE_ARN" --output json | \
  jq -r '.containerInstances[0].ec2InstanceId'`

INSTANCE_DETAILS=`aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --output json`

INTERNAL_IP=`\
  echo "$INSTANCE_DETAILS" | \
  jq -r '.Reservations[0].Instances[0].PrivateIpAddress'`

EXTERNAL_IP=`\
  echo "$INSTANCE_DETAILS" | \
  jq -r '.Reservations[0].Instances[0].PublicIpAddress'`

# echo "On $INTERNAL_IP,"

# Introspect agent to find the docker name of the container:
# curl http://localhost:51678/v1/tasks?taskarn=<task ARN>
# find docker name, use that to exec

DOCKER_CONTAINER_NAME=`\
  $SSH ec2-user@$EXTERNAL_IP curl -s "http://localhost:51678/v1/tasks?taskarn=$TASK_ARN" | \
  jq -r '.Containers[0].DockerName'`

$SSH ec2-user@$EXTERNAL_IP -t "docker exec -it $DOCKER_CONTAINER_NAME bash"

