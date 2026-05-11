#!/usr/bin/env bash
# Downloads the Android platform-tools bundle and extracts the `adb`
# binary into `mac/McController/Resources/adb/`. The Xcode build phase
# (or `build.sh`) copies the folder into the app bundle's Resources, so
# the bundled adb is available at
#     McController.app/Contents/Resources/adb/adb
# without the user having to install Android SDK separately.
#
# Re-run if Google ships a new platform-tools release. The bundle is
# pinned by date so a regression in a future adb release can't
# spontaneously break things.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"
TARGET_DIR="${PROJECT_ROOT}/McController/Resources/adb"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

URL="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"

echo "→ Downloading platform-tools from ${URL}"
curl -fL -o "${TMP_DIR}/platform-tools.zip" "${URL}"

echo "→ Extracting"
unzip -q "${TMP_DIR}/platform-tools.zip" -d "${TMP_DIR}"

mkdir -p "${TARGET_DIR}"
# adb depends on the bundled OpenSSL + libraries that ship next to it.
# Copy the whole platform-tools tree but trim everything we don't need
# at runtime (no fastboot, mkbootimg, etc.).
cp -R "${TMP_DIR}/platform-tools/adb" "${TARGET_DIR}/adb"
chmod +x "${TARGET_DIR}/adb"

# adb on macOS only needs the `adb` binary itself — the dylibs are
# resolved via @rpath from the system. If we discover otherwise we'll
# also copy the supporting *.dylib files here.

ARCH="$(uname -m)"
echo "✅ Bundled adb at ${TARGET_DIR}/adb (${ARCH})"
"${TARGET_DIR}/adb" version | head -1
