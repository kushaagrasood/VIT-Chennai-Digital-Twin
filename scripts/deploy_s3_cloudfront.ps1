# ==============================================================================
# VIT Chennai Campus AI Digital Twin - AWS S3 & CloudFront Deployment Script (PowerShell)
# ==============================================================================
# Pre-requisites:
# 1. AWS CLI installed and configured (`aws configure`).
# 2. Production build created via `npm run build`.
# 3. Target S3 Bucket and CloudFront Distribution created with Origin Access Control (OAC).
#
# Usage:
#   $env:S3_BUCKET = "your-bucket-name"
#   $env:CLOUDFRONT_DISTRIBUTION_ID = "E1234567EXAMPLE"
#   .\scripts\deploy_s3_cloudfront.ps1
# ==============================================================================

[CmdletBinding()]
param (
    [string]$Bucket = $env:S3_BUCKET,
    [string]$DistributionId = $env:CLOUDFRONT_DISTRIBUTION_ID
)

$ErrorActionPreference = "Stop"

if (-not $Bucket) {
    Write-Error "Error: S3 bucket name not provided. Set `$env:S3_BUCKET or pass -Bucket <name>."
    exit 1
}

if (-not $DistributionId) {
    Write-Error "Error: CloudFront distribution ID not provided. Set `$env:CLOUDFRONT_DISTRIBUTION_ID or pass -DistributionId <id>."
    exit 1
}

if (-not (Test-Path "dist")) {
    Write-Error "Error: dist/ directory not found. Please run 'npm run build' first."
    exit 1
}

if (-not (Test-Path "dist/vit_map.glb")) {
    Write-Error "Error: dist/vit_map.glb not found. Ensure 3D asset is in public/ before building."
    exit 1
}

Write-Host "Deploying VIT Chennai Digital Twin to S3 bucket: s3://$Bucket..." -ForegroundColor Cyan

# 1. Upload hashed assets with 1-year immutable caching (CSS, JS)
Write-Host "[1/4] Uploading hashed static assets (dist/assets/)..." -ForegroundColor Yellow
aws s3 sync dist/assets/ "s3://$Bucket/assets/" `
  --cache-control "public, max-age=31536000, immutable" `
  --delete

# 2. Upload unhashed 3D model and JSON datasets with 1-day cache
Write-Host "[2/4] Uploading campus datasets and 3D model..." -ForegroundColor Yellow
aws s3 sync dist/ "s3://$Bucket/" `
  --exclude "index.html" `
  --exclude "assets/*" `
  --cache-control "public, max-age=86400, stale-while-revalidate=604800"

# 3. Explicitly ensure correct MIME type for the 20.3MB glTF binary model
Write-Host "[3/4] Ensuring model/gltf-binary Content-Type on vit_map.glb..." -ForegroundColor Yellow
aws s3 cp dist/vit_map.glb "s3://$Bucket/vit_map.glb" `
  --content-type "model/gltf-binary" `
  --cache-control "public, max-age=86400, stale-while-revalidate=604800"

# 4. Upload index.html with no-cache so browsers always discover the latest asset hashes
Write-Host "[4/4] Uploading index.html (entrypoint with no-cache)..." -ForegroundColor Yellow
aws s3 cp dist/index.html "s3://$Bucket/index.html" `
  --content-type "text/html; charset=utf-8" `
  --cache-control "no-cache, no-store, must-revalidate"

# 5. Invalidate CloudFront edge cache to immediately distribute updates
Write-Host "Creating CloudFront cache invalidation for distribution: $DistributionId..." -ForegroundColor Cyan
$invalidationId = aws cloudfront create-invalidation `
  --distribution-id $DistributionId `
  --paths "/*" `
  --query "Invalidation.Id" `
  --output text

Write-Host "CloudFront invalidation created successfully: $invalidationId" -ForegroundColor Green
$domain = aws cloudfront get-distribution --id $DistributionId --query "Distribution.DomainName" --output text
Write-Host "Deployment complete! Visit: https://$domain" -ForegroundColor Green

