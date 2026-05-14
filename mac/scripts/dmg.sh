#!/usr/bin/env bash
# Build a Release `.app` and package it as a polished, drag-to-install
# `.dmg` with a custom background, window size, and icon layout.
#
# Three signing tiers, picked automatically based on what the host has:
#
#   1. ad-hoc            — no Developer ID Application cert installed.
#                          Works immediately, no Apple-side setup. Users
#                          will see "macOS cannot verify the developer"
#                          on first launch and need Right-click → Open.
#
#   2. Developer ID      — `Developer ID Application: …` cert found in
#                          the keychain. Same Gatekeeper warning as #1
#                          unless you also notarize (#3).
#
#   3. Notarized         — pass `--notarize` AND have a notarytool
#                          credentials profile stored in the keychain
#                          under `--keychain-profile NAME` (defaults to
#                          `couchmc-notary`). Setup:
#
#                              xcrun notarytool store-credentials \
#                                  couchmc-notary \
#                                  --apple-id YOUR_APPLE_ID \
#                                  --team-id 9886C6X23N \
#                                  --password APP_SPECIFIC_PASSWORD
#
#                          Generate the app-specific password at
#                          https://account.apple.com/account/manage
#                          → Sign-In and Security → App-Specific
#                          Passwords. The password is stored in the
#                          login keychain and only used by notarytool.
#
# Output: mac/dist/CouchMC-<version>-mac.dmg
#
# Usage:
#     bash scripts/dmg.sh                          # auto-pick signing tier
#     bash scripts/dmg.sh --notarize               # also notarize + staple
#     bash scripts/dmg.sh --notarize --keychain-profile myprofile

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"
cd "${PROJECT_ROOT}"

# --- arg parsing -------------------------------------------------------

NOTARIZE=0
KEYCHAIN_PROFILE="couchmc-notary"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --notarize) NOTARIZE=1; shift ;;
        --keychain-profile) KEYCHAIN_PROFILE="$2"; shift 2 ;;
        -h|--help)
            sed -n '1,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# --- pick a signing identity ------------------------------------------

DEV_ID_HASH=$(security find-identity -v -p codesigning \
    | awk '/Developer ID Application/ { print $2; exit }' || true)

if [[ -n "${DEV_ID_HASH}" ]]; then
    SIGN_ID="${DEV_ID_HASH}"
    SIGN_TIER="developer-id"
    DEV_ID_NAME=$(security find-identity -v -p codesigning \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }')
    echo "→ Found Developer ID cert: ${DEV_ID_NAME}"
else
    SIGN_ID="-"
    SIGN_TIER="ad-hoc"
    echo "→ No Developer ID Application cert in keychain — falling back to ad-hoc."
    echo "  Recipients will see a Gatekeeper warning on first launch."
fi

if [[ ${NOTARIZE} -eq 1 && "${SIGN_TIER}" != "developer-id" ]]; then
    echo "✗ --notarize requires a Developer ID Application cert; ad-hoc " \
         "binaries cannot be notarized." >&2
    exit 3
fi

# --- 1. Build a clean Release with the picked identity ----------------

echo "→ Building Release with identity: ${SIGN_ID}"

# We don't reuse build.sh because it forces ad-hoc signing. We invoke
# xcodebuild directly so the same build can be ad-hoc OR Developer ID,
# and pinned to release-grade flags either way.

# Make sure the pbxproj reflects the current source tree first.
swift "${SCRIPT_DIR}/gen-xcodeproj.swift" >/dev/null

BUILD_DIR="${PROJECT_ROOT}/build"
CONFIG_BUILD_DIR="${BUILD_DIR}/Release"
DERIVED="${BUILD_DIR}/DerivedData"
mkdir -p "${BUILD_DIR}"

# Common signing args. For Developer ID we also want hardened runtime
# (required for notarization); for ad-hoc it's optional but harmless.
XCODE_SIGN_ARGS=(
    "CODE_SIGN_IDENTITY=${SIGN_ID}"
    "CODE_SIGN_STYLE=Manual"
    "OTHER_CODE_SIGN_FLAGS=--timestamp --options runtime"
)

xcodebuild \
    -project McController.xcodeproj \
    -scheme McController \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED}" \
    CONFIGURATION_BUILD_DIR="${CONFIG_BUILD_DIR}" \
    "${XCODE_SIGN_ARGS[@]}" \
    build > "${BUILD_DIR}/last-dmg-build.log" 2>&1 || {
    echo "✗ Build failed. Last 60 lines:" >&2
    tail -60 "${BUILD_DIR}/last-dmg-build.log" >&2
    exit 1
}

APP_PATH="${CONFIG_BUILD_DIR}/CouchMC.app"
[[ -d "${APP_PATH}" ]] || { echo "✗ Missing ${APP_PATH}"; exit 1; }

# Splice in bundled adb (matches build.sh; xcodegen doesn't list it).
ADB_SOURCE="${PROJECT_ROOT}/McController/Resources/adb"
if [[ -d "${ADB_SOURCE}" ]]; then
    cp -R "${ADB_SOURCE}" "${APP_PATH}/Contents/Resources/"
    # Re-sign the .app because we added bytes to its bundle after the
    # initial xcodebuild signing. Without this, the signature is invalid
    # and Gatekeeper / notarytool both reject it.
    codesign --force --sign "${SIGN_ID}" \
        --timestamp --options runtime \
        --deep "${APP_PATH}" 2>/dev/null
