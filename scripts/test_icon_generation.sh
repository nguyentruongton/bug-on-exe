#!/usr/bin/env bash
set -euo pipefail

test -f "dist/AppIcon.iconset/icon_512x512@2x.png"
test -f "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json"
test -f "Resources/AppIcon-Preview.png"

# Verify 1024x1024 dimensions on highest-res icon
DIM=$(sips -g pixelWidth dist/AppIcon.iconset/icon_512x512@2x.png | awk '/pixelWidth/ {print $2}')
[ "$DIM" -eq 1024 ]
echo "PASS: Icon generation outputs validated."
