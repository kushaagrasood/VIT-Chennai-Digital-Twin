#!/usr/bin/env bash
# ==============================================================================
# VIT Chennai Campus AI Digital Twin - AWS S3 & CloudFront Deployment Script
# ==============================================================================
# Pre-requisites:
# 1. AWS CLI installed and configured with appropriate IAM credentials (s3:PutObject, cloudfront:CreateInvalidation).
# 2. Production build created via `npm run build`.
# 3. Target S3 Bucket and CloudFront Distribution created with Origin Access Control (OAC).
#
# Usage:
#   export S3_BUCKET="your-bucket-name"
#   export CLOUDFRONT_DISTRIBUTION_ID="E1234567EXAMPLE"
#   ./scripts/deploy_s3_cloudfront.sh
# ==============================================================================

set -euo pipefail

# 1. Validate environment configuration
if [ -z "${S3_BUCKET:-}" ]; then
  echo "Error: S3_BUCKET environment variable is not set."
  echo "Example: export S3_BUCKET=\"vit-chennai-digital-twin-web\""
  exit 1
fi

if [ -z "${CLOUDFRONT_DISTRIBUTION_ID:-}" ]; then
  echo "Error: CLOUDFRONT_DISTRIBUTION_ID environment variable is not set."
  echo "Example: export CLOUDFRONT_DISTRIBUTION_ID=\"E1234567EXAMPLE\""
  exit 1
fi

# 2. Verify dist/ build directory exists
if [ ! -d "dist" ]; then
  echo "Error: dist/ directory not found. Run 'npm run build' first."
  exit 1
fi

if [ ! -f "dist/vit_map.glb" ]; then
  echo "Error: dist/vit_map.glb not found. Ensure 3D asset is in public/ before building."
  exit 1
fi

echo "Deploying VIT Chennai Digital Twin to S3 bucket: s3://${S3_BUCKET}..."

# 3. Upload hashed assets with 1-year immutable caching (CSS, JS)
echo "[1/4] Uploading hashed static assets (dist/assets/)..."
aws s3 sync dist/assets/ "s3://${S3_BUCKET}/assets/" \
  --cache-control "public, max-age=31536000, immutable" \
  --delete

# 4. Upload unhashed 3D model and JSON datasets with 1-day cache
echo "[2/4] Uploading campus datasets and 3D model..."
aws s3 sync dist/ "s3://${S3_BUCKET}/" \
  --exclude "index.html" \
  --exclude "assets/*" \
  --cache-control "public, max-age=86400, stale-while-revalidate=604800"

# Explicitly ensure correct MIME type for the 20.3MB glTF binary model
echo "[3/4] Ensuring model/gltf-binary Content-Type on vit_map.glb..."
aws s3 cp dist/vit_map.glb "s3://${S3_BUCKET}/vit_map.glb" \
  --content-type "model/gltf-binary" \
  --cache-control "public, max-age=86400, stale-while-revalidate=604800"

# 5. Upload index.html with no-cache so browsers always discover the latest asset hashes
echo "[4/4] Uploading index.html (entrypoint with no-cache)..."
aws s3 cp dist/index.html "s3://${S3_BUCKET}/index.html" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "no-cache, no-store, must-revalidate"

# 6. Invalidate CloudFront edge cache to immediately distribute updates
echo "Creating CloudFront cache invalidation for distribution: ${CLOUDFRONT_DISTRIBUTION_ID}..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "${CLOUDFRONT_DISTRIBUTION_ID}" \
  --paths "/*" \
  --query "Invalidation.Id" \
  --output text)

echo "CloudFront invalidation created successfully: ${INVALIDATION_ID}"
echo "Deployment complete! Visit: https://$(aws cloudfront get-distribution --id "${CLOUDFRONT_DISTRIBUTION_ID}" --query "Distribution.DomainName" --output text)"

