#!/bin/bash
set -e

echo "Starting Azurite..."
docker compose -f docker-compose.test.yml up -d azurite

echo "Waiting for Azurite to be ready..."
sleep 2

echo "Running Azure tests..."
mix test --only azure "$@"

echo "Tests complete!"