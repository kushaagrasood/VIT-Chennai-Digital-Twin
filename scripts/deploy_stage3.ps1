# ==============================================================================
# VIT Chennai Campus AI Digital Twin - Stage 3: Monitoring & Observability Deployment (PowerShell)
# ==============================================================================
# Architecture: Amazon CloudWatch Alarms + CloudWatch Dashboard
# Target Region: ap-south-1
# AWS CLI Profile: vit-deploy
#
# Idempotency & Safety:
# - Creates or updates CloudWatch alarms for Lambda errors, throttling, and venue threshold alerts.
# - Deploys a unified CloudWatch dashboard (free tier eligible: 3 dashboards included free).
# - Sets up a log metric filter on /aws/lambda/vit-telemetry-handler for VENUE_THRESHOLD_ALARM.
# - Prompts for user confirmation before modifying AWS resources.
#
# Usage:
#   .\scripts\deploy_stage3.ps1
#
# Custom overrides:
#   .\scripts\deploy_stage3.ps1 -Profile "vit-deploy" -Region "ap-south-1" -Force
# ==============================================================================

[CmdletBinding()]
param (
    [string]$Region = $(if ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }),
    [string]$Profile = $(if ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }),
    [string]$LambdaName = "vit-telemetry-handler",
    [string]$TableName = "vit-campus-telemetry",
    [string]$DashboardName = "vit-campus-digital-twin-dashboard",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Fail-fast validation if any parameter was provided as blank or whitespace
if ($PSBoundParameters.ContainsKey("Region") -and [string]::IsNullOrWhiteSpace($Region)) {
    Write-Error "Validation failed: AWS Region was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("Profile") -and [string]::IsNullOrWhiteSpace($Profile)) {
    Write-Error "Validation failed: AWS CLI Profile was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("LambdaName") -and [string]::IsNullOrWhiteSpace($LambdaName)) {
    Write-Error "Validation failed: Lambda function name was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("TableName") -and [string]::IsNullOrWhiteSpace($TableName)) {
    Write-Error "Validation failed: DynamoDB Table name was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("DashboardName") -and [string]::IsNullOrWhiteSpace($DashboardName)) {
    Write-Error "Validation failed: CloudWatch Dashboard name was provided but is blank or empty."
    exit 1
}

# Parameter normalization with defaults
$Profile = if ($Profile -and $Profile.Trim() -ne "") { $Profile.Trim() } elseif ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }
$Region = if ($Region -and $Region.Trim() -ne "") { $Region.Trim() } elseif ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }
$LambdaName = if ($LambdaName -and $LambdaName.Trim() -ne "") { $LambdaName.Trim() } else { "vit-telemetry-handler" }
$TableName = if ($TableName -and $TableName.Trim() -ne "") { $TableName.Trim() } else { "vit-campus-telemetry" }
$DashboardName = if ($DashboardName -and $DashboardName.Trim() -ne "") { $DashboardName.Trim() } else { "vit-campus-digital-twin-dashboard" }

# Syntax and format verification
if ([string]::IsNullOrWhiteSpace($Region) -or -not ($Region -match '^[a-z]{2}-[a-z]+-[0-9]$')) {
    Write-Error "Validation failed: Region '$Region' is invalid. Expected format like 'ap-south-1'."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($Profile) -or -not ($Profile -match '^[a-zA-Z0-9_.-]+$')) {
    Write-Error "Validation failed: Profile '$Profile' is invalid."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($LambdaName) -or -not ($LambdaName -match '^[a-zA-Z0-9-_]{1,64}$')) {
    Write-Error "Validation failed: LambdaName '$LambdaName' is invalid."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($TableName) -or -not ($TableName -match '^[a-zA-Z0-9_.-]{3,255}$')) {
    Write-Error "Validation failed: TableName '$TableName' is invalid."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($DashboardName) -or -not ($DashboardName -match '^[a-zA-Z0-9-_]{1,255}$')) {
    Write-Error "Validation failed: DashboardName '$DashboardName' is invalid."
    exit 1
}

