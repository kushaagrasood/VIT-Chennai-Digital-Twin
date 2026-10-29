#!/usr/bin/env bash
# ==============================================================================
# VIT Chennai Campus AI Digital Twin - AWS Serverless Backend Deployment Script (Bash)
# ==============================================================================
# Architecture: Amazon API Gateway (HTTP API v2) -> AWS Lambda (Node.js 22.x) -> Amazon DynamoDB
# Target Region: ap-south-1
# AWS CLI Profile: vit-deploy
# ==============================================================================

set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
PROFILE="${AWS_PROFILE:-vit-deploy}"
TABLE_NAME="vit-campus-telemetry"
LAMBDA_NAME="vit-telemetry-handler"
ROLE_NAME="vit-telemetry-lambda-role"
API_NAME="vit-telemetry-api"
FORCE="${FORCE:-false}"

echo "=============================================================================="
echo "VIT Chennai AI Digital Twin - AWS Serverless Backend Deployment"
echo "Target AWS Region: ${REGION} | Profile: ${PROFILE}"
echo "DynamoDB Table:    ${TABLE_NAME}"
echo "Lambda Function:   ${LAMBDA_NAME} (Node.js 22.x on arm64)"
echo "API Gateway:       ${API_NAME} (HTTP API v2 with Stage Throttling)"
echo "=============================================================================="

