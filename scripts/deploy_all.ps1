# ==============================================================================
# VIT Chennai Campus AI Digital Twin - Master AWS Pipeline Orchestrator (PowerShell)
# ==============================================================================
# Course: Cloud Architecture Design (CAD)
# Target Region: ap-south-1
# AWS CLI Profile: vit-deploy
# Live Frontend: https://d457w1fwy7gg.cloudfront.net
#
# Usage Options:
#   1. Preflight Check Only (Read-Only, Zero AWS Mutations):
#      .\scripts\deploy_all.ps1 -Preflight
#
#   2. Individual Stage Deployments:
#      .\scripts\deploy_all.ps1 -Stage1           # Deploy DynamoDB + Lambda + API Gateway
#      .\scripts\deploy_all.ps1 -Stage2           # Deploy AWS IoT Core + Topic Rule + Certs
#      .\scripts\deploy_all.ps1 -Stage3           # Deploy CloudWatch Alarms & Dashboard
#      .\scripts\deploy_all.ps1 -DeployFrontend   # Build Vite app & deploy to S3/CloudFront
#
#   3. Full Automated Pipeline (Stage 1 -> Stage 2 -> Stage 3 -> Frontend):
#      .\scripts\deploy_all.ps1 -All
# ==============================================================================

[CmdletBinding()]
param (
    [switch]$Preflight,
    [switch]$Stage1,
    [switch]$Stage2,
    [switch]$Stage3,
    [switch]$DeployFrontend,
    [switch]$All,
    [string]$Region = $(if ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }),
    [string]$Profile = $(if ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }),
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$Profile = $Profile.Trim()
$Region = $Region.Trim()

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

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "VIT Chennai AI Digital Twin - Master AWS Pipeline Orchestrator" -ForegroundColor Cyan
Write-Host "AWS Region:  $Region | Profile: $Profile" -ForegroundColor DarkGray
Write-Host "Live Domain: https://d457w1fwy7gg.cloudfront.net" -ForegroundColor DarkGray
Write-Host "==============================================================================" -ForegroundColor Cyan

function Run-PreflightCheck {
    Write-Host "`n>>> RUNNING PRE-FLIGHT AUDIT (Read-Only Mode, Zero AWS Mutations) <<<" -ForegroundColor Yellow

    # 1. Check local environment files
    Write-Host "[1/5] Checking local repository files..." -ForegroundColor Yellow
    $criticalFiles = @(
        "index.html",
        "package.json",
        "src/main.js",
        "src/twinSimulation.js",
        "src/scene.js",
        "backend/lambda/index.js",
        "backend/lambda/package.json",
        "public/vit_map.glb",
        "public/waypoints.json",
        "public/buildingEntrances.json",
        "public/config.json",
        "scripts/deploy_backend.ps1",
        "scripts/deploy_stage2.ps1",
        "scripts/deploy_stage3.ps1",
        "scripts/deploy_s3_cloudfront.ps1"
    )

    $missingFiles = @()
    foreach ($file in $criticalFiles) {
        $path = Join-Path $PSScriptRoot "..\$file"
        if (-not (Test-Path $path)) {
            $missingFiles += $file
        }
    }

    if ($missingFiles.Count -gt 0) {
        Write-Error "Pre-flight failed: Missing critical files: $($missingFiles -join ', ')"
        return $false
    }
    Write-Host "All critical project files verified present." -ForegroundColor Green

    # 2. Check Node.js and npm
    Write-Host "[2/5] Checking Node.js and build tooling..." -ForegroundColor Yellow
    $nodeVer = node -v 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($nodeVer)) {
        Write-Error "Pre-flight failed: Node.js is not found in PATH."
        return $false
    }
    Write-Host "Node.js detected: $nodeVer (Required: >= 20.0)" -ForegroundColor Green

    # 3. Check AWS CLI installation
    Write-Host "[3/5] Checking AWS CLI installation..." -ForegroundColor Yellow
    $awsVer = aws --version 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($awsVer)) {
        Write-Error "Pre-flight failed: AWS CLI is not installed or not in PATH."
        return $false
    }
    Write-Host "AWS CLI detected: $awsVer" -ForegroundColor Green

    # 4. Check AWS CLI Authentication & Credentials
    Write-Host "[4/5] Checking AWS CLI profile '$Profile' connectivity..." -ForegroundColor Yellow
    $callerJson = Invoke-Native { aws sts get-caller-identity --profile $Profile --output json 2>$null }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($callerJson)) {
        Write-Host "Warning: AWS CLI profile '$Profile' could not authenticate." -ForegroundColor Yellow
        Write-Host "Please run 'aws configure --profile $Profile' or export AWS_PROFILE before executing mutating stages." -ForegroundColor DarkGray
        return $false
    }
    $callerObj = $callerJson | ConvertFrom-Json
    Write-Host "AWS Profile Authenticated: $($callerObj.Arn)" -ForegroundColor Green
    Write-Host "Target AWS Account:        $($callerObj.Account)" -ForegroundColor DarkGray

    # 5. Check CloudFront distribution configuration
    Write-Host "[5/5] Inspecting CloudFront distribution 'E2NGCY20SE2WWQ'..." -ForegroundColor Yellow
    $distStatus = Invoke-Native { aws cloudfront get-distribution --id "E2NGCY20SE2WWQ" --profile $Profile --query "Distribution.Status" --output text 2>$null }
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($distStatus)) {
        Write-Host "CloudFront distribution status: $distStatus" -ForegroundColor Green
    } else {
        Write-Host "CloudFront distribution check skipped or requires active credentials." -ForegroundColor DarkGray
    }

    Write-Host "`n>>> PRE-FLIGHT AUDIT PASSED: Environment is ready for deployment. <<<" -ForegroundColor Green
    return $true
}

