#!/usr/bin/env bash
# ==============================================================================
# VIT Chennai Campus AI Digital Twin - Stage 3: Monitoring & Observability Deployment (Bash)
# ==============================================================================
# Architecture: Amazon CloudWatch Alarms + CloudWatch Dashboard
# Target Region: ap-south-1
# AWS CLI Profile: vit-deploy
# ==============================================================================

set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
PROFILE="${AWS_PROFILE:-vit-deploy}"
LAMBDA_NAME="vit-telemetry-handler"
TABLE_NAME="vit-campus-telemetry"
DASHBOARD_NAME="vit-campus-digital-twin-dashboard"
FORCE="${FORCE:-false}"

echo "=============================================================================="
echo "VIT Chennai AI Digital Twin - Stage 3: Monitoring & Observability"
echo "Target AWS Region: ${REGION} | Profile: ${PROFILE}"
echo "Lambda Function:   ${LAMBDA_NAME}"
echo "DynamoDB Table:    ${TABLE_NAME}"
echo "Dashboard Name:    ${DASHBOARD_NAME}"
echo "=============================================================================="

# 0. Pre-flight Check
echo ""
echo "[0/4] Verifying AWS CLI profile '${PROFILE}'..."
CALLER_JSON=$(aws sts get-caller-identity --profile "${PROFILE}" --output json)
ACCOUNT_ID=$(echo "${CALLER_JSON}" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
CALLER_ARN=$(echo "${CALLER_JSON}" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
echo "Authenticated as: ${CALLER_ARN}"
echo "AWS Account ID:   ${ACCOUNT_ID}"

# Pre-deployment Resource Audit & Confirmation
echo ""
echo "=============================================================================="
echo "STAGE 3 PRE-DEPLOYMENT AUDIT"
echo "The following CloudWatch monitoring resources will be inspected, created, or updated:"
echo "  1. Metric Filter:      'vit-high-occupancy-filter' on log group /aws/lambda/${LAMBDA_NAME}"
echo "  2. CloudWatch Alarm:   'vit-telemetry-lambda-errors' (Errors > 0 over 5 min)"
echo "  3. CloudWatch Alarm:   'vit-telemetry-lambda-throttles' (Throttles > 0 over 5 min)"
echo "  4. CloudWatch Alarm:   'vit-auditorium-high-occupancy' (Threshold alerts >= 1)"
echo "  5. CloudWatch Dash:    '${DASHBOARD_NAME}' (Lambda Invocations, Errors, Latency, DDB Read/Write)"
echo "=============================================================================="

if [ "${FORCE}" != "true" ] && [ "${FORCE}" != "1" ]; then
  read -r -p "Proceed with provisioning Stage 3 monitoring resources on AWS? (y/N) " confirm
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    echo "Stage 3 deployment aborted by user. Zero AWS resources were modified."
    exit 0
  fi
fi

LOG_GROUP="/aws/lambda/${LAMBDA_NAME}"

# 1. Metric Filter
echo ""
echo "[1/4] Configuring CloudWatch Logs metric filter for high occupancy events..."
aws logs put-metric-filter \
  --log-group-name "${LOG_GROUP}" \
  --filter-name "vit-high-occupancy-filter" \
  --filter-pattern '{ $.event = "VENUE_THRESHOLD_ALARM" }' \
  --metric-transformations "metricName=HighOccupancyAlerts,metricNamespace=VITChennai/DigitalTwin,metricValue=1,defaultValue=0" \
  --region "${REGION}" \
  --profile "${PROFILE}"
echo "Metric filter configured."

# 2. CloudWatch Alarms
echo ""
echo "[2/4] Configuring CloudWatch Alarms..."

aws cloudwatch put-metric-alarm \
  --alarm-name "vit-telemetry-lambda-errors" \
  --alarm-description "Triggers if the VIT Chennai telemetry Lambda encounters execution errors" \
  --metric-name "Errors" \
  --namespace "AWS/Lambda" \
  --dimensions Name=FunctionName,Value="${LAMBDA_NAME}" \
  --statistic "Sum" \
  --period 300 \
  --threshold 0 \
  --comparison-operator "GreaterThanThreshold" \
  --evaluation-periods 1 \
  --treat-missing-data "notBreaching" \
  --region "${REGION}" \
  --profile "${PROFILE}"

aws cloudwatch put-metric-alarm \
  --alarm-name "vit-telemetry-lambda-throttles" \
  --alarm-description "Triggers if the VIT Chennai telemetry Lambda is throttled by concurrency limits" \
  --metric-name "Throttles" \
  --namespace "AWS/Lambda" \
  --dimensions Name=FunctionName,Value="${LAMBDA_NAME}" \
  --statistic "Sum" \
  --period 300 \
  --threshold 0 \
  --comparison-operator "GreaterThanThreshold" \
  --evaluation-periods 1 \
  --treat-missing-data "notBreaching" \
  --region "${REGION}" \
  --profile "${PROFILE}"

aws cloudwatch put-metric-alarm \
  --alarm-name "vit-auditorium-high-occupancy" \
  --alarm-description "Triggers when Mahatma Gandhi Auditorium occupancy exceeds safety threshold (>= 80%)" \
  --metric-name "HighOccupancyAlerts" \
  --namespace "VITChennai/DigitalTwin" \
  --statistic "Sum" \
  --period 300 \
  --threshold 0 \
  --comparison-operator "GreaterThanThreshold" \
  --evaluation-periods 1 \
  --treat-missing-data "notBreaching" \
  --region "${REGION}" \
  --profile "${PROFILE}"
echo "CloudWatch Alarms configured."

# 3. CloudWatch Dashboard
echo ""
echo "[3/4] Deploying CloudWatch Dashboard '${DASHBOARD_NAME}'..."
cat <<EOF > /tmp/vit_dashboard.json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "Lambda Invocations & Errors",
        "region": "${REGION}",
        "metrics": [
          [ "AWS/Lambda", "Invocations", "FunctionName", "${LAMBDA_NAME}", { "stat": "Sum", "color": "#1f77b4" } ],
          [ ".", "Errors", ".", ".", { "stat": "Sum", "color": "#d62728" } ]
        ],
        "period": 300,
        "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "Lambda Execution Duration (ms)",
        "region": "${REGION}",
        "metrics": [
          [ "AWS/Lambda", "Duration", "FunctionName", "${LAMBDA_NAME}", { "stat": "Average", "label": "Avg Duration (ms)", "color": "#2ca02c" } ],
          [ ".", ".", ".", ".", { "stat": "p95", "label": "p95 Duration (ms)", "color": "#ff7f0e" } ]
        ],
        "period": 300,
        "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "Venue High-Occupancy Alarms (MG Auditorium >= 80%)",
        "region": "${REGION}",
        "metrics": [
          [ "VITChennai/DigitalTwin", "HighOccupancyAlerts", { "stat": "Sum", "color": "#d62728" } ]
        ],
        "period": 300,
        "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "DynamoDB Consumed Capacity (Units)",
        "region": "${REGION}",
        "metrics": [
          [ "AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "${TABLE_NAME}", { "stat": "Sum", "color": "#9467bd" } ],
          [ ".", "ConsumedReadCapacityUnits", ".", ".", { "stat": "Sum", "color": "#8c564b" } ]
        ],
        "period": 300,
        "view": "timeSeries"
      }
    }
  ]
}
EOF

aws cloudwatch put-dashboard \
  --dashboard-name "${DASHBOARD_NAME}" \
  --dashboard-body file:///tmp/vit_dashboard.json \
  --region "${REGION}" \
  --profile "${PROFILE}"
rm -f /tmp/vit_dashboard.json

echo ""
echo "=============================================================================="
echo "Stage 3 Monitoring Deployment Complete!"
echo "CloudWatch Dashboard URL:"
echo "https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=${DASHBOARD_NAME}"
echo "=============================================================================="

