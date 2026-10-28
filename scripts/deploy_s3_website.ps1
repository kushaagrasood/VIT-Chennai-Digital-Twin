# ==============================================================================
# VIT Chennai Campus AI Digital Twin - S3 Static Website Deployment Script (PowerShell)
# ==============================================================================
# Architecture: Direct S3 Static Website Hosting (HTTP demo endpoint)
# S3 Website URL: http://<bucket-name>.s3-website.<region>.amazonaws.com
#
# Pre-requisites:
# 1. AWS CLI installed with profile configured (`--profile vit-deploy`).
# 2. S3 bucket configured with Static Website Hosting enabled and public read policy applied.
# 3. Production build created via `npm run build`.
#
# Usage:
#   .\scripts\deploy_s3_website.ps1
#   # Or with custom parameters:
#   .\scripts\deploy_s3_website.ps1 -Bucket "vit-chennai-digital-twin-672791231004" -Region "ap-south-1" -Profile "vit-deploy"
# ==============================================================================

[CmdletBinding()]
param (
    [string]$Bucket = $(if ($env:S3_BUCKET -and $env:S3_BUCKET.Trim() -ne "") { $env:S3_BUCKET.Trim() } else { "vit-chennai-digital-twin-672791231004" }),
    [string]$Region = $(if ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }),
    [string]$Profile = $(if ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" })
)

$ErrorActionPreference = "Stop"

$Bucket = $Bucket.Trim()
if (-not ($Bucket -match '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$')) {
    Write-Error "Error: Bucket name '$Bucket' is invalid. S3 bucket names must be lowercase letters, numbers, or hyphens (3-63 chars)."
    exit 1
}

$Profile = $Profile.Trim()
$Region = $Region.Trim()

if (-not (Test-Path "dist")) {
    Write-Error "Error: dist/ directory not found. Please run 'npm run build' first."
    exit 1
}

if (-not (Test-Path "dist/vit_map.glb")) {
    Write-Error "Error: dist/vit_map.glb not found. Ensure 3D asset is in public/ before building."
    exit 1
}

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

Write-Host "Deploying VIT Chennai Digital Twin to S3 Static Website: s3://$Bucket..." -ForegroundColor Cyan
Write-Host "Using AWS CLI Profile: $Profile | Region: $Region" -ForegroundColor DarkGray

# 1. Upload hashed assets with 1-year immutable caching (CSS, JS)
Write-Host "[1/4] Uploading hashed static assets (dist/assets/)..." -ForegroundColor Yellow
Invoke-AwsCommand {
    aws s3 sync dist/assets/ "s3://$Bucket/assets/" `
      --profile $Profile `
      --cache-control "public, max-age=31536000, immutable" `
      --delete
} "Upload hashed static assets (dist/assets/)"

# 2. Upload unhashed JSON datasets with 1-day cache (excluding vit_map.glb to avoid redundant upload)
Write-Host "[2/4] Uploading campus datasets (*.json)..." -ForegroundColor Yellow
Invoke-AwsCommand {
    aws s3 sync dist/ "s3://$Bucket/" `
      --profile $Profile `
      --exclude "*" `
      --include "*.json" `
      --cache-control "public, max-age=86400, stale-while-revalidate=604800"
} "Upload campus JSON datasets"

# 3. Upload the 20.3MB glTF binary model once with explicit model/gltf-binary MIME type
Write-Host "[3/4] Uploading 3D campus model with model/gltf-binary Content-Type..." -ForegroundColor Yellow
Invoke-AwsCommand {
    aws s3 cp dist/vit_map.glb "s3://$Bucket/vit_map.glb" `
      --profile $Profile `
      --content-type "model/gltf-binary" `
      --cache-control "public, max-age=86400, stale-while-revalidate=604800"
} "Upload 3D model vit_map.glb"

# 4. Upload index.html with no-cache so browsers always discover the latest asset hashes
Write-Host "[4/4] Uploading index.html (entrypoint with no-cache)..." -ForegroundColor Yellow
Invoke-AwsCommand {
    aws s3 cp dist/index.html "s3://$Bucket/index.html" `
      --profile $Profile `
      --content-type "text/html; charset=utf-8" `
      --cache-control "no-cache, no-store, must-revalidate"
} "Upload index.html entrypoint"

$websiteUrl = "http://$Bucket.s3-website.$Region.amazonaws.com"
Write-Host "`nDeployment complete!" -ForegroundColor Green
Write-Host "S3 Static Website URL: $websiteUrl" -ForegroundColor Cyan
Write-Host "Note: S3 Website endpoints serve over HTTP (not HTTPS)." -ForegroundColor Yellow