# If only preflight requested, run and exit
if ($Preflight) {
    $ok = Run-PreflightCheck
    exit $(if ($ok) { 0 } else { 1 })
}

# If no specific switches passed, default to -All
$executeAll = $All -or (-not $Stage1 -and -not $Stage2 -and -not $Stage3 -and -not $DeployFrontend)

# Step 0: Always run preflight before mutating stages
$preflightPassed = Run-PreflightCheck
if (-not $preflightPassed) {
    Write-Error "Pre-flight checks failed. Aborting deployment pipeline."
    exit 1
}

# Stage 1: Telemetry API
if ($executeAll -or $Stage1) {
    Write-Host "`n==============================================================================" -ForegroundColor Cyan
    Write-Host "PIPELINE STEP: STAGE 1 (Telemetry API: DynamoDB + Lambda + API Gateway)" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
    $stage1Script = Join-Path $PSScriptRoot "deploy_backend.ps1"
    $params = @{
        Region     = $Region
        Profile    = $Profile
        TableName  = "vit-campus-telemetry"
        LambdaName = "vit-telemetry-handler"
        RoleName   = "vit-telemetry-lambda-role"
        ApiName    = "vit-telemetry-api"
    }
    if ($Force) { $params.Force = $true }
    & $stage1Script @params
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Stage 1 deployment failed (Exit code: $LASTEXITCODE). Pipeline stopped."
        exit $LASTEXITCODE
    }
}

# Stage 2: AWS IoT Core Ingestion
if ($executeAll -or $Stage2) {
    Write-Host "`n==============================================================================" -ForegroundColor Cyan
    Write-Host "PIPELINE STEP: STAGE 2 (AWS IoT Core Ingestion & MQTT Rule)" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
    $stage2Script = Join-Path $PSScriptRoot "deploy_stage2.ps1"
    $params = @{
        Region     = $Region
        Profile    = $Profile
        ThingName  = "vit-campus-auditorium-sensor-01"
        PolicyName = "vit-campus-sensor-policy"
        RuleName   = "vit_campus_telemetry_rule"
        LambdaName = "vit-telemetry-handler"
        TopicName  = "vit/campus/Building024/telemetry"
    }
    if ($Force) { $params.Force = $true }
    & $stage2Script @params
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Stage 2 deployment failed (Exit code: $LASTEXITCODE). Pipeline stopped."
        exit $LASTEXITCODE
    }
}

# Stage 3: Monitoring & Observability
if ($executeAll -or $Stage3) {
    Write-Host "`n==============================================================================" -ForegroundColor Cyan
    Write-Host "PIPELINE STEP: STAGE 3 (CloudWatch Alarms & Observability Dashboard)" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
    $stage3Script = Join-Path $PSScriptRoot "deploy_stage3.ps1"
    $params = @{
        Region        = $Region
        Profile       = $Profile
        LambdaName    = "vit-telemetry-handler"
        TableName     = "vit-campus-telemetry"
        DashboardName = "vit-campus-digital-twin-dashboard"
    }
    if ($Force) { $params.Force = $true }
    & $stage3Script @params
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Stage 3 deployment failed (Exit code: $LASTEXITCODE). Pipeline stopped."
        exit $LASTEXITCODE
    }
}

# Frontend Build & CloudFront Deployment
if ($executeAll -or $DeployFrontend) {
    Write-Host "`n==============================================================================" -ForegroundColor Cyan
    Write-Host "PIPELINE STEP: FRONTEND DEPLOYMENT (Vite Build + S3 + CloudFront Invalidation)" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
    $frontendScript = Join-Path $PSScriptRoot "deploy_s3_cloudfront.ps1"
    $frontendParams = @{
        Region         = $Region
        Profile        = $Profile
        Bucket         = "vit-chennai-digital-twin-672791231004"
        DistributionId = "E2NGCY20SE2WWQ"
    }
    & $frontendScript @frontendParams
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Frontend deployment failed (Exit code: $LASTEXITCODE). Pipeline stopped."
        exit $LASTEXITCODE
    }
}

Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host "ALL REQUESTED PIPELINE STAGES DEPLOYED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "Live CloudFront Digital Twin: https://d457w1fwy7gg.cloudfront.net" -ForegroundColor Cyan
Write-Host "To test live IoT sensor publication during your demo:" -ForegroundColor Yellow
Write-Host "  .\scripts\publish_sensor_sim.ps1 -Occupancy 1950 -FlowDelta 20" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Green

