# ==============================================================================
# VIT Chennai Campus AI Digital Twin - AWS Serverless Backend Deployment Script (PowerShell)
# ==============================================================================
# Architecture: Amazon API Gateway (HTTP API v2) -> AWS Lambda (Node.js 22.x) -> Amazon DynamoDB
# Target Region: ap-south-1
# AWS CLI Profile: vit-deploy
#
# Idempotency & Safety:
# - Displays a complete pre-deployment audit summary and prompts for explicit confirmation.
# - Checks if DynamoDB table, IAM role, Lambda function, or API Gateway already exist.
# - Updates existing resources without destructive recreate and modifies only project-specific resources.
# - Configures least-privilege IAM policies scoped strictly to the telemetry table and log group.
# - Configures server-side API Gateway stage throttling (Rate limit = 10 req/s, Burst = 20).
# - Automatically updates public/config.json with the deployed API endpoint URL.
#
# Usage:
#   .\scripts\deploy_backend.ps1
#
# Custom overrides:
#   .\scripts\deploy_backend.ps1 -Profile "vit-deploy" -Region "ap-south-1" -Force
# ==============================================================================

[CmdletBinding()]
param (
    [string]$Region = $(if ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }),
    [string]$Profile = $(if ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }),
    [string]$TableName = $(if ($env:DYNAMODB_TABLE -and $env:DYNAMODB_TABLE.Trim() -ne "") { $env:DYNAMODB_TABLE.Trim() } else { "vit-campus-telemetry" }),
    [string]$LambdaName = $(if ($env:LAMBDA_FUNCTION_NAME -and $env:LAMBDA_FUNCTION_NAME.Trim() -ne "") { $env:LAMBDA_FUNCTION_NAME.Trim() } else { "vit-telemetry-handler" }),
    [string]$RoleName = $(if ($env:LAMBDA_ROLE_NAME -and $env:LAMBDA_ROLE_NAME.Trim() -ne "") { $env:LAMBDA_ROLE_NAME.Trim() } else { "vit-telemetry-lambda-role" }),
    [string]$ApiName = $(if ($env:API_GATEWAY_NAME -and $env:API_GATEWAY_NAME.Trim() -ne "") { $env:API_GATEWAY_NAME.Trim() } else { "vit-telemetry-api" }),
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
if ($PSBoundParameters.ContainsKey("TableName") -and [string]::IsNullOrWhiteSpace($TableName)) {
    Write-Error "Validation failed: DynamoDB Table name was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("LambdaName") -and [string]::IsNullOrWhiteSpace($LambdaName)) {
    Write-Error "Validation failed: Lambda function name was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("RoleName") -and [string]::IsNullOrWhiteSpace($RoleName)) {
    Write-Error "Validation failed: IAM Role name was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("ApiName") -and [string]::IsNullOrWhiteSpace($ApiName)) {
    Write-Error "Validation failed: API Gateway name was provided but is blank or empty."
    exit 1
}

# Parameter normalization with environment fallbacks
$Region = if ($Region -and $Region.Trim() -ne "") { $Region.Trim() } elseif ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }
$Profile = if ($Profile -and $Profile.Trim() -ne "") { $Profile.Trim() } elseif ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }
$TableName = if ($TableName -and $TableName.Trim() -ne "") { $TableName.Trim() } elseif ($env:DYNAMODB_TABLE -and $env:DYNAMODB_TABLE.Trim() -ne "") { $env:DYNAMODB_TABLE.Trim() } else { "vit-campus-telemetry" }
$LambdaName = if ($LambdaName -and $LambdaName.Trim() -ne "") { $LambdaName.Trim() } elseif ($env:LAMBDA_FUNCTION_NAME -and $env:LAMBDA_FUNCTION_NAME.Trim() -ne "") { $env:LAMBDA_FUNCTION_NAME.Trim() } else { "vit-telemetry-handler" }
$RoleName = if ($RoleName -and $RoleName.Trim() -ne "") { $RoleName.Trim() } elseif ($env:LAMBDA_ROLE_NAME -and $env:LAMBDA_ROLE_NAME.Trim() -ne "") { $env:LAMBDA_ROLE_NAME.Trim() } else { "vit-telemetry-lambda-role" }
$ApiName = if ($ApiName -and $ApiName.Trim() -ne "") { $ApiName.Trim() } elseif ($env:API_GATEWAY_NAME -and $env:API_GATEWAY_NAME.Trim() -ne "") { $env:API_GATEWAY_NAME.Trim() } else { "vit-telemetry-api" }