fi

# Sanity-check the signature before we package.
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 \
    | sed 's/^/  /' || { echo "✗ codesign verify failed"; exit 1; }

# --- 2. Bake the DMG background image (idempotent) --------------------

DMG_ASSETS_DIR="${SCRIPT_DIR}/dmg-assets"
BACKGROUND_PNG="${DMG_ASSETS_DIR}/background.png"
BACKGROUND_PNG_2X="${DMG_ASSETS_DIR}/background@2x.png"

if [[ ! -f "${BACKGROUND_PNG}" || ! -f "${BACKGROUND_PNG_2X}" ]]; then
    echo "→ Baking DMG background"
    swift "${SCRIPT_DIR}/make-dmg-background.swift"
fi

# --- 3. Stage drag-to-install layout ----------------------------------

VERSION=$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" \
    "${APP_PATH}/Contents/Info.plist")
BUILD_NO=$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleVersion" \
    "${APP_PATH}/Contents/Info.plist")

DIST_DIR="${PROJECT_ROOT}/dist"
mkdir -p "${DIST_DIR}"

DMG_NAME="CouchMC-${VERSION}-mac.dmg"
DMG_OUT="${DIST_DIR}/${DMG_NAME}"
DMG_TEMP="${BUILD_DIR}/CouchMC-${VERSION}-rw.dmg"
DMG_STAGE="${BUILD_DIR}/dmg-stage"
VOL_NAME="CouchMC ${VERSION}"

echo "→ Staging ${DMG_STAGE}"
rm -rf "${DMG_STAGE}" "${DMG_OUT}" "${DMG_TEMP}"
mkdir -p "${DMG_STAGE}"
cp -R "${APP_PATH}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

# Hidden .background/ folder picked up by Finder when reading the
# `background picture` AppleScript property.
mkdir -p "${DMG_STAGE}/.background"
cp "${BACKGROUND_PNG}" "${DMG_STAGE}/.background/background.png"
# Bundle the @2x variant too — Finder's icon view will pick it up
# automatically on retina displays.
cp "${BACKGROUND_PNG_2X}" "${DMG_STAGE}/.background/background@2x.png"

# --- 4. Create a writable DMG, apply Finder window layout, freeze ----

# Size the writable DMG generously so AppleScript's icon-view tweaks
# never run into an out-of-space error mid-write. Final compressed
# DMG is ~10 MB regardless.
echo "→ Creating writable DMG (UDRW)"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${DMG_STAGE}" \
    -ov \
    -format UDRW \
    -fs HFS+ \
    -size 80m \
    "${DMG_TEMP}" >/dev/null

echo "→ Mounting + applying Finder layout"
DMG_DEV=$(hdiutil attach "${DMG_TEMP}" -readwrite -noverify -noautoopen \
    | awk 'NR==1 { print $1 }')
MOUNT_POINT="/Volumes/${VOL_NAME}"

# Wait for the volume to actually be mounted (hdiutil returns before
# Finder is ready).
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -d "${MOUNT_POINT}" ]] && break
    sleep 0.4
done
[[ -d "${MOUNT_POINT}" ]] || { echo "✗ Mount point ${MOUNT_POINT} never appeared"; exit 1; }

# Coordinates here MUST match `make-dmg-background.swift`'s
# `appIconCenter` and `dstIconCenter` — Finder positions icons by
# their centre, and the arrow on the background was drawn assuming
# these specific points.
APPLESCRIPT=$(cat <<APPLESCRIPT_EOF
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- {x1, y1, x2, y2} screen coordinates. Width 600, height 400
        -- excluding title bar; height ≈ 400 + 22 px chrome.
        set the bounds of container window to {200, 200, 800, 622}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png"
        set position of item "CouchMC.app" of container window to {165, 220}
        set position of item "Applications" of container window to {435, 220}
        -- Force Finder to flush the .DS_Store before we unmount. The
        -- close → open → update → long-delay → close dance is the
        -- create-dmg recipe. "update without registering applications"
        -- alone does NOT synchronously persist .DS_Store, and a 1-second
        -- delay races the async Finder writer on most machines. Without a
        -- persisted .DS_Store the resulting DMG opens with default view
        -- settings (no background, no icon positions).
        close
        open
        update without registering applications
        delay 5
        close
    end tell
end tell
APPLESCRIPT_EOF
)
osascript -e "${APPLESCRIPT}" || {
    echo "✗ osascript reported a failure while laying out the DMG window." >&2
    echo "  The DMG may build but open without background/icon positions." >&2
}

# Set the .app's permissions and ensure the symlink is correct
chmod -Rf go-w "${MOUNT_POINT}" 2>/dev/null || true