function Invoke-Native {
    param([scriptblock]$Script)
    $prev = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $Script
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Invoke-AwsChecked {
    param(
        [scriptblock]$Command,
        [string]$StepDescription
    )
    & $Command
    if ($LASTEXITCODE -ne 0) {
        Write-Error "AWS CLI execution failed during: $StepDescription (Exit code: $LASTEXITCODE). Aborting Stage 3 deployment."
        exit $LASTEXITCODE
    }
}

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "VIT Chennai AI Digital Twin - Stage 3: Monitoring & Observability" -ForegroundColor Cyan
Write-Host "Target AWS Region: $Region | Profile: $Profile" -ForegroundColor DarkGray
Write-Host "Lambda Function:   $LambdaName" -ForegroundColor DarkGray
Write-Host "DynamoDB Table:    $TableName" -ForegroundColor DarkGray
Write-Host "Dashboard Name:    $DashboardName" -ForegroundColor DarkGray
Write-Host "==============================================================================" -ForegroundColor Cyan

# 0. Pre-flight Check
Write-Host "`n[0/4] Verifying AWS CLI profile '$Profile'..." -ForegroundColor Yellow
$callerJson = Invoke-Native { aws sts get-caller-identity --profile $Profile --output json 2>$null }
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($callerJson)) {
    Write-Error "Error: AWS CLI profile '$Profile' is not available or authentication failed. Check 'aws configure --profile $Profile'."
    exit 1
}

$callerObj = $callerJson | ConvertFrom-Json
$accountId = $callerObj.Account
$callerArn = $callerObj.Arn
Write-Host "Authenticated as: $callerArn" -ForegroundColor Green
Write-Host "AWS Account ID:   $accountId" -ForegroundColor DarkGray

# Pre-deployment Resource Audit & Confirmation
Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host "STAGE 3 PRE-DEPLOYMENT AUDIT" -ForegroundColor Cyan
Write-Host "The following CloudWatch monitoring resources will be inspected, created, or updated:" -ForegroundColor DarkGray
Write-Host "  1. Metric Filter:      'vit-high-occupancy-filter' on log group /aws/lambda/$LambdaName"
Write-Host "  2. CloudWatch Alarm:   'vit-telemetry-lambda-errors' (Errors > 0 over 5 min)"
Write-Host "  3. CloudWatch Alarm:   'vit-telemetry-lambda-throttles' (Throttles > 0 over 5 min)"
Write-Host "  4. CloudWatch Alarm:   'vit-auditorium-high-occupancy' (Threshold alerts >= 1)"
Write-Host "  5. CloudWatch Dash:    '$DashboardName' (Lambda Invocations, Errors, Latency, DDB Read/Write)"
Write-Host "==============================================================================" -ForegroundColor Cyan

if (-not $Force) {
    $confirm = Read-Host "`nDo you want to proceed with provisioning Stage 3 monitoring resources on AWS? (y/N)"
    if ($confirm.Trim().ToLower() -ne "y") {
        Write-Host "Stage 3 deployment aborted by user. Zero AWS resources were modified." -ForegroundColor Yellow
        exit 0
    }
}

$logGroupName = "/aws/lambda/$LambdaName"

# 1. CloudWatch Logs Metric Filter for Venue Threshold Alarms
Write-Host "`n[1/4] Configuring CloudWatch Logs metric filter for high occupancy events..." -ForegroundColor Yellow
Invoke-AwsChecked {
    aws logs put-metric-filter `
      --log-group-name $logGroupName `
      --filter-name "vit-high-occupancy-filter" `
      --filter-pattern '{ $.event = "VENUE_THRESHOLD_ALARM" }' `
      --metric-transformations "metricName=HighOccupancyAlerts,metricNamespace=VITChennai/DigitalTwin,metricValue=1,defaultValue=0" `
      --region $Region `
      --profile $Profile
} "Put metric filter for high occupancy events"
Write-Host "Metric filter 'vit-high-occupancy-filter' configured." -ForegroundColor Green

# 2. CloudWatch Alarms
Write-Host "`n[2/4] Configuring CloudWatch Alarms..." -ForegroundColor Yellow

