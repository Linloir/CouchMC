#!/usr/bin/env bash
# Build MC Controller and install it into /Applications.
#
# Why this script exists: launching the app directly from
# `mac/build/Debug/McController.app` works for code iteration but
# the menu-bar status item gets misplaced by macOS's layout engine
# (e.g. behind the MBP-14 notch, or at off-screen X coordinates),
# because ad-hoc-signed apps in user / DerivedData paths aren't
# treated like proper installed apps by `ControlCenter` (Sequoia+)
# / `SystemUIServer` (older). Moving the bundle to `/Applications`
# and re-registering with LaunchServices fixes the placement.
#
# **What this script does NOT do**:
#   • It does NOT touch ControlCenter, SystemUIServer, Dock, or
#     Finder via launchctl / killall. An earlier revision did, on
#     the theory that restarting those would force a fresh menu
#     bar layout — empirically that caused at least one full
#     system-UI lockup that only a reboot fixed. An app must never
#     restart system-owned launchd services.
#   • It does NOT clear icon caches in /private/var/folders or
#     ~/Library/Caches that would need sudo.
#
# If you've already run the app from the build directory and macOS
# is showing a stale icon in the Dock / Accessibility list, the
# safest reset is: log out + back in (or reboot). Toggling the
# Accessibility switch off + on for MC Controller forces TCC to
# re-issue trust for the new binary's cdhash.
#
# Usage:
#     bash scripts/install.sh             # Debug build
#     bash scripts/install.sh release     # Release build

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

SOURCE_APP="${PROJECT_ROOT}/build/${CONFIG}/McController.app"
TARGET_APP="/Applications/McController.app"
BUNDLE_ID="cn.linloir.couchmc.mac"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

echo "→ Building (${CONFIG})..."
bash "${SCRIPT_DIR}/build.sh" "${CONFIG}" > /dev/null

if [ ! -d "${SOURCE_APP}" ]; then
    echo "✗ Build output not found at ${SOURCE_APP}" >&2
    exit 1
fi

# Stop the previous instance (if any) so we can replace its bundle.
# This only kills the McController process — never anything else.
echo "→ Stopping any running MC Controller instance..."
pkill -f "McController.app/Contents/MacOS/McController" 2>/dev/null || true
sleep 1

# Wipe the previous /Applications copy and install fresh.
echo "→ Copying to ${TARGET_APP}..."
rm -rf "${TARGET_APP}"
cp -R "${SOURCE_APP}" "${TARGET_APP}"

# Find and unregister every LaunchServices entry for our bundle ID
# *except* the canonical /Applications copy. Without this, macOS may
# still associate the app with an old build-directory path.
echo "→ Re-registering with LaunchServices..."
mdfind "kMDItemCFBundleIdentifier == ${BUNDLE_ID}" 2>/dev/null \
    | while IFS= read -r path; do
    if [ "${path}" != "${TARGET_APP}" ] && [ -n "${path}" ]; then
        "${LSREGISTER}" -u "${path}" 2>/dev/null || true
    fi
done
"${LSREGISTER}" -f "${TARGET_APP}"

# Bump file mtime so IconServicesAgent picks up new icon bytes —
# macOS's icon cache is keyed in part by bundle path + mtime.
# Touch-only, no service restart.
touch "${TARGET_APP}"
touch "${TARGET_APP}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
touch "${TARGET_APP}/Contents/Resources/Assets.car" 2>/dev/null || true

echo "→ Launching..."
open "${TARGET_APP}"

echo
echo "✅ Installed at ${TARGET_APP}"
echo
echo "  • If the Dock / Settings still shows the old icon, that's"
echo "    macOS's icon cache catching up — log out + back in (or"
echo "    drag the app out of /Applications then back in) to force"
echo "    a refresh."
echo "  • If a menu-bar manager (Hidden Bar / Bartender) is hiding"
echo "    the status icon, whitelist MC Controller in its preferences."
