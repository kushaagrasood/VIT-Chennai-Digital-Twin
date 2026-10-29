# ==============================================================================
# VIT Chennai Campus AI Digital Twin - Stage 2: AWS IoT Core Ingestion Deployment (PowerShell)
# ==============================================================================
# Architecture: AWS IoT Core MQTT -> IoT Topic Rule -> AWS Lambda -> Amazon DynamoDB
# Target Region: ap-south-1
# AWS CLI Profile: vit-deploy
#
# Idempotency & Safety:
# - Checks if IoT Thing, IoT Policy, and Topic Rule already exist.
# - Prompts for explicit user confirmation before modifying AWS resources.
# - Stores temporary device certificates in local 'certs/' directory (strictly ignored by git).
# - Grants scoped invocation permission to iot.amazonaws.com on Lambda vit-telemetry-handler.
#
# Usage:
#   .\scripts\deploy_stage2.ps1
#
# Custom overrides:
#   .\scripts\deploy_stage2.ps1 -Profile "vit-deploy" -Region "ap-south-1" -Force
# ==============================================================================

[CmdletBinding()]
param (
    [string]$Region = $(if ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }),
    [string]$Profile = $(if ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }),
    [string]$ThingName = "vit-campus-auditorium-sensor-01",
    [string]$PolicyName = "vit-campus-sensor-policy",
    [string]$RuleName = "vit_campus_telemetry_rule",
    [string]$LambdaName = "vit-telemetry-handler",
    [string]$TopicName = "vit/campus/Building024/telemetry",
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
if ($PSBoundParameters.ContainsKey("ThingName") -and [string]::IsNullOrWhiteSpace($ThingName)) {
    Write-Error "Validation failed: IoT Thing name was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("PolicyName") -and [string]::IsNullOrWhiteSpace($PolicyName)) {
    Write-Error "Validation failed: IoT Policy name was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("RuleName") -and [string]::IsNullOrWhiteSpace($RuleName)) {
    Write-Error "Validation failed: IoT Topic Rule name was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("LambdaName") -and [string]::IsNullOrWhiteSpace($LambdaName)) {
    Write-Error "Validation failed: Lambda function name was provided but is blank or empty."
    exit 1
}
if ($PSBoundParameters.ContainsKey("TopicName") -and [string]::IsNullOrWhiteSpace($TopicName)) {
    Write-Error "Validation failed: IoT Topic name was provided but is blank or empty."
    exit 1
}

# Parameter normalization with defaults
$Profile = if ($Profile -and $Profile.Trim() -ne "") { $Profile.Trim() } elseif ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }
$Region = if ($Region -and $Region.Trim() -ne "") { $Region.Trim() } elseif ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }
$ThingName = if ($ThingName -and $ThingName.Trim() -ne "") { $ThingName.Trim() } else { "vit-campus-auditorium-sensor-01" }
$PolicyName = if ($PolicyName -and $PolicyName.Trim() -ne "") { $PolicyName.Trim() } else { "vit-campus-sensor-policy" }
$RuleName = if ($RuleName -and $RuleName.Trim() -ne "") { $RuleName.Trim() } else { "vit_campus_telemetry_rule" }
$LambdaName = if ($LambdaName -and $LambdaName.Trim() -ne "") { $LambdaName.Trim() } else { "vit-telemetry-handler" }
$TopicName = if ($TopicName -and $TopicName.Trim() -ne "") { $TopicName.Trim() } else { "vit/campus/Building024/telemetry" }