# Alarm 1: Lambda Errors
Invoke-AwsChecked {
    aws cloudwatch put-metric-alarm `
      --alarm-name "vit-telemetry-lambda-errors" `
      --alarm-description "Triggers if the VIT Chennai telemetry Lambda encounters execution errors" `
      --metric-name "Errors" `
      --namespace "AWS/Lambda" `
      --dimensions Name=FunctionName,Value=$LambdaName `
      --statistic "Sum" `
      --period 300 `
      --threshold 0 `
      --comparison-operator "GreaterThanThreshold" `
      --evaluation-periods 1 `
      --treat-missing-data "notBreaching" `
      --region $Region `
      --profile $Profile
} "Put alarm vit-telemetry-lambda-errors"
Write-Host "Alarm 'vit-telemetry-lambda-errors' configured." -ForegroundColor Green

# Alarm 2: Lambda Throttles
Invoke-AwsChecked {
    aws cloudwatch put-metric-alarm `
      --alarm-name "vit-telemetry-lambda-throttles" `
      --alarm-description "Triggers if the VIT Chennai telemetry Lambda is throttled by concurrency limits" `
      --metric-name "Throttles" `
      --namespace "AWS/Lambda" `
      --dimensions Name=FunctionName,Value=$LambdaName `
      --statistic "Sum" `
      --period 300 `
      --threshold 0 `
      --comparison-operator "GreaterThanThreshold" `
      --evaluation-periods 1 `
      --treat-missing-data "notBreaching" `
      --region $Region `
      --profile $Profile
} "Put alarm vit-telemetry-lambda-throttles"
Write-Host "Alarm 'vit-telemetry-lambda-throttles' configured." -ForegroundColor Green

# Alarm 3: Venue High Occupancy Alert
Invoke-AwsChecked {
    aws cloudwatch put-metric-alarm `
      --alarm-name "vit-auditorium-high-occupancy" `
      --alarm-description "Triggers when Mahatma Gandhi Auditorium occupancy exceeds safety threshold (>= 80%)" `
      --metric-name "HighOccupancyAlerts" `
      --namespace "VITChennai/DigitalTwin" `
      --statistic "Sum" `
      --period 300 `
      --threshold 0 `
      --comparison-operator "GreaterThanThreshold" `
      --evaluation-periods 1 `
      --treat-missing-data "notBreaching" `
      --region $Region `
      --profile $Profile
} "Put alarm vit-auditorium-high-occupancy"
Write-Host "Alarm 'vit-auditorium-high-occupancy' configured." -ForegroundColor Green

# 3. CloudWatch Dashboard
Write-Host "`n[3/4] Deploying CloudWatch Dashboard '$DashboardName'..." -ForegroundColor Yellow
$dashboardBody = @"
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
        "region": "$Region",
        "metrics": [
          [ "AWS/Lambda", "Invocations", "FunctionName", "$LambdaName", { "stat": "Sum", "color": "#1f77b4" } ],
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
        "region": "$Region",
        "metrics": [
          [ "AWS/Lambda", "Duration", "FunctionName", "$LambdaName", { "stat": "Average", "label": "Avg Duration (ms)", "color": "#2ca02c" } ],
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
        "region": "$Region",
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
        "region": "$Region",
        "metrics": [
          [ "AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "$TableName", { "stat": "Sum", "color": "#9467bd" } ],
          [ ".", "ConsumedReadCapacityUnits", ".", ".", { "stat": "Sum", "color": "#8c564b" } ]
        ],
        "period": 300,
        "view": "timeSeries"
      }
    }
  ]
}
"@

$tmpDashPath = Join-Path $env:TEMP "vit_dashboard_$PID.json"
$dashboardBody | Out-File -FilePath $tmpDashPath -Encoding ascii

Invoke-AwsChecked {
    aws cloudwatch put-dashboard `
      --dashboard-name $DashboardName `
      --dashboard-body "file://$tmpDashPath" `
      --region $Region `
      --profile $Profile
} "Put CloudWatch Dashboard"

Remove-Item -Path $tmpDashPath -Force -ErrorAction SilentlyContinue
Write-Host "CloudWatch Dashboard '$DashboardName' deployed successfully." -ForegroundColor Green

Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host "Stage 3 Monitoring & Observability Deployment Complete!" -ForegroundColor Green
Write-Host "CloudWatch Dashboard URL:" -ForegroundColor Cyan
Write-Host "https://${Region}.console.aws.amazon.com/cloudwatch/home?region=${Region}#dashboards:name=${DashboardName}" -ForegroundColor Cyan
Write-Host "Alarms Active:" -ForegroundColor DarkGray
Write-Host "  - vit-telemetry-lambda-errors" -ForegroundColor DarkGray
Write-Host "  - vit-telemetry-lambda-throttles" -ForegroundColor DarkGray
Write-Host "  - vit-auditorium-high-occupancy" -ForegroundColor DarkGray
Write-Host "==============================================================================" -ForegroundColor Green
$global:LASTEXITCODE = 0
exit 0

