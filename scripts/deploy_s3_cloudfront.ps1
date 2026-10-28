# ==============================================================================
# VIT Chennai Campus AI Digital Twin - AWS S3 and CloudFront Deployment Script (PowerShell)
# ==============================================================================
# Architecture: Private Amazon S3 Origin + CloudFront OAC + Global HTTPS CDN
# CloudFront URL: https://d457w1fwy7gg.cloudfront.net
#
# Pre-requisites:
# 1. AWS CLI installed and configured with profile (`--profile vit-deploy`).
# 2. Node.js and npm installed for automated Vite production build.
# 3. Target S3 Bucket and CloudFront Distribution configured with Origin Access Control (OAC).
#
# Usage (One-Command Deployment):
#   .\scripts\deploy_s3_cloudfront.ps1
#
# Optional custom overrides:
#   .\scripts\deploy_s3_cloudfront.ps1 -Profile "vit-deploy" -Bucket "vit-chennai-digital-twin-672791231004" -DistributionId "E2NGCY20SE2WWQ"
# ==============================================================================

[CmdletBinding()]
param (
    [string]$Bucket = $(if ($env:S3_BUCKET -and $env:S3_BUCKET.Trim() -ne "") { $env:S3_BUCKET.Trim() } else { "vit-chennai-digital-twin-672791231004" }),
    [string]$DistributionId = $(if ($env:CLOUDFRONT_DISTRIBUTION_ID -and $env:CLOUDFRONT_DISTRIBUTION_ID.Trim() -ne "") { $env:CLOUDFRONT_DISTRIBUTION_ID.Trim() } else { "E2NGCY20SE2WWQ" }),
    [string]$Region = $(if ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }),
    [string]$Profile = $(if ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }),
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$Bucket = $Bucket.Trim()
if (-not ($Bucket -match '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$')) {
    Write-Error "Error: Bucket name '$Bucket' is invalid. S3 bucket names must be lowercase letters, numbers, or hyphens (3-63 chars)."
    exit 1
}

$DistributionId = $DistributionId.Trim()
if (-not ($DistributionId -match '^[A-Z0-9]+$')) {
    Write-Error "Error: CloudFront distribution ID '$DistributionId' is invalid. Must be alphanumeric uppercase (e.g. E2NGCY20SE2WWQ)."
    exit 1
}

$Profile = $Profile.Trim()
$Region = $Region.Trim()

# Helper to execute AWS CLI commands and ensure non-zero exit codes immediately abort
function Invoke-AwsCommand {
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
Write-Host "VIT Chennai AI Digital Twin - Production S3 and CloudFront Deployment" -ForegroundColor Cyan
Write-Host "Target S3 Bucket:  s3://$Bucket" -ForegroundColor DarkGray
Write-Host "CloudFront Dist:   $DistributionId" -ForegroundColor DarkGray
Write-Host "AWS CLI Profile:   $Profile | Region: $Region" -ForegroundColor DarkGray
Write-Host "==============================================================================" -ForegroundColor Cyan

# 0. Pre-flight Check: Verify AWS CLI profile credentials without exposing secrets
Write-Host "Verifying AWS CLI profile '$Profile'..." -ForegroundColor Yellow
$callerArn = aws sts get-caller-identity --profile $Profile --query "Arn" --output text
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($callerArn)) {
    Write-Error "Error: AWS CLI profile '$Profile' is not available or authentication failed. Check 'aws configure --profile $Profile'."
    exit 1
}
Write-Host "Authenticated as: $callerArn" -ForegroundColor Green

# 1. Build Vite application
if (-not $SkipBuild) {
    Write-Host "`n[1/5] Building production bundle (npm run build)..." -ForegroundColor Yellow
    npm run build
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Vite build failed (npm run build exited with code $LASTEXITCODE). Aborting deployment."
        exit $LASTEXITCODE
    }
} else {
    Write-Host "`n[1/5] Skipping build (-SkipBuild specified)..." -ForegroundColor DarkGray
}

if (-not (Test-Path "dist")) {
    Write-Error "Error: dist/ directory not found after build. Please run 'npm run build' first."
    exit 1
}

if (-not (Test-Path "dist/vit_map.glb")) {
    Write-Error "Error: dist/vit_map.glb not found. Ensure 3D asset is in public/ before building."
    exit 1
}

# 2. Upload hashed static assets with 1-year immutable caching (CSS, JS)
Write-Host "`n[2/5] Uploading hashed static assets (dist/assets/)..." -ForegroundColor Yellow
Invoke-AwsCommand {
    aws s3 sync dist/assets/ "s3://$Bucket/assets/" `
      --profile $Profile `
      --cache-control "public, max-age=31536000, immutable" `
      --delete
} "Upload hashed static assets (dist/assets/)"

# 3. Upload unhashed JSON datasets with 1-day cache (excluding vit_map.glb to prevent redundant upload)
Write-Host "[3/5] Uploading campus datasets (*.json)..." -ForegroundColor Yellow
Invoke-AwsCommand {
    aws s3 sync dist/ "s3://$Bucket/" `
      --profile $Profile `
      --exclude "*" `
      --include "*.json" `
      --cache-control "public, max-age=86400, stale-while-revalidate=604800"
} "Upload campus JSON datasets"

# 4. Upload 3D campus model once with explicit model/gltf-binary MIME type
Write-Host "[4/5] Uploading 3D campus model (vit_map.glb) with model/gltf-binary Content-Type..." -ForegroundColor Yellow
Invoke-AwsCommand {
    aws s3 cp dist/vit_map.glb "s3://$Bucket/vit_map.glb" `
      --profile $Profile `
      --content-type "model/gltf-binary" `
      --cache-control "public, max-age=86400, stale-while-revalidate=604800"
} "Upload 3D model vit_map.glb"

# 5. Upload index.html with no-cache so browsers always discover the latest asset hashes
Write-Host "[5/5] Uploading index.html (entrypoint with no-cache)..." -ForegroundColor Yellow
Invoke-AwsCommand {
    aws s3 cp dist/index.html "s3://$Bucket/index.html" `
      --profile $Profile `
      --content-type "text/html; charset=utf-8" `
      --cache-control "no-cache, no-store, must-revalidate"
} "Upload index.html entrypoint"

# 6. Invalidate CloudFront edge cache to immediately distribute updates
Write-Host "`nCreating CloudFront cache invalidation for distribution: $DistributionId..." -ForegroundColor Cyan
$invalidationId = aws cloudfront create-invalidation `
  --distribution-id $DistributionId `
  --paths "/*" `
  --profile $Profile `
  --query "Invalidation.Id" `
  --output text

if ($LASTEXITCODE -ne 0) {
    Write-Error "CloudFront cache invalidation failed (Exit code: $LASTEXITCODE)."
    exit $LASTEXITCODE
}

Write-Host "CloudFront invalidation created successfully: $invalidationId" -ForegroundColor Green

$domain = aws cloudfront get-distribution --id $DistributionId --profile $Profile --query "Distribution.DomainName" --output text
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($domain)) {
    $domain = "d457w1fwy7gg.cloudfront.net"
}

Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host "Deployment complete! Live HTTPS Digital Twin:" -ForegroundColor Green
Write-Host "https://$domain" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Green
