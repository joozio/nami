#!/bin/bash
# Run Nami window manager

set -e

cd "$(dirname "$0")"

# Kill any existing instances
pkill -f "Nami$" 2>/dev/null || true

# Build
echo "Building Nami..."
swift build

# Run
echo "Starting Nami..."
.build/debug/Nami
