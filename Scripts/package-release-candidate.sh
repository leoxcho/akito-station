#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Scripts/verify-public-release.py
if rg -q "Status: BLOCKED" Documentation/LICENSE_REPORT.md; then
  echo "Release archive blocked by Documentation/LICENSE_REPORT.md" >&2
  exit 1
fi
mkdir -p Build
ARCHIVE="$PWD/Build/Akito-Station-1.0.1-macOS-arm64.zip"
ditto -c -k --norsrc --noextattr --keepParent "Build/Akito Station.app" "$ARCHIVE"
echo "$ARCHIVE"
