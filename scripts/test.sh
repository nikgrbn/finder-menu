#!/bin/bash
# Builds and runs the tests in Tests/ against the code they cover.
# Usage: scripts/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Not Sources/FinderMenu/*.swift: main.swift starts the app, and Tests/main.swift is the entry point here.
xcrun swiftc -swift-version 5 -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macos13.0" \
  -module-name FinderMenuTests -framework Cocoa \
  Tests/*.swift Sources/Shared/*.swift Sources/FinderMenu/Paths.swift Sources/FinderMenu/Terminals.swift \
  -o "$WORK/tests"
"$WORK/tests"
