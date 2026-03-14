#!/bin/bash
set -e

echo "🧪 Running FileSystem tests..."
mix test --only file_system "$@"

echo "✅ Tests complete!"
