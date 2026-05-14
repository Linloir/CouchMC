#!/usr/bin/env bash
# Convenience wrapper around `xcodebuild` that produces a runnable
# `.app` bundle in `mac/build/`. Pass `release` as the first arg for an
# optimized build with `dwarf-with-dsym` debug info; default is Debug.
#
# This script does NOT sign for distribution. It uses the project's
# ad-hoc signing setting (`CODE_SIGN_IDENTITY = "-"`), which produces a
# bundle that Gatekeeper will refuse on first launch but
# Right-click → Open works to bypass.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"
cd "${PROJECT_ROOT}"

CONFIG="${1:-Debug}"
case "${CONFIG}" in
    debug|Debug) CONFIG="Debug" ;;
    release|Release) CONFIG="Release" ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac

BUILD_DIR="${PROJECT_ROOT}/build"
mkdir -p "${BUILD_DIR}"

# If the icons aren't baked, do it now — a fresh checkout starts with
# an empty `AppIcon.appiconset` and Xcode would crash.
if [ ! -f "${PROJECT_ROOT}/McController/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" ]; then
    echo "→ Baking icons (one-time)"
    swift "${SCRIPT_DIR}/bake-icon.swift"
fi

# Suggest fetching adb if it's missing — purely informational; the
# build still succeeds, the user just won't have USB auto-pairing.
if [ ! -x "${PROJECT_ROOT}/McController/Resources/adb/adb" ]; then
    echo "⚠ Bundled adb missing. Run: bash scripts/fetch-adb.sh"
fi

# Make sure the pbxproj reflects the current source tree (cheap, ~1s).
swift "${SCRIPT_DIR}/gen-xcodeproj.swift" >/dev/null

echo "→ xcodebuild ${CONFIG}"
xcodebuild \
    -project McController.xcodeproj \
    -scheme McController \
    -configuration "${CONFIG}" \
    -destination 'platform=macOS' \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    CONFIGURATION_BUILD_DIR="${BUILD_DIR}/${CONFIG}" \
    build | xcpretty 2>/dev/null || true

# Some setups don't have xcpretty installed; fall through to the raw
# output if the pipe broke or returned non-zero. We re-run silently
# either way so a missing xcpretty is non-fatal.
xcodebuild \
    -project McController.xcodeproj \
    -scheme McController \
    -configuration "${CONFIG}" \
    -destination 'platform=macOS' \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    CONFIGURATION_BUILD_DIR="${BUILD_DIR}/${CONFIG}" \
    build > "${BUILD_DIR}/last-build.log" 2>&1

APP_PATH="${BUILD_DIR}/${CONFIG}/CouchMC.app"
if [ ! -d "${APP_PATH}" ]; then
    echo "✗ Build failed. See ${BUILD_DIR}/last-build.log"
    tail -40 "${BUILD_DIR}/last-build.log" >&2
    exit 1
fi

# Copy the bundled adb into the .app's Resources directory. The
# Xcode pbxproj generator only registers Swift sources + the asset
# catalog; the adb tree (which `scripts/fetch-adb.sh` populates)
# isn't a build phase input, so we splice it in here after the
# Xcode build. The app reads it at runtime via
# `Bundle.main.url(forResource: "adb", ...)`.
ADB_SOURCE="${PROJECT_ROOT}/McController/Resources/adb"
if [ -d "${ADB_SOURCE}" ]; then
    cp -R "${ADB_SOURCE}" "${APP_PATH}/Contents/Resources/"
fi

echo "✅ Built ${APP_PATH}"
echo
echo "  Launch:   open '${APP_PATH}'"
echo "  Or:       '${APP_PATH}/Contents/MacOS/CouchMC'"