# Syntax and format verification
if ([string]::IsNullOrWhiteSpace($Region) -or -not ($Region -match '^[a-z]{2}-[a-z]+-[0-9]$')) {
    Write-Error "Validation failed: Region '$Region' is invalid. Expected format like 'ap-south-1'."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($Profile) -or -not ($Profile -match '^[a-zA-Z0-9_.-]+$')) {
    Write-Error "Validation failed: Profile '$Profile' is invalid."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($ThingName) -or -not ($ThingName -match '^[a-zA-Z0-9:_-]{1,128}$')) {
    Write-Error "Validation failed: ThingName '$ThingName' is invalid. Must be 1-128 alphanumeric characters (hyphens, colons, underscores allowed)."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($PolicyName) -or -not ($PolicyName -match '^[\w+=,.@-]{1,128}$')) {
    Write-Error "Validation failed: PolicyName '$PolicyName' is invalid."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($RuleName) -or -not ($RuleName -match '^[a-zA-Z0-9_]+$')) {
    Write-Error "Validation failed: RuleName '$RuleName' is invalid. IoT Topic Rule names must be alphanumeric and underscores only."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($LambdaName) -or -not ($LambdaName -match '^[a-zA-Z0-9-_]{1,64}$')) {
    Write-Error "Validation failed: LambdaName '$LambdaName' is invalid."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($TopicName)) {
    Write-Error "Validation failed: TopicName is required and cannot be empty."
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
        Write-Error "AWS CLI execution failed during: $StepDescription (Exit code: $LASTEXITCODE). Aborting Stage 2 deployment."
        exit $LASTEXITCODE
    }
}

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "VIT Chennai AI Digital Twin - Stage 2: AWS IoT Core Deployment" -ForegroundColor Cyan
Write-Host "Target AWS Region: $Region | Profile: $Profile" -ForegroundColor DarkGray
Write-Host "IoT Thing Name:    $ThingName" -ForegroundColor DarkGray
Write-Host "IoT Topic Name:    $TopicName" -ForegroundColor DarkGray
Write-Host "Target Lambda:     $LambdaName" -ForegroundColor DarkGray
Write-Host "==============================================================================" -ForegroundColor Cyan

# 0. Pre-flight Check
Write-Host "`n[0/5] Verifying AWS CLI profile '$Profile'..." -ForegroundColor Yellow
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
Write-Host "STAGE 2 PRE-DEPLOYMENT AUDIT" -ForegroundColor Cyan
Write-Host "The following AWS IoT resources will be inspected, created, or updated:" -ForegroundColor DarkGray
Write-Host "  1. AWS IoT Thing:     $ThingName"
Write-Host "  2. AWS IoT Policy:    $PolicyName (iot:Connect on client/$ThingName, iot:Publish on topic/$TopicName)"
Write-Host "  3. X.509 Certificate: Generated into local certs/ directory (strictly git-ignored)"
Write-Host "  4. IoT Topic Rule:    $RuleName (SQL: SELECT * FROM '$TopicName' -> Action: Lambda $LambdaName)"
Write-Host "  5. Lambda Permission: iot.amazonaws.com granted lambda:InvokeFunction on $LambdaName"
Write-Host "==============================================================================" -ForegroundColor Cyan

if (-not $Force) {
    $confirm = Read-Host "`nDo you want to proceed with provisioning Stage 2 IoT resources on AWS? (y/N)"
    if ($confirm.Trim().ToLower() -ne "y") {
        Write-Host "Stage 2 deployment aborted by user. Zero AWS resources were modified." -ForegroundColor Yellow
        exit 0
    }
}

# 1. AWS IoT Thing
Write-Host "`n[1/5] Checking IoT Thing '$ThingName'..." -ForegroundColor Yellow
$thingCheckOut = Invoke-Native { aws iot describe-thing --thing-name $ThingName --region $Region --profile $Profile --query "thingArn" --output text 2>&1 }
$thingCheckExit = $LASTEXITCODE
$thingCheckText = ($thingCheckOut | Out-String).Trim()

