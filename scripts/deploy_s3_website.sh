#!/usr/bin/env bash
# ==============================================================================
# VIT Chennai Campus AI Digital Twin - S3 Static Website Deployment Script (Bash)
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
#   ./scripts/deploy_s3_website.sh
#   # Or with custom environment variables:
#   S3_BUCKET="vit-chennai-digital-twin-672791231004" AWS_REGION="ap-south-1" AWS_PROFILE="vit-deploy" ./scripts/deploy_s3_website.sh
# ==============================================================================

set -euo pipefail

BUCKET="${S3_BUCKET:-vit-chennai-digital-twin-672791231004}"
REGION="${AWS_REGION:-ap-south-1}"
PROFILE="${AWS_PROFILE:-vit-deploy}"

if [ ! -d "dist" ]; then
  echo "Error: dist/ directory not found. Run 'npm run build' first."
  exit 1
fi

if [ ! -f "dist/vit_map.glb" ]; then
  echo "Error: dist/vit_map.glb not found. Ensure 3D asset is in public/ before building."
  exit 1
fi

echo "Deploying VIT Chennai Digital Twin to S3 Static Website: s3://${BUCKET}..."
echo "Using AWS CLI Profile: ${PROFILE} | Region: ${REGION}"

# 1. Upload hashed assets with 1-year immutable caching (CSS, JS)
echo "[1/4] Uploading hashed static assets (dist/assets/)..."
aws s3 sync dist/assets/ "s3://${BUCKET}/assets/" \
  --profile "${PROFILE}" \
  --cache-control "public, max-age=31536000, immutable" \
  --delete

# 2. Upload unhashed JSON datasets with 1-day cache (excluding vit_map.glb to avoid redundant upload)
echo "[2/4] Uploading campus datasets (*.json)..."
aws s3 sync dist/ "s3://${BUCKET}/" \
  --profile "${PROFILE}" \
  --exclude "*" \
  --include "*.json" \
  --cache-control "public, max-age=86400, stale-while-revalidate=604800"

# 3. Upload 3D model once with explicit model/gltf-binary MIME type
echo "[3/4] Uploading 3D campus model with model/gltf-binary Content-Type..."
aws s3 cp dist/vit_map.glb "s3://${BUCKET}/vit_map.glb" \
  --profile "${PROFILE}" \
  --content-type "model/gltf-binary" \
  --cache-control "public, max-age=86400, stale-while-revalidate=604800"

# 4. Upload index.html with no-cache so browsers always discover the latest asset hashes
echo "[4/4] Uploading index.html (entrypoint with no-cache)..."
aws s3 cp dist/index.html "s3://${BUCKET}/index.html" \
  --profile "${PROFILE}" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "no-cache, no-store, must-revalidate"

WEBSITE_URL="http://${BUCKET}.s3-website.${REGION}.amazonaws.com"
echo ""
echo "Deployment complete!"
echo "S3 Static Website URL: ${WEBSITE_URL}"
echo "Note: S3 Website endpoints serve over HTTP (not HTTPS)."