# Syntax and format verification
if ([string]::IsNullOrWhiteSpace($Region) -or -not ($Region -match '^[a-z]{2}-[a-z]+-[0-9]$')) {
    Write-Error "Validation failed: Region '$Region' is invalid. Expected format like 'ap-south-1'."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($Profile) -or -not ($Profile -match '^[a-zA-Z0-9_.-]+$')) {
    Write-Error "Validation failed: Profile '$Profile' is invalid."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($TableName) -or -not ($TableName -match '^[a-zA-Z0-9_.-]{3,255}$')) {
    Write-Error "Validation failed: DynamoDB Table name is required and must match [a-zA-Z0-9_.-]{3,255} (got: '$TableName')."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($LambdaName) -or -not ($LambdaName -match '^[a-zA-Z0-9-_]{1,64}$')) {
    Write-Error "Validation failed: Lambda function name is required and must match [a-zA-Z0-9-_]{1,64} (got: '$LambdaName')."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($RoleName) -or -not ($RoleName -match '^[\w+=,.@-]{1,64}$')) {
    Write-Error "Validation failed: IAM Role name is required and must match [\w+=,.@-]{1,64} (got: '$RoleName')."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($ApiName) -or -not ($ApiName -match '^[a-zA-Z0-9-_]{1,128}$')) {
    Write-Error "Validation failed: API Gateway name is required and must match [a-zA-Z0-9-_]{1,128} (got: '$ApiName')."
    exit 1
}

# Helper to execute AWS CLI commands and abort immediately on failure
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
        Write-Error "AWS CLI execution failed during: $StepDescription (Exit code: $LASTEXITCODE). Aborting deployment."
        exit $LASTEXITCODE
    }
}

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "VIT Chennai AI Digital Twin - AWS Serverless Backend Deployment" -ForegroundColor Cyan
Write-Host "Target AWS Region: $Region | Profile: $Profile" -ForegroundColor DarkGray
Write-Host "DynamoDB Table:    $TableName" -ForegroundColor DarkGray
Write-Host "Lambda Function:   $LambdaName (Node.js 22.x on arm64)" -ForegroundColor DarkGray
Write-Host "API Gateway:       $ApiName (HTTP API v2 with Stage Throttling)" -ForegroundColor DarkGray
Write-Host "==============================================================================" -ForegroundColor Cyan

# 0. Pre-flight Check: Verify AWS CLI authentication without leaking credentials
Write-Host "`n[0/6] Verifying AWS CLI profile '$Profile'..." -ForegroundColor Yellow
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

# Pre-deployment Summary and Confirmation Prompt
Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host "PRE-DEPLOYMENT RESOURCE AUDIT" -ForegroundColor Cyan
Write-Host "The following AWS resources will be inspected, created, or updated:" -ForegroundColor DarkGray
Write-Host "  1. DynamoDB Table:   $TableName (PAY_PER_REQUEST, PK: venueId, SK: sk, TTL: ttl_epoch)"
Write-Host "  2. IAM Role:         $RoleName (Trust: lambda.amazonaws.com, Scoped to $TableName)"
Write-Host "  3. Lambda Function:  $LambdaName (Runtime: nodejs22.x, arm64, 128MB, 5s timeout)"
Write-Host "  4. CloudWatch Logs:  /aws/lambda/$LambdaName (Retention: 7 days)"
Write-Host "  5. API Gateway:      $ApiName (HTTP API v2, Stage Throttling: Rate 10/s, Burst 20)"
Write-Host "  6. Frontend Config:  public/config.json will be updated with live API endpoint"
Write-Host "==============================================================================" -ForegroundColor Cyan

if (-not $Force) {
    $confirm = Read-Host "`nDo you want to proceed with provisioning / updating these resources on AWS? (y/N)"
    if ($confirm.Trim().ToLower() -ne "y") {
        Write-Host "Deployment aborted by user. Zero AWS resources were modified." -ForegroundColor Yellow
        exit 0
    }
}

# 1. DynamoDB Table (On-Demand PAY_PER_REQUEST)
Write-Host "`n[1/6] Checking DynamoDB table '$TableName'..." -ForegroundColor Yellow
$tableCheckOut = Invoke-Native { aws dynamodb describe-table --table-name $TableName --region $Region --profile $Profile --query "Table.TableStatus" --output text 2>&1 }
$tableCheckExit = $LASTEXITCODE
$tableCheckText = ($tableCheckOut | Out-String).Trim()