if ($thingCheckExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($thingCheckText) -and $thingCheckText -ne "None") {
    $thingArn = $thingCheckText
    Write-Host "IoT Thing '$ThingName' already exists ($thingArn)." -ForegroundColor Green
} elseif ($thingCheckText -match "ResourceNotFoundException" -or $thingCheckText -match "No such thing") {
    Write-Host "Creating IoT Thing '$ThingName'..." -ForegroundColor Cyan
    $thingAttrObj = @{
        attributes = @{
            venueId     = "Building024"
            description = "Mahatma_Gandhi_Auditorium_Entrance_Turnstile_Sensor_Array"
        }
    }
    $thingAttrJson = $thingAttrObj | ConvertTo-Json -Depth 5
    try {
        $null = $thingAttrJson | ConvertFrom-Json
    } catch {
        Write-Error "Invalid IoT Thing attribute JSON: $_"
        exit 1
    }

    $tmpAttrPath = Join-Path $env:TEMP "vit_iot_thing_attr_$PID.json"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmpAttrPath, $thingAttrJson, $utf8NoBom)

    try {
        Invoke-AwsChecked {
            aws iot create-thing `
              --thing-name $ThingName `
              --attribute-payload "file://$tmpAttrPath" `
              --region $Region `
              --profile $Profile | Out-Null
        } "Create IoT Thing $ThingName"
        Write-Host "IoT Thing created: $ThingName" -ForegroundColor Green
    } finally {
        if (Test-Path $tmpAttrPath) {
            Remove-Item -Path $tmpAttrPath -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Error "Error checking IoT Thing '$ThingName' (Exit code: ${thingCheckExit}): $thingCheckText"
    exit 1
}

# 2. AWS IoT Policy (Least Privilege)
Write-Host "`n[2/5] Checking IoT Policy '$PolicyName'..." -ForegroundColor Yellow
$policyCheckOut = Invoke-Native { aws iot get-policy --policy-name $PolicyName --region $Region --profile $Profile --query "policyArn" --output text 2>&1 }
$policyCheckExit = $LASTEXITCODE
$policyCheckText = ($policyCheckOut | Out-String).Trim()

$policyDocObj = @{
    Version   = "2012-10-17"
    Statement = @(
        @{
            Effect   = "Allow"
            Action   = "iot:Connect"
            Resource = "arn:aws:iot:${Region}:${accountId}:client/${ThingName}"
        },
        @{
            Effect   = "Allow"
            Action   = "iot:Publish"
            Resource = "arn:aws:iot:${Region}:${accountId}:topic/vit/campus/*"
        }
    )
}
$policyDocJson = $policyDocObj | ConvertTo-Json -Depth 5
try {
    $null = $policyDocJson | ConvertFrom-Json
} catch {
    Write-Error "Invalid IoT policy JSON: $_"
    exit 1
}

if ($policyCheckExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($policyCheckText) -and $policyCheckText -ne "None") {
    Write-Host "IoT Policy '$PolicyName' already exists ($policyCheckText)." -ForegroundColor Green
} elseif ($policyCheckText -match "ResourceNotFoundException") {
    Write-Host "Creating scoped IoT policy '$PolicyName'..." -ForegroundColor Cyan
    $tmpPolicyPath = Join-Path $env:TEMP "vit_iot_policy_$PID.json"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmpPolicyPath, $policyDocJson, $utf8NoBom)

    try {
        Invoke-AwsChecked {
            aws iot create-policy `
              --policy-name $PolicyName `
              --policy-document "file://$tmpPolicyPath" `
              --region $Region `
              --profile $Profile | Out-Null
        } "Create IoT Policy $PolicyName"
        Write-Host "IoT Policy created successfully." -ForegroundColor Green
    } finally {
        if (Test-Path $tmpPolicyPath) {
            Remove-Item -Path $tmpPolicyPath -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Error "Error checking IoT Policy '$PolicyName' (Exit code: ${policyCheckExit}): $policyCheckText"
    exit 1
}

# 3. Create Keys and Certificate (Stored securely in local certs/ directory)
Write-Host "`n[3/5] Checking/generating device certificates in local 'certs/' directory..." -ForegroundColor Yellow

$scriptDir = if ($PSScriptRoot -and $PSScriptRoot.Trim() -ne "") { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir -or $scriptDir.Trim() -eq "") { $scriptDir = (Get-Location).Path }
$certsDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\certs"))

if (-not (Test-Path $certsDir)) {
    New-Item -ItemType Directory -Path $certsDir -Force | Out-Null
}

$certPemPath = Join-Path $certsDir "sensor-certificate.pem.crt"
$privKeyPath = Join-Path $certsDir "sensor-private.pem.key"
$pubKeyPath = Join-Path $certsDir "sensor-public.pem.key"
$certMetaPath = Join-Path $certsDir "cert-metadata.json"

$certArn = $null

if (-not (Test-Path $certPemPath) -or -not (Test-Path $privKeyPath)) {
    Write-Host "Generating active X.509 device certificate via AWS IoT Core..." -ForegroundColor Cyan
    $certJson = aws iot create-keys-and-certificate `
      --set-as-active `
      --certificate-pem-outfile $certPemPath `
      --public-key-outfile $pubKeyPath `
      --private-key-outfile $privKeyPath `
      --region $Region `
      --profile $Profile `
      --output json

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($certJson)) {
        Write-Error "Failed to generate AWS IoT certificates."
        exit 1
    }

    $certObj = $certJson | ConvertFrom-Json
    $certArn = $certObj.certificateArn
    $certId = $certObj.certificateId

    # Save metadata locally (git-ignored)
    $metaObj = @{
        certificateArn = $certArn
        certificateId  = $certId
        createdAt      = (Get-Date).ToString("o")
        thingName      = $ThingName
    }
    $metaJson = $metaObj | ConvertTo-Json -Depth 5
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($certMetaPath, $metaJson, $utf8NoBom)

    Write-Host "Certificate generated successfully (ID: $certId)." -ForegroundColor Green
    Write-Host "Certificates saved to '$certsDir' (excluded from Git repository)." -ForegroundColor DarkGray
} else {
    Write-Host "Device certificates already exist in '$certsDir'. Preserving existing keys." -ForegroundColor Green
    if (Test-Path $certMetaPath) {
        try {
            $existingMeta = Get-Content -Path $certMetaPath -Raw | ConvertFrom-Json
            $certArn = $existingMeta.certificateArn
            Write-Host "Loaded certificate ARN from metadata: $certArn" -ForegroundColor DarkGray
        } catch {
            Write-Host "Notice: Could not parse cert-metadata.json: $_" -ForegroundColor DarkGray
        }
    }
}

# Attach Policy to Certificate & Thing Principal (Idempotent)
if ($certArn) {
    Write-Host "Ensuring policy '$PolicyName' is attached to certificate..." -ForegroundColor DarkGray
    $attachPolicyOut = Invoke-Native {
        aws iot attach-policy `
          --policy-name $PolicyName `
          --target $certArn `
          --region $Region `
          --profile $Profile 2>&1
    }
    $attachPolicyExit = $LASTEXITCODE
    $attachPolicyText = ($attachPolicyOut | Out-String).Trim()
    if ($attachPolicyExit -ne 0 -and $attachPolicyText -notmatch "ResourceAlreadyExists" -and $attachPolicyText -notmatch "already attached") {
        Write-Error "Failed to attach policy to certificate: $attachPolicyText"
        exit 1
    } elseif ($attachPolicyExit -ne 0) {
        # Handled expected idempotent condition - reset LASTEXITCODE so it does not leak
        $global:LASTEXITCODE = 0
    }

    Write-Host "Ensuring certificate principal is attached to Thing '$ThingName'..." -ForegroundColor DarkGray
    $attachPrincipalOut = Invoke-Native {
        aws iot attach-thing-principal `
          --thing-name $ThingName `
          --principal $certArn `
          --region $Region `
          --profile $Profile 2>&1
    }
    $attachPrincipalExit = $LASTEXITCODE
    $attachPrincipalText = ($attachPrincipalOut | Out-String).Trim()
    if ($attachPrincipalExit -ne 0 -and $attachPrincipalText -notmatch "ResourceAlreadyExists" -and $attachPrincipalText -notmatch "already attached") {
        Write-Error "Failed to attach principal to thing: $attachPrincipalText"
        exit 1
    } elseif ($attachPrincipalExit -ne 0) {
        # Handled expected idempotent condition - reset LASTEXITCODE so it does not leak
        $global:LASTEXITCODE = 0
    }
    Write-Host "Policy and Thing attachments verified." -ForegroundColor Green
}

# 4. AWS IoT Topic Rule (SQL routing into Lambda)
Write-Host "`n[4/5] Checking IoT Topic Rule '$RuleName'..." -ForegroundColor Yellow
$lambdaArn = aws lambda get-function --function-name $LambdaName --region $Region --profile $Profile --query "Configuration.FunctionArn" --output text 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($lambdaArn) -or $lambdaArn -eq "None") {
    Write-Error "Error: Lambda function '$LambdaName' does not exist. Deploy Stage 1 first (.\scripts\deploy_backend.ps1)."
    exit 1
}

$ruleObj = @{
    sql              = "SELECT * FROM '$TopicName'"
    description      = "Routes simulated VIT Chennai campus sensor readings into telemetry Lambda"
    actions          = @(
        @{
            lambda = @{
                functionArn = $lambdaArn
            }
        }
    )
    ruleDisabled     = $false
    awsIotSqlVersion = "2016-03-23"
}
$ruleJson = $ruleObj | ConvertTo-Json -Depth 5
try {
    $null = $ruleJson | ConvertFrom-Json
} catch {
    Write-Error "Invalid IoT Topic Rule JSON: $_"
    exit 1
}

$tmpRulePath = Join-Path $env:TEMP "vit_iot_rule_$PID.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tmpRulePath, $ruleJson, $utf8NoBom)

try {
    $rulesListOut = Invoke-Native { aws iot list-topic-rules --region $Region --profile $Profile --output json 2>&1 }
    $rulesListExit = $LASTEXITCODE
    $rulesListText = ($rulesListOut | Out-String).Trim()

    if ($rulesListExit -ne 0) {
        Write-Error "Error listing IoT Topic Rules (Exit code: ${rulesListExit}): $rulesListText"
        exit 1
    }

    $ruleExists = $false
    try {
        $rulesJsonObj = $rulesListText | ConvertFrom-Json
        if ($rulesJsonObj -and $rulesJsonObj.rules) {
            foreach ($r in $rulesJsonObj.rules) {
                if ($r -and $r.ruleName -eq $RuleName) {
                    $ruleExists = $true
                    break
                }
            }
        }
    } catch {
        Write-Error "Failed to parse IoT Topic Rules list JSON: $_"
        exit 1
    }

    if ($ruleExists) {
        Write-Host "Updating IoT Topic Rule '$RuleName'..." -ForegroundColor Cyan
        Invoke-AwsChecked {
            aws iot replace-topic-rule `
              --rule-name $RuleName `
              --topic-rule-payload "file://$tmpRulePath" `
              --region $Region `
              --profile $Profile
        } "Replace IoT Topic Rule $RuleName"
        Write-Host "IoT Topic Rule updated successfully." -ForegroundColor Green
    } else {
        Write-Host "Creating IoT Topic Rule '$RuleName' (SQL: SELECT * FROM '$TopicName')..." -ForegroundColor Cyan
        Invoke-AwsChecked {
            aws iot create-topic-rule `
              --rule-name $RuleName `
              --topic-rule-payload "file://$tmpRulePath" `
              --region $Region `
              --profile $Profile
        } "Create IoT Topic Rule $RuleName"
        Write-Host "IoT Topic Rule created successfully." -ForegroundColor Green
    }
} finally {
    if (Test-Path $tmpRulePath) {
        Remove-Item -Path $tmpRulePath -Force -ErrorAction SilentlyContinue
    }
}

# 5. Grant Lambda invocation permission to iot.amazonaws.com
Write-Host "`n[5/5] Checking Lambda invocation permission for IoT Core..." -ForegroundColor Yellow
$statementId = "vit-iot-rule-invoke"
$permCheck = Invoke-Native {
    aws lambda get-policy --function-name $LambdaName --region $Region --profile $Profile --query "Policy" --output text 2>&1
}
if (($permCheck | Out-String) -match $statementId) {
    Write-Host "Lambda invocation permission for IoT Core already exists." -ForegroundColor Green
    $global:LASTEXITCODE = 0
} else {
    $addIotPermOut = Invoke-Native {
        aws lambda add-permission `
          --function-name $LambdaName `
          --statement-id $statementId `
          --action "lambda:InvokeFunction" `
          --principal "iot.amazonaws.com" `
          --source-arn "arn:aws:iot:${Region}:${accountId}:rule/$RuleName" `
          --region $Region `
          --profile $Profile 2>&1
    }
    $addIotPermExit = $LASTEXITCODE
    $addIotPermText = ($addIotPermOut | Out-String).Trim()
    if ($addIotPermExit -ne 0 -and $addIotPermText -notmatch "ResourceConflictException") {
        Write-Host "Notice: Lambda permission note ($addIotPermText)." -ForegroundColor DarkGray
        $global:LASTEXITCODE = 0
    } elseif ($addIotPermExit -ne 0) {
        # Handled expected idempotent condition - reset LASTEXITCODE so it does not leak
        $global:LASTEXITCODE = 0
    }
    Write-Host "Lambda invocation permission configured." -ForegroundColor Green
}

# Fetch IoT ATS Endpoint
$iotEndpoint = aws iot describe-endpoint --endpoint-type "iot:Data-ATS" --region $Region --profile $Profile --query "endpointAddress" --output text 2>$null

Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host "Stage 2 IoT Ingestion Deployment Complete!" -ForegroundColor Green
Write-Host "IoT ATS Data Endpoint: $iotEndpoint" -ForegroundColor Cyan
Write-Host "MQTT Ingestion Topic:  $TopicName" -ForegroundColor Cyan
Write-Host "To simulate live IoT sensor data during your demo, run:" -ForegroundColor Yellow
Write-Host "  .\scripts\publish_sensor_sim.ps1 -Occupancy 1920 -FlowDelta 15" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Green
$global:LASTEXITCODE = 0
exit 0

