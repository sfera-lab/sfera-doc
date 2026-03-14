#!/bin/bash
set -e

echo "🚀 Starting Redis..."
docker compose -f docker-compose.test.yml up -d redis

echo "⏳ Waiting for Redis to be ready..."
sleep 2

echo "🧪 Running Redis tests..."
mix test --only redis "$@"

echo "✅ Tests complete!"
