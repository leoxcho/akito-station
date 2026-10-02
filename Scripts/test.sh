#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/akito-station-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/akito-station-swift-cache"
[ "${AKITO_EDITION:-public}" = public ] || { echo "This sanitized tree tests Public only" >&2; exit 2; }
export AKITO_EDITION=public
swift test --disable-sandbox --build-system native --scratch-path "${AKITO_STATION_BUILD_DIR:-/tmp/akito-station-$AKITO_EDITION-build}"
