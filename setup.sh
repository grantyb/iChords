#!/bin/bash
set -e

cd "$(dirname "$0")"

# Install xcodegen if not present
if ! command -v xcodegen &> /dev/null; then
    echo "Installing XcodeGen..."
    brew install xcodegen
fi

# Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "Done! Opening iChords.xcodeproj..."
echo ""
echo "Next steps:"
echo "  1. Select your Development Team in Signing & Capabilities"
echo "  2. Connect your iPhone"
echo "  3. Select your device as the run destination"
echo "  4. Press Cmd+R to build and run"
echo ""

open iChords.xcodeproj
