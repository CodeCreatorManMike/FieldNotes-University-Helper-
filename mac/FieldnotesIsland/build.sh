#!/bin/bash
# Builds the release binary and prints its absolute path, for pasting into
# com.fieldnotes.island.plist or running directly.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
echo "Built: $(pwd)/.build/release/FieldnotesIsland"