if ($tableCheckExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($tableCheckText) -and $tableCheckText -ne "None") {
    Write-Host "DynamoDB table '$TableName' already exists (Status: $tableCheckText)." -ForegroundColor Green
} elseif ($tableCheckText -match "ResourceNotFoundException" -or $tableCheckText -match "Cannot find table") {
    Write-Host "Creating DynamoDB table '$TableName' (PAY_PER_REQUEST, PK: venueId, SK: sk)..." -ForegroundColor Cyan
    Invoke-AwsChecked {
        aws dynamodb create-table `
          --table-name $TableName `
          --attribute-definitions AttributeName=venueId,AttributeType=S AttributeName=sk,AttributeType=S `
          --key-schema AttributeName=venueId,KeyType=HASH AttributeName=sk,KeyType=RANGE `
          --billing-mode PAY_PER_REQUEST `
          --region $Region `
          --profile $Profile | Out-Null
    } "Create DynamoDB table $TableName"

    Write-Host "Waiting for table to become ACTIVE..." -ForegroundColor DarkGray
    Invoke-AwsChecked {
        aws dynamodb wait table-exists --table-name $TableName --region $Region --profile $Profile
    } "Wait for table $TableName active"

    # Enable TTL on ttl_epoch attribute for 7-day asynchronous retention
    Write-Host "Enabling TTL on attribute 'ttl_epoch'..." -ForegroundColor DarkGray
    Invoke-AwsChecked {
        aws dynamodb update-time-to-live `
          --table-name $TableName `
          --time-to-live-specification "Enabled=true,AttributeName=ttl_epoch" `
          --region $Region `
          --profile $Profile | Out-Null
    } "Enable TTL on table $TableName"
    Write-Host "DynamoDB table '$TableName' created and active with TTL enabled." -ForegroundColor Green
} else {
    Write-Error "Error checking DynamoDB table '$TableName' (Exit code: ${tableCheckExit}): $tableCheckText"
    exit 1
}

# 2. IAM Least-Privilege Execution Role
Write-Host "`n[2/6] Checking IAM role '$RoleName'..." -ForegroundColor Yellow
$roleCheckOut = Invoke-Native { aws iam get-role --role-name $RoleName --profile $Profile --query "Role.Arn" --output text 2>&1 }
$roleCheckExit = $LASTEXITCODE
$roleCheckText = ($roleCheckOut | Out-String).Trim()

if ($roleCheckExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($roleCheckText) -and $roleCheckText -ne "None") {
    $roleArn = $roleCheckText
    Write-Host "IAM role '$RoleName' already exists ($roleArn)." -ForegroundColor Green
} elseif ($roleCheckText -match "NoSuchEntity" -or $roleCheckText -match "cannot be found") {
    Write-Host "Creating IAM role '$RoleName' with Lambda assume-role trust policy..." -ForegroundColor Cyan
    $trustPolicy = @"
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
"@
    # Validate trust policy locally with ConvertFrom-Json before AWS invocation
    try {
        $null = $trustPolicy | ConvertFrom-Json
        Write-Host "Validated trust policy JSON structure successfully." -ForegroundColor DarkGray
    } catch {
        Write-Error "Invalid trust policy JSON: $_"
        exit 1
    }

    # Write trust policy to temporary file without BOM to avoid PowerShell 5.1 quote-stripping issues
    $trustPolicyPath = Join-Path $env:TEMP "vit_trust_policy_$PID.json"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($trustPolicyPath, $trustPolicy, $utf8NoBom)

    try {
        $roleArn = aws iam create-role `
          --role-name $RoleName `
          --assume-role-policy-document "file://$trustPolicyPath" `
          --description "Execution role for VIT Chennai Digital Twin telemetry Lambda" `
          --profile $Profile `
          --query "Role.Arn" `
          --output text

        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($roleArn)) {
            Write-Error "Failed to create IAM role '$RoleName'."
            exit 1
        }
        Write-Host "IAM role created: $roleArn" -ForegroundColor Green
    } finally {
        if (Test-Path $trustPolicyPath) {
            Remove-Item -Path $trustPolicyPath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Waiting 10 seconds for IAM role propagation..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 10
} else {
    Write-Error "Error checking IAM role '$RoleName' (Exit code: ${roleCheckExit}): $roleCheckText"
    exit 1
}

# Put scoped inline policy (least privilege)
Write-Host "Attaching scoped least-privilege policy to '$RoleName'..." -ForegroundColor DarkGray
$policyDoc = @"
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
      "Resource": "arn:aws:logs:${Region}:${accountId}:log-group:/aws/lambda/${LambdaName}:*"
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
      "Resource": "arn:aws:dynamodb:${Region}:${accountId}:table/${TableName}"
    }
  ]
}
"@

