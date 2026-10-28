#!/usr/bin/env bash
# ==============================================================================
# VIT Chennai Campus AI Digital Twin - AWS S3 & CloudFront Deployment Script (Bash)
# ==============================================================================
# Architecture: Private Amazon S3 Origin + CloudFront OAC + Global HTTPS CDN
# CloudFront URL: https://d457w1fwy7gg.cloudfront.net
#
# Pre-requisites:
# 1. AWS CLI installed and configured with profile (`--profile vit-deploy`).
# 2. Node.js & npm installed for automated Vite production build.
# 3. Target S3 Bucket and CloudFront Distribution configured with Origin Access Control (OAC).
#
# Usage (One-Command Deployment):
#   ./scripts/deploy_s3_cloudfront.sh
#
# Optional custom overrides:
#   S3_BUCKET="..." CLOUDFRONT_DISTRIBUTION_ID="..." AWS_PROFILE="..." ./scripts/deploy_s3_cloudfront.sh
# ==============================================================================

set -euo pipefail

BUCKET="${S3_BUCKET:-vit-chennai-digital-twin-672791231004}"
DISTRIBUTION_ID="${CLOUDFRONT_DISTRIBUTION_ID:-E2NGCY20SE2WWQ}"
REGION="${AWS_REGION:-ap-south-1}"
PROFILE="${AWS_PROFILE:-vit-deploy}"

echo "=============================================================================="
echo "VIT Chennai AI Digital Twin — Production S3 & CloudFront Deployment"
echo "Target S3 Bucket:  s3://${BUCKET}"
echo "CloudFront Dist:   ${DISTRIBUTION_ID}"
echo "AWS CLI Profile:   ${PROFILE} | Region: ${REGION}"
echo "=============================================================================="

# 0. Pre-flight Check: Verify AWS CLI profile credentials without exposing secrets
echo "Verifying AWS CLI profile '${PROFILE}'..."
CALLER_ARN=$(aws sts get-caller-identity --profile "${PROFILE}" --query "Arn" --output text)
if [ -z "${CALLER_ARN}" ]; then
  echo "Error: AWS CLI profile '${PROFILE}' is not available or authentication failed."
  exit 1
fi
echo "Authenticated as: ${CALLER_ARN}"

# 1. Build Vite application
echo ""
echo "[1/5] Building production bundle (npm run build)..."
npm run build

if [ ! -d "dist" ]; then
  echo "Error: dist/ directory not found after build."
  exit 1
fi

if [ ! -f "dist/vit_map.glb" ]; then
  echo "Error: dist/vit_map.glb not found. Ensure 3D asset is in public/ before building."
  exit 1
fi

# 2. Upload hashed static assets with 1-year immutable caching (CSS, JS)
echo ""
echo "[2/5] Uploading hashed static assets (dist/assets/)..."
aws s3 sync dist/assets/ "s3://${BUCKET}/assets/" \
  --profile "${PROFILE}" \
  --cache-control "public, max-age=31536000, immutable" \
  --delete

# 3. Upload unhashed JSON datasets with 1-day cache (excluding vit_map.glb to avoid redundant upload)
echo "[3/5] Uploading campus datasets (*.json)..."
aws s3 sync dist/ "s3://${BUCKET}/" \
  --profile "${PROFILE}" \
  --exclude "*" \
  --include "*.json" \
  --cache-control "public, max-age=86400, stale-while-revalidate=604800"

# 4. Upload 3D model once with explicit model/gltf-binary MIME type
echo "[4/5] Uploading 3D campus model (vit_map.glb) with model/gltf-binary Content-Type..."
aws s3 cp dist/vit_map.glb "s3://${BUCKET}/vit_map.glb" \
  --profile "${PROFILE}" \
  --content-type "model/gltf-binary" \
  --cache-control "public, max-age=86400, stale-while-revalidate=604800"

# 5. Upload index.html with no-cache so browsers always discover the latest asset hashes
echo "[5/5] Uploading index.html (entrypoint with no-cache)..."
aws s3 cp dist/index.html "s3://${BUCKET}/index.html" \
  --profile "${PROFILE}" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "no-cache, no-store, must-revalidate"

# 6. Invalidate CloudFront edge cache to immediately distribute updates
echo ""
echo "Creating CloudFront cache invalidation for distribution: ${DISTRIBUTION_ID}..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "${DISTRIBUTION_ID}" \
  --paths "/*" \
  --profile "${PROFILE}" \
  --query "Invalidation.Id" \
  --output text)

echo "CloudFront invalidation created successfully: ${INVALIDATION_ID}"

DOMAIN=$(aws cloudfront get-distribution --id "${DISTRIBUTION_ID}" --profile "${PROFILE}" --query "Distribution.DomainName" --output text 2>/dev/null || echo "d457w1fwy7gg.cloudfront.net")

echo ""
echo "=============================================================================="
echo "Deployment complete! Live HTTPS Digital Twin:"
echo "https://${DOMAIN}"
echo "=============================================================================="
