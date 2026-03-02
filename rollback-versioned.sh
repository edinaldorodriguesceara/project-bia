#!/bin/bash
set -e

REGION="us-east-1"
ECR_REPO="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-definition-bia"

if [ -z "$1" ]; then
  echo "Uso: ./rollback-versioned.sh <commit-hash>"
  echo ""
  echo "Versões disponíveis:"
  aws ecr describe-images --repository-name $ECR_REPO --region $REGION --query 'sort_by(imageDetails,&imagePushedAt)[*].[imageTags[0],imagePushedAt]' --output table
  exit 1
fi

TARGET_TAG=$1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"

echo "==> Rollback para versão: $TARGET_TAG"

# Verificar se imagem existe
aws ecr describe-images --repository-name $ECR_REPO --region $REGION --image-ids imageTag=$TARGET_TAG > /dev/null

# Criar task definition
TEMP_FILE=$(mktemp)
aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition' > $TEMP_FILE
NEW_TASK=$(jq --arg img "$ECR_URI:$TARGET_TAG" '.containerDefinitions[0].image = $img | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)' $TEMP_FILE)
echo $NEW_TASK > $TEMP_FILE
NEW_REVISION=$(aws ecs register-task-definition --region $REGION --cli-input-json file://$TEMP_FILE --query 'taskDefinition.revision' --output text)
rm -f $TEMP_FILE

echo "==> Task Definition: $TASK_FAMILY:$NEW_REVISION"

# Update service
aws ecs update-service --region $REGION --cluster $CLUSTER --service $SERVICE --task-definition $TASK_FAMILY:$NEW_REVISION > /dev/null

echo "==> Rollback iniciado. Aguardando estabilização..."
aws ecs wait services-stable --region $REGION --cluster $CLUSTER --services $SERVICE

echo "==> Rollback concluído: $TARGET_TAG"
