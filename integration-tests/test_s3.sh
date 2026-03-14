#!/bin/bash
set -e

echo "🚀 Starting s3ninja..."
docker compose -f docker-compose.test.yml up -d s3ninja

echo "⏳ Waiting for s3ninja to be ready..."
sleep 3

echo "🧪 Running S3 tests..."
mix test --only s3 "$@"

echo "✅ Tests complete!"