# Validate inline policy locally with ConvertFrom-Json before AWS invocation
try {
    $null = $policyDoc | ConvertFrom-Json
} catch {
    Write-Error "Invalid inline policy JSON: $_"
    exit 1
}

$policyDocPath = Join-Path $env:TEMP "vit_lambda_policy_$PID.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($policyDocPath, $policyDoc, $utf8NoBom)

try {
    Invoke-AwsChecked {
        aws iam put-role-policy `
          --role-name $RoleName `
          --policy-name "vit-telemetry-access" `
          --policy-document "file://$policyDocPath" `
          --profile $Profile
    } "Put inline IAM policy"
} finally {
    if (Test-Path $policyDocPath) {
        Remove-Item -Path $policyDocPath -Force -ErrorAction SilentlyContinue
    }
}

# 3. Package & Deploy Lambda Function (Node.js 22.x, arm64)
Write-Host "`n[3/6] Packaging and deploying Lambda function '$LambdaName' (nodejs22.x)..." -ForegroundColor Yellow

$scriptDir = if ($PSScriptRoot -and $PSScriptRoot.Trim() -ne "") { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir -or $scriptDir.Trim() -eq "") { $scriptDir = (Get-Location).Path }
$lambdaDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\backend\lambda"))
$lambdaZipPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\backend\lambda\lambda.zip"))

if (-not (Test-Path -Path $lambdaDir -PathType Container)) {
    Write-Error "Required Lambda source directory not found: '$lambdaDir'."
    exit 1
}

# Explicitly validate required Lambda source files before packaging
$requiredFiles = @("index.js", "package.json")
$sourceFilesToZip = @()

foreach ($fileName in $requiredFiles) {
    $filePath = Join-Path $lambdaDir $fileName
    if (-not (Test-Path -Path $filePath -PathType Leaf)) {
        Write-Error "Required Lambda source file missing: '$filePath'."
        exit 1
    }
    $sourceFilesToZip += (Get-Item -Path $filePath).FullName
}

if ($sourceFilesToZip.Count -eq 0) {
    Write-Error "No Lambda source files identified for packaging in '$lambdaDir'."
    exit 1
}

if (Test-Path -Path $lambdaZipPath) {
    Remove-Item -Path $lambdaZipPath -Force -ErrorAction SilentlyContinue
}

# Compress required Lambda files with progress preference suppressed to avoid console buffer errors
$prevProgress = $ProgressPreference
try {
    $ProgressPreference = "SilentlyContinue"
    Compress-Archive -Path $sourceFilesToZip -DestinationPath $lambdaZipPath -CompressionLevel Optimal
} finally {
    $ProgressPreference = $prevProgress
}

if (-not (Test-Path -Path $lambdaZipPath) -or (Get-Item -Path $lambdaZipPath).Length -eq 0) {
    Write-Error "Failed to generate valid Lambda ZIP package at '$lambdaZipPath'."
    exit 1
}

Write-Host "Created Lambda deployment package ($((Get-Item -Path $lambdaZipPath).Length) bytes)." -ForegroundColor DarkGray

$lambdaCheckOut = Invoke-Native { aws lambda get-function --function-name $LambdaName --region $Region --profile $Profile --query "Configuration.FunctionArn" --output text 2>&1 }
$lambdaCheckExit = $LASTEXITCODE
$lambdaCheckText = ($lambdaCheckOut | Out-String).Trim()

