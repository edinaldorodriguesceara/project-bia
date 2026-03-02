#!/bin/bash
set -e

REGION="us-east-1"
ECR_REPO="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-definition-bia"

COMMIT_HASH=$(git rev-parse --short=7 HEAD)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"

echo "==> Deploy com versionamento"
echo "Commit: $COMMIT_HASH"
echo "ECR: $ECR_URI:$COMMIT_HASH"

# Login ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URI

# Build
docker build -t $ECR_URI:$COMMIT_HASH .

# Push
docker push $ECR_URI:$COMMIT_HASH

# Criar task definition
TEMP_FILE=$(mktemp)
aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition' > $TEMP_FILE
NEW_TASK=$(jq --arg img "$ECR_URI:$COMMIT_HASH" '.containerDefinitions[0].image = $img | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)' $TEMP_FILE)
echo $NEW_TASK > $TEMP_FILE
NEW_REVISION=$(aws ecs register-task-definition --region $REGION --cli-input-json file://$TEMP_FILE --query 'taskDefinition.revision' --output text)
rm -f $TEMP_FILE

echo "==> Task Definition: $TASK_FAMILY:$NEW_REVISION"

# Update service
aws ecs update-service --region $REGION --cluster $CLUSTER --service $SERVICE --task-definition $TASK_FAMILY:$NEW_REVISION > /dev/null

echo "==> Deploy iniciado. Aguardando estabilização..."
aws ecs wait services-stable --region $REGION --cluster $CLUSTER --services $SERVICE

echo "==> Deploy concluído: $COMMIT_HASH"