# CRITICAL: ejecting via Finder (not bash's `hdiutil detach`) is what
# actually persists .DS_Store. Finder writes .DS_Store through its own
# buffered IPC path; the kernel only sees a dentry-cache update, so a
# bash-level `sync` followed by `hdiutil detach` will appear to succeed
# while silently discarding the dirty pages — the unmounted DMG ends up
# missing .DS_Store entirely and Finder opens it with default view
# settings (no background, no icon layout). Telling Finder itself to
# eject forces it to flush its own caches before the volume goes away.
echo "→ Asking Finder to eject (flushes .DS_Store)"
osascript -e "tell application \"Finder\" to eject disk \"${VOL_NAME}\"" || true

# Wait for the volume to actually disappear from /Volumes.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    [[ -d "${MOUNT_POINT}" ]] || break
    sleep 0.4
done
if [[ -d "${MOUNT_POINT}" ]]; then
    echo "  Finder eject did not unmount — falling back to hdiutil detach" >&2
    hdiutil detach "${DMG_DEV}" -force >/dev/null 2>&1 || true
fi

# Diagnostic: re-mount the UDRW DMG read-only and confirm .DS_Store
# survived the unmount. Finder may still be holding the DMG handle for
# a moment after eject, so retry a few times. Non-fatal if it can't
# probe — we'll still build the DMG and the user can spot a missing
# background empirically.
DIAG_MOUNT="${BUILD_DIR}/diag-mount"
mkdir -p "${DIAG_MOUNT}"
DIAG_OK=0
for _ in 1 2 3 4 5; do
    if hdiutil attach "${DMG_TEMP}" -readonly -noverify -noautoopen \
        -mountpoint "${DIAG_MOUNT}" >/dev/null 2>&1; then
        DIAG_OK=1
        break
    fi
    sleep 1
done
if [[ ${DIAG_OK} -eq 1 ]]; then
    if [[ -f "${DIAG_MOUNT}/.DS_Store" ]]; then
        DS_SIZE=$(stat -f '%z' "${DIAG_MOUNT}/.DS_Store")
        echo "  .DS_Store persisted (${DS_SIZE} bytes)"
    else
        echo "  ⚠ .DS_Store NOT persisted to the UDRW DMG — the final DMG" >&2
        echo "    will open with default view settings (no background)." >&2
    fi
    hdiutil detach "${DIAG_MOUNT}" -quiet >/dev/null 2>&1 || true
else
    echo "  (skipped persisted-check: UDRW DMG still busy)"
fi
rmdir "${DIAG_MOUNT}" 2>/dev/null || true

# --- 5. Convert to compressed read-only DMG ---------------------------

echo "→ Compressing → ${DMG_OUT}"
hdiutil convert "${DMG_TEMP}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG_OUT}" \
    -ov >/dev/null
rm -f "${DMG_TEMP}"
rm -rf "${DMG_STAGE}"

# Sign the DMG itself when we have a real cert. Notarization requires
# this; ad-hoc tier skips it (signing a DMG with `-` is supported but
# adds no value).
if [[ "${SIGN_TIER}" == "developer-id" ]]; then
    echo "→ Signing DMG with ${DEV_ID_NAME}"
    codesign --force --sign "${SIGN_ID}" \
        --timestamp --options runtime \
        "${DMG_OUT}"
fi

# --- 6. Optional notarize + staple ------------------------------------

if [[ ${NOTARIZE} -eq 1 ]]; then
    echo "→ Submitting to Apple notarytool (profile: ${KEYCHAIN_PROFILE})..."
    echo "  This usually takes 1–15 minutes."
    xcrun notarytool submit "${DMG_OUT}" \
        --keychain-profile "${KEYCHAIN_PROFILE}" \
        --wait

    echo "→ Stapling notarization ticket onto DMG"
    xcrun stapler staple "${DMG_OUT}"

    echo "→ Verifying staple"
    xcrun stapler validate "${DMG_OUT}"
fi

# --- 7. Summary -------------------------------------------------------

DMG_SIZE=$(du -h "${DMG_OUT}" | cut -f1)
echo
echo "✅ ${DMG_NAME}"
echo "   Path:    ${DMG_OUT}"
echo "   Size:    ${DMG_SIZE}"
echo "   Version: ${VERSION} (${BUILD_NO})"
echo "   Tier:    ${SIGN_TIER}$( [[ ${NOTARIZE} -eq 1 ]] && echo " + notarized" )"

if [[ "${SIGN_TIER}" == "ad-hoc" ]]; then
    echo
    echo "  ⚠ Ad-hoc signed. First-launch UX:"
    echo "    Recipients must Right-click → Open the first time, then"
    echo "    confirm the Gatekeeper dialog. Subsequent launches behave"
    echo "    normally."
    echo
    echo "  To eliminate the warning, create a 'Developer ID Application'"
    echo "  certificate in Xcode:"
    echo "    Xcode → Settings → Accounts → (your team) → Manage"
    echo "    Certificates → + → Developer ID Application"
    echo "  then re-run this script and pass --notarize."
elif [[ ${NOTARIZE} -eq 0 ]]; then
    echo
    echo "  ⚠ Signed but not notarized. Gatekeeper will still warn on"
    echo "    first launch. Re-run with --notarize to remove the warning."
fi
