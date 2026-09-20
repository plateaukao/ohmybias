#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# UI-only files to exclude
EXCLUDE="CandidatePanel|ModeToast|AppDelegate|OhMyBiasInputController|DebugLog"

SOURCES=$(find Sources Sources/Shared -maxdepth 1 -name '*.swift' | grep -Ev "$EXCLUDE" | sort -u)
TEST_SOURCES=$(find Tests -name '*.swift' | sort)

echo "Compiling test runner..."
xcrun --sdk macosx swiftc \
    -module-name OhMyBiasTests \
    -target arm64-apple-macos14.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework Foundation \
    -framework AppKit \
    -framework Cocoa \
    -lsqlite3 \
    -O \
    -o /tmp/ohmybias_tests \
    $SOURCES $TEST_SOURCES 2>&1

echo "Running tests..."
/tmp/ohmybias_tests