# 0. Pre-flight Check
echo ""
echo "[0/6] Verifying AWS CLI profile '${PROFILE}'..."
CALLER_JSON=$(aws sts get-caller-identity --profile "${PROFILE}" --output json)
ACCOUNT_ID=$(echo "${CALLER_JSON}" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
CALLER_ARN=$(echo "${CALLER_JSON}" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
echo "Authenticated as: ${CALLER_ARN}"
echo "AWS Account ID:   ${ACCOUNT_ID}"

# Pre-deployment Resource Audit & Confirmation Prompt
echo ""
echo "=============================================================================="
echo "PRE-DEPLOYMENT RESOURCE AUDIT"
echo "The following AWS resources will be inspected, created, or updated:"
echo "  1. DynamoDB Table:   ${TABLE_NAME} (PAY_PER_REQUEST, PK: venueId, SK: sk, TTL: ttl_epoch)"
echo "  2. IAM Role:         ${ROLE_NAME} (Trust: lambda.amazonaws.com, Scoped to ${TABLE_NAME})"
echo "  3. Lambda Function:  ${LAMBDA_NAME} (Runtime: nodejs22.x, arm64, 128MB, 5s timeout)"
echo "  4. CloudWatch Logs:  /aws/lambda/${LAMBDA_NAME} (Retention: 7 days)"
echo "  5. API Gateway:      ${API_NAME} (HTTP API v2, Stage Throttling: Rate 10/s, Burst 20)"
echo "  6. Frontend Config:  public/config.json will be updated with live API endpoint"
echo "=============================================================================="

if [ "${FORCE}" != "true" ] && [ "${FORCE}" != "1" ]; then
  read -r -p "Proceed with provisioning / updating these resources on AWS? (y/N) " confirm
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    echo "Deployment aborted by user. Zero AWS resources were modified."
    exit 0
  fi
fi

# 1. DynamoDB Table
echo ""
echo "[1/6] Checking DynamoDB table '${TABLE_NAME}'..."
TABLE_STATUS=$(aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${REGION}" --profile "${PROFILE}" --query "Table.TableStatus" --output text 2>/dev/null || echo "None")

if [ "${TABLE_STATUS}" == "None" ] || [ -z "${TABLE_STATUS}" ]; then
  echo "Creating DynamoDB table '${TABLE_NAME}' (PAY_PER_REQUEST)..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=venueId,AttributeType=S AttributeName=sk,AttributeType=S \
    --key-schema AttributeName=venueId,KeyType=HASH AttributeName=sk,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" \
    --profile "${PROFILE}" >/dev/null

  echo "Waiting for table to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}" --profile "${PROFILE}"

  echo "Enabling TTL on 'ttl_epoch'..."
  aws dynamodb update-time-to-live \
    --table-name "${TABLE_NAME}" \
    --time-to-live-specification "Enabled=true,AttributeName=ttl_epoch" \
    --region "${REGION}" \
    --profile "${PROFILE}" >/dev/null
  echo "DynamoDB table created and active."
else
  echo "DynamoDB table '${TABLE_NAME}' already exists (Status: ${TABLE_STATUS})."
fi

# 2. IAM Role
echo ""
echo "[2/6] Checking IAM role '${ROLE_NAME}'..."
ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --profile "${PROFILE}" --query "Role.Arn" --output text 2>/dev/null || echo "None")

if [ "${ROLE_ARN}" == "None" ] || [ -z "${ROLE_ARN}" ]; then
  echo "Creating IAM role '${ROLE_NAME}'..."
  cat <<'EOF' > /tmp/vit_trust_policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
  ROLE_ARN=$(aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "file:///tmp/vit_trust_policy.json" \
    --profile "${PROFILE}" \
    --query "Role.Arn" \
    --output text)
  rm -f /tmp/vit_trust_policy.json
  echo "Waiting 10s for IAM propagation..."
  sleep 10
else
  echo "IAM role '${ROLE_NAME}' already exists (${ROLE_ARN})."
fi

# Scoped inline policy
cat <<EOF > /tmp/vit_lambda_policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudWatchLogging",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/lambda/${LAMBDA_NAME}:*"
    },
    {
      "Sid": "DynamoDBScopedAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:ConditionCheckItem"
      ],
      "Resource": "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${TABLE_NAME}"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "vit-telemetry-access" \
  --policy-document file:///tmp/vit_lambda_policy.json \
  --profile "${PROFILE}"
rm -f /tmp/vit_lambda_policy.json

# 3. Package & Deploy Lambda
echo ""
echo "[3/6] Packaging and deploying Lambda '${LAMBDA_NAME}' (nodejs22.x)..."
LAMBDA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../backend/lambda" && pwd)"
if [ ! -d "${LAMBDA_DIR}" ]; then
  echo "Error: Required Lambda directory not found at '${LAMBDA_DIR}'."
  exit 1
fi
if [ ! -f "${LAMBDA_DIR}/index.js" ] || [ ! -f "${LAMBDA_DIR}/package.json" ]; then
  echo "Error: Required Lambda source files missing in '${LAMBDA_DIR}'."
  exit 1
fi
LAMBDA_ZIP="${LAMBDA_DIR}/lambda.zip"
rm -f "${LAMBDA_ZIP}"
(cd "${LAMBDA_DIR}" && zip -q -r lambda.zip index.js package.json)

LAMBDA_ARN=$(aws lambda get-function --function-name "${LAMBDA_NAME}" --region "${REGION}" --profile "${PROFILE}" --query "Configuration.FunctionArn" --output text 2>/dev/null || echo "None")

if [ "${LAMBDA_ARN}" == "None" ] || [ -z "${LAMBDA_ARN}" ]; then
  echo "Creating Lambda function '${LAMBDA_NAME}' (nodejs22.x, arm64, 128MB)..."
  LAMBDA_ARN=$(aws lambda create-function \
    --function-name "${LAMBDA_NAME}" \
    --runtime "nodejs22.x" \
    --role "${ROLE_ARN}" \
    --handler "index.handler" \
    --zip-file "fileb://${LAMBDA_ZIP}" \
    --timeout 5 \
    --memory-size 128 \
    --architectures "arm64" \
    --environment "Variables={TABLE_NAME=${TABLE_NAME}}" \
    --region "${REGION}" \
    --profile "${PROFILE}" \
    --query "FunctionArn" \
    --output text)
  echo "Lambda created: ${LAMBDA_ARN}"
else
  echo "Updating Lambda function code..."
  aws lambda update-function-code \
    --function-name "${LAMBDA_NAME}" \
    --zip-file "fileb://${LAMBDA_ZIP}" \
    --region "${REGION}" \
    --profile "${PROFILE}" >/dev/null
  echo "Lambda code updated."
fi

# 4. CloudWatch Retention
echo ""
echo "[4/6] Setting CloudWatch log retention to 7 days..."
aws logs create-log-group --log-group-name "/aws/lambda/${LAMBDA_NAME}" --region "${REGION}" --profile "${PROFILE}" 2>/dev/null || true
aws logs put-retention-policy \
  --log-group-name "/aws/lambda/${LAMBDA_NAME}" \
  --retention-in-days 7 \
  --region "${REGION}" \
  --profile "${PROFILE}"

# 5. API Gateway HTTP API v2 with Stage Throttling
echo ""
echo "[5/6] Checking API Gateway '${API_NAME}'..."
API_ID=$(aws apigatewayv2 get-apis --region "${REGION}" --profile "${PROFILE}" --query "Items[?Name=='${API_NAME}'].ApiId" --output text 2>/dev/null || echo "None")

if [ "${API_ID}" == "None" ] || [ -z "${API_ID}" ]; then
  echo "Creating API Gateway HTTP API '${API_NAME}'..."
  CORS_CONFIG='AllowOrigins=["https://d457w1fwy7gg.cloudfront.net","http://localhost:5173","http://localhost:4173"],AllowMethods=["GET","POST","OPTIONS"],AllowHeaders=["Content-Type","X-Simulation-Token"],MaxAge=86400'
  API_ID=$(aws apigatewayv2 create-api \
    --name "${API_NAME}" \
    --protocol-type HTTP \
    --cors-configuration "${CORS_CONFIG}" \
    --target "${LAMBDA_ARN}" \
    --region "${REGION}" \
    --profile "${PROFILE}" \
    --query "ApiId" \
    --output text)
  echo "API Gateway created (ID: ${API_ID})"
else
  echo "API Gateway already exists (ID: ${API_ID})"
fi

# Configure Stage-Level Throttling (Rate: 10 req/s, Burst: 20)
echo "Configuring API Gateway stage throttling (Rate limit = 10 req/s, Burst = 20)..."
aws apigatewayv2 update-stage \
  --api-id "${API_ID}" \
  --stage-name '$default' \
  --default-route-settings "ThrottlingBurstLimit=20,ThrottlingRateLimit=10" \
  --region "${REGION}" \
  --profile "${PROFILE}" >/dev/null

# Grant permission to invoke
aws lambda add-permission \
  --function-name "${LAMBDA_NAME}" \
  --statement-id "apigateway-invoke-${API_ID}" \
  --action "lambda:InvokeFunction" \
  --principal "apigateway.amazonaws.com" \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*" \
  --region "${REGION}" \
  --profile "${PROFILE}" 2>/dev/null || true

API_ENDPOINT="https://${API_ID}.execute-api.${REGION}.amazonaws.com"

# 6. Update Frontend Configuration (public/config.json)
echo ""
echo "[6/6] Updating public/config.json with live API endpoint..."
CONFIG_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../public" && pwd)/config.json"
echo "{\"apiUrl\": \"${API_ENDPOINT}\"}" > "${CONFIG_PATH}"
echo "Saved API endpoint to: ${CONFIG_PATH}"

echo ""
echo "=============================================================================="
echo "Backend deployment complete!"
echo "Live API Gateway Endpoint: ${API_ENDPOINT}"
echo "Stage Throttling:          10 req/sec (Burst: 20)"
echo "Routes available:"
echo "  GET  ${API_ENDPOINT}/telemetry/latest?venueId=Building024"
echo "  POST ${API_ENDPOINT}/telemetry"
echo "Next step to deploy frontend with cloud telemetry:"
echo "  ./scripts/deploy_s3_cloudfront.sh"
echo "=============================================================================="