if ($lambdaCheckExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($lambdaCheckText) -and $lambdaCheckText -ne "None") {
    $lambdaArn = $lambdaCheckText
    Write-Host "Updating Lambda function code for '$LambdaName'..." -ForegroundColor Cyan
    Invoke-AwsChecked {
        aws lambda update-function-code `
          --function-name $LambdaName `
          --zip-file "fileb://$lambdaZipPath" `
          --region $Region `
          --profile $Profile | Out-Null
    } "Update Lambda function code"
    Write-Host "Lambda function code updated successfully." -ForegroundColor Green
} elseif ($lambdaCheckText -match "ResourceNotFoundException" -or $lambdaCheckText -match "Function not found") {
    Write-Host "Creating Lambda function '$LambdaName' (nodejs22.x, arm64, 128MB)..." -ForegroundColor Cyan
    
    # Retry loop with backoff for IAM eventual consistency (role propagation)
    $maxAttempts = 5
    $lambdaArn = $null
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $lambdaCreateOut = Invoke-Native {
            aws lambda create-function `
              --function-name $LambdaName `
              --runtime "nodejs22.x" `
              --role $roleArn `
              --handler "index.handler" `
              --zip-file "fileb://$lambdaZipPath" `
              --timeout 5 `
              --memory-size 128 `
              --architectures "arm64" `
              --environment "Variables={TABLE_NAME=$TableName}" `
              --region $Region `
              --profile $Profile `
              --query "FunctionArn" `
              --output text 2>&1
        }
        $lambdaCreateExit = $LASTEXITCODE
        $lambdaCreateText = ($lambdaCreateOut | Out-String).Trim()

        if ($lambdaCreateExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($lambdaCreateText) -and $lambdaCreateText -notmatch "Error") {
            $lambdaArn = $lambdaCreateText
            break
        }

        if ($lambdaCreateText -match "cannot be assumed by Lambda" -and $attempt -lt $maxAttempts) {
            Write-Host "IAM role still replicating to regional Lambda endpoint (attempt $attempt/$maxAttempts). Waiting 5 seconds..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 5
            continue
        }

        Write-Error "Failed to create Lambda function '$LambdaName': $lambdaCreateText"
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($lambdaArn)) {
        Write-Error "Failed to create Lambda function '$LambdaName'."
        exit 1
    }
    Write-Host "Lambda function created: $lambdaArn" -ForegroundColor Green
} else {
    Write-Error "Error checking Lambda function '$LambdaName' (Exit code: ${lambdaCheckExit}): $lambdaCheckText"
    exit 1
}

# 4. CloudWatch Log Retention Policy (7 days)
Write-Host "`n[4/6] Setting CloudWatch log retention to 7 days..." -ForegroundColor Yellow

# Ensure log group exists: create if missing; safely ignore ResourceAlreadyExistsException via Invoke-Native
$createLogOut = Invoke-Native {
    aws logs create-log-group `
      --log-group-name "/aws/lambda/$LambdaName" `
      --region $Region `
      --profile $Profile 2>&1
}
$createLogExit = $LASTEXITCODE
$createLogText = ($createLogOut | Out-String).Trim()

if ($createLogExit -ne 0 -and $createLogText -notmatch "ResourceAlreadyExistsException") {
    Write-Host "Notice: Log group note ($createLogText). Proceeding to retention policy..." -ForegroundColor DarkGray
} elseif ($createLogExit -ne 0) {
    # Handled expected idempotent condition - reset LASTEXITCODE so it does not leak
    $global:LASTEXITCODE = 0
}

Invoke-AwsChecked {
    aws logs put-retention-policy `
      --log-group-name "/aws/lambda/$LambdaName" `
      --retention-in-days 7 `
      --region $Region `
      --profile $Profile
} "Set CloudWatch log retention"

# 5. API Gateway HTTP API v2 with CORS & Server-Side Throttling
Write-Host "`n[5/6] Checking API Gateway '$ApiName'..." -ForegroundColor Yellow
$apiCheckOut = Invoke-Native { aws apigatewayv2 get-apis --region $Region --profile $Profile --output json 2>&1 }
$apiCheckExit = $LASTEXITCODE
$apiCheckText = ($apiCheckOut | Out-String).Trim()

$apiId = $null
if ($apiCheckExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($apiCheckText)) {
    try {
        $apiListObj = $apiCheckText | ConvertFrom-Json
        $matchedApi = $apiListObj.Items | Where-Object { $_.Name -eq $ApiName }
        if ($matchedApi) {
            $apiId = $matchedApi.ApiId
            Write-Host "API Gateway HTTP API '$ApiName' already exists (ID: $apiId)." -ForegroundColor Green
        }
    } catch {
        Write-Error "Failed to parse API Gateway list output: $_"
        exit 1
    }
} else {
    Write-Error "Error checking API Gateway APIs (Exit code: ${apiCheckExit}): $apiCheckText"
    exit 1
}

if (-not $apiId) {
    Write-Host "Creating API Gateway HTTP API '$ApiName' with CORS configuration..." -ForegroundColor Cyan
    $corsJson = @"
{
  "AllowOrigins": [
    "https://d457w1fwy7gg.cloudfront.net",
    "http://localhost:5173",
    "http://localhost:4173"
  ],
  "AllowMethods": [
    "GET",
    "POST",
    "OPTIONS"
  ],
  "AllowHeaders": [
    "Content-Type",
    "X-Simulation-Token"
  ],
  "MaxAge": 86400
}
"@
    try {
        $null = $corsJson | ConvertFrom-Json
    } catch {
        Write-Error "Invalid CORS configuration JSON: $_"
        exit 1
    }

    $corsConfigPath = Join-Path $env:TEMP "vit_cors_config_$PID.json"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($corsConfigPath, $corsJson, $utf8NoBom)

    try {
        $apiId = aws apigatewayv2 create-api `
          --name $ApiName `
          --protocol-type HTTP `
          --cors-configuration "file://$corsConfigPath" `
          --target $lambdaArn `
          --region $Region `
          --profile $Profile `
          --query "ApiId" `
          --output text

        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($apiId)) {
            Write-Error "Failed to create API Gateway HTTP API."
            exit 1
        }
        Write-Host "API Gateway HTTP API created with ID: $apiId" -ForegroundColor Green
    } finally {
        if (Test-Path $corsConfigPath) {
            Remove-Item -Path $corsConfigPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Configure Stage-Level Throttling (Rate: 10 req/s, Burst: 20)
Write-Host "Configuring API Gateway stage throttling (Rate limit = 10 req/s, Burst = 20)..." -ForegroundColor DarkGray
Invoke-AwsChecked {
    aws apigatewayv2 update-stage `
      --api-id $apiId `
      --stage-name '$default' `
      --default-route-settings "ThrottlingBurstLimit=20,ThrottlingRateLimit=10" `
      --region $Region `
      --profile $Profile | Out-Null
} "Configure API Gateway throttling"

# Grant API Gateway permission to invoke Lambda (idempotent)
$statementId = "apigateway-invoke-$apiId"
$addPermOut = Invoke-Native {
    aws lambda add-permission `
      --function-name $LambdaName `
      --statement-id $statementId `
      --action "lambda:InvokeFunction" `
      --principal "apigateway.amazonaws.com" `
      --source-arn "arn:aws:execute-api:${Region}:${accountId}:${apiId}/*" `
      --region $Region `
      --profile $Profile 2>&1
}
$addPermExit = $LASTEXITCODE
$addPermText = ($addPermOut | Out-String).Trim()
if ($addPermExit -ne 0 -and $addPermText -notmatch "ResourceConflictException") {
    Write-Host "Notice: Lambda permission note ($addPermText)." -ForegroundColor DarkGray
    $global:LASTEXITCODE = 0
} elseif ($addPermExit -ne 0) {
    # Handled expected idempotent condition - reset LASTEXITCODE so it does not leak
    $global:LASTEXITCODE = 0
}

$apiEndpoint = "https://${apiId}.execute-api.${Region}.amazonaws.com"

# 6. Update Frontend Configuration (public/config.json)
Write-Host "`n[6/6] Updating public/config.json with live API endpoint..." -ForegroundColor Yellow
$configPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\public\config.json"))
$configDir = Split-Path -Parent $configPath
if (-not (Test-Path -Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}
$configContent = @"
{
  "apiUrl": "$apiEndpoint"
}
"@
$configContent | Out-File -FilePath $configPath -Encoding ascii
Write-Host "Saved API endpoint to: $configPath" -ForegroundColor Green

Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host "Backend deployment complete!" -ForegroundColor Green
Write-Host "Live API Gateway Endpoint: $apiEndpoint" -ForegroundColor Cyan
Write-Host "Stage Throttling:          10 req/sec (Burst: 20)" -ForegroundColor DarkGray
Write-Host "Routes available:" -ForegroundColor DarkGray
Write-Host "  GET  $apiEndpoint/telemetry/latest?venueId=Building024" -ForegroundColor DarkGray
Write-Host "  POST $apiEndpoint/telemetry" -ForegroundColor DarkGray
Write-Host "Next step to deploy frontend with cloud telemetry:" -ForegroundColor Yellow
Write-Host "  .\scripts\deploy_s3_cloudfront.ps1" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Green
$global:LASTEXITCODE = 0
exit 0
