#!/usr/bin/env bash
#
# Builds the macOS release bundle: build, sign, package DMG, notarize, staple.
#
#     ./publish.sh              # unsigned / ad-hoc bundle (local packaging test)
#     ./publish.sh -Sign        # signed & notarized production release DMG
#     ./publish.sh -Sign --rehearsal-feed https://plantoir.app/updates/rehearsal-204/macos.xml
#                               # a DRESS-REHEARSAL build of the updater (#204):
#                               # its own feed, a "-rehearsal.<build>" version and
#                               # a REHEARSAL asset name, so it can never be cut
#
# Output lands in mac-app/dist/Plantoir-macOS.dmg with its SHA-256 printed for
# the release notes.
#
# The version comes from ONE place in mac-app:
# MARKETING_VERSION in project.yml (which matches <Version> in Plantoir.csproj).
#
# The BUILD number is derived here rather than stored anywhere, because its
# only job is to name BITS uniquely: two artifacts must never share a name,
# and a hand-maintained number is one somebody forgets. `git rev-list --count
# HEAD` rises with every commit, never resets, and carries across marketing
# versions forever — see "Build numbers" in RELEASING.md.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${HERE}"

SIGN=false
KEYCHAIN_PROFILE="${NOTARYTOOL_PROFILE:-notarytool-profile}"
IDENTITY=""
REHEARSAL_FEED=""
PRODUCTION_FEED="https://plantoir.app/updates/macos.xml"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -Sign|--sign|-s)
      SIGN=true
      shift
      ;;
    --identity)
      IDENTITY="$2"
      shift 2
      ;;
    --keychain-profile)
      KEYCHAIN_PROFILE="$2"
      shift 2
      ;;
    --rehearsal-feed)
      REHEARSAL_FEED="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: ./publish.sh [-Sign] [--identity <name>] [--keychain-profile <profile>] [--rehearsal-feed <url>]"
      exit 1
      ;;
  esac
done

echo "============================================================"
echo "  Plantoir macOS Release Packaging"
echo "============================================================"

# A rehearsal build (#204) may point only at a throwaway feed on plantoir.app,
# never the real one: a rehearsal that read the production feed would be
# offered teachers' real updates, and one on another host is a feed nobody
# checks. The dress rehearsal is RELEASING.md → "The dress rehearsal".
if [[ -n "${REHEARSAL_FEED}" ]]; then
  if [[ "${REHEARSAL_FEED}" != https://plantoir.app/updates/* ]] || [[ "${REHEARSAL_FEED}" == "${PRODUCTION_FEED}" ]]; then
    echo "❌ --rehearsal-feed must be a throwaway feed under https://plantoir.app/updates/, never ${PRODUCTION_FEED}."
    exit 1
  fi
  echo "🎭 REHEARSAL BUILD — feed ${REHEARSAL_FEED}. This DMG must never be attached to a release."
fi

# ---- Preflight ---------------------------------------------------------------
if [[ "${SIGN}" == true ]]; then
  echo "🔍 Preflighting code signing & notarization credentials..."

  # Auto-discover Developer ID Application certificate if not explicitly supplied
  if [[ -z "${IDENTITY}" ]]; then
    # Look for "Developer ID Application"
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
  fi

  if [[ -z "${IDENTITY}" ]]; then
    echo "❌ No 'Developer ID Application' certificate found in keychain."
    echo "   To fix: Download your Developer ID Application certificate from developer.apple.com"
    echo "   and double-click to install it in Keychain Access."
    echo "   (Found identities:)"
    security find-identity -v -p codesigning
    exit 1
  fi
  echo "✅ Signing identity: ${IDENTITY}"

  # Preflight notarytool credentials
  if ! xcrun notarytool history --keychain-profile "${KEYCHAIN_PROFILE}" >/dev/null 2>&1; then
    echo "⚠️  Could not validate notarytool keychain profile '${KEYCHAIN_PROFILE}'."
    echo "   To set up: xcrun notarytool store-credentials \"${KEYCHAIN_PROFILE}\" --apple-id <email> --team-id <team-id> --password <app-specific-password>"
    echo "   Continuing, but notarization step will fail if credentials are not configured."
  else
    echo "✅ Notarization keychain profile '${KEYCHAIN_PROFILE}' verified."
  fi
fi

# ---- 1. Fetch Engine ---------------------------------------------------------
echo ""
echo "📦 Step 1: Checking llama.cpp engine..."
./Vendor/fetch-llama.sh
# The updater (#204): `project.yml` embeds Vendor/Sparkle/Sparkle.framework,
# so it must be in place before step 2 generates the project. Its helpers are
# signed item by item in step 4 (release/sign-updater.sh).
echo "📦 Checking Sparkle (the updater)..."
./Vendor/fetch-sparkle.sh

# ---- 2. Generate Xcode Project -----------------------------------------------
echo ""
echo "⚙️  Step 2: Generating Xcode project..."
xcodegen generate

# ---- 3. Build Release --------------------------------------------------------
echo ""
echo "🔨 Step 3: Building Release configuration..."
BUILD_DIR="${HERE}/build"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# The build number, derived from history rather than stored. A tree with no
# git (a downloaded tarball, say) still builds — it just gets 0, which is
# the same placeholder project.yml carries for local builds.
BUILD_NUMBER="$(git -C "${HERE}" rev-list --count HEAD 2>/dev/null || echo 0)"
echo "   - Build number: ${BUILD_NUMBER} (git rev-list --count HEAD)"

EXTRA_SETTINGS=()
EXPECTED_FEED="${PRODUCTION_FEED}"
if [[ -n "${REHEARSAL_FEED}" ]]; then
  MARKETING="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -n 1)"
  EXTRA_SETTINGS+=("PLANTOIR_UPDATE_FEED_URL=${REHEARSAL_FEED}" "MARKETING_VERSION=${MARKETING}-rehearsal.${BUILD_NUMBER}")
  EXPECTED_FEED="${REHEARSAL_FEED}"
fi

xcodebuild -project Plantoir.xcodeproj \
  -scheme Plantoir \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  ENABLE_HARDENED_RUNTIME=YES \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  ${EXTRA_SETTINGS[@]+"${EXTRA_SETTINGS[@]}"} \
  build

APP_SOURCE="${BUILD_DIR}/DerivedData/Build/Products/Release/Plantoir.app"
if [[ ! -d "${APP_SOURCE}" ]]; then
  echo "❌ Build output not found at ${APP_SOURCE}"
  exit 1
fi

STAGE_APP="${BUILD_DIR}/Plantoir.app"
rm -rf "${STAGE_APP}"
cp -a "${APP_SOURCE}" "${STAGE_APP}"

# A Release that lost its update feed, or carries the wrong key, ships an app
# that never offers an update and says nothing (#204). Asked of the BUILT
# bundle, in every mode.
./release/check-update-keys.sh "${STAGE_APP}" "${EXPECTED_FEED}"

# ---- 4. Code Signing ---------------------------------------------------------
if [[ "${SIGN}" == true ]]; then
  echo ""
  echo "✍️  Step 4: Bottom-up Code Signing with Hardened Runtime..."
  ENTITLEMENTS="${HERE}/QuartzTeachers/QuartzTeachers.entitlements"

  # The updater's own code FIRST, item by item, framework last (#204): Xcode's
  # Code Sign On Copy re-signs only the framework's top level, and its helpers
  # arrive ad-hoc. Never --deep; never the app's entitlements on them.
  ./release/sign-updater.sh "${STAGE_APP}" "${IDENTITY}"

  # Sign all real .dylib files inside the bundle (skip symlinks)
  echo "   - Signing dynamic libraries..."
  find "${STAGE_APP}/Contents" -type f -name "*.dylib" | while read -r dylib; do
    codesign --force --timestamp --options runtime --sign "${IDENTITY}" "${dylib}"
  done

  # Sign llama-server executable
  LLAMA_SERVER="${STAGE_APP}/Contents/Resources/llama/llama-server"
  if [[ -f "${LLAMA_SERVER}" ]]; then
    echo "   - Signing llama-server..."
    codesign --force --timestamp --options runtime --sign "${IDENTITY}" "${LLAMA_SERVER}"
  fi

  # Sign main application bundle
  echo "   - Signing Plantoir.app with entitlements..."
  codesign --force --timestamp --options runtime --entitlements "${ENTITLEMENTS}" --sign "${IDENTITY}" "${STAGE_APP}"

  # Verify bundle signature
  codesign --verify --deep --strict --verbose=2 "${STAGE_APP}"
  # …which cannot see an updater helper left on another team (measured for
  # #204). This can, and refuses BEFORE a five-minute notarization round trip.
  ./release/check-signatures.sh "${STAGE_APP}"
  echo "✅ Application bundle signed and verified."
else
  echo ""
  echo "⚠️  Step 4: Skipping code signing (-Sign not given) - for local testing only."
fi

# ---- 5. Package DMG ----------------------------------------------------------
echo ""
echo "💿 Step 5: Packaging Drag-and-Drop DMG..."
DIST_DIR="${HERE}/dist"
mkdir -p "${DIST_DIR}"
DMG_PATH="${DIST_DIR}/Plantoir-macOS.dmg"
if [[ -n "${REHEARSAL_FEED}" ]]; then
  # A name the cut-release skill refuses to attach (it takes only the frozen
  # asset names), so a rehearsal DMG can never reach a teacher by mistake.
  DMG_PATH="${DIST_DIR}/Plantoir-macOS-REHEARSAL.dmg"
fi
rm -f "${DMG_PATH}"

DMG_STAGE="${BUILD_DIR}/dmg_staging"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"

cp -a "${STAGE_APP}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

if command -v create-dmg >/dev/null 2>&1; then
  echo "   Using create-dmg for styled disk image layout..."
  create-dmg \
    --volname "Plantoir" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "Plantoir.app" 150 175 \
    --app-drop-link 450 175 \
    --no-internet-enable \
    "${DMG_PATH}" \
    "${DMG_STAGE}" || {
      echo "   create-dmg exited non-zero, falling back to native hdiutil (APFS)..."
      rm -f "${DMG_PATH}"
      hdiutil create -fs APFS -volname "Plantoir" -srcfolder "${DMG_STAGE}" -ov -format UDZO "${DMG_PATH}"
    }
else
  echo "   Using native hdiutil to create APFS disk image..."
  hdiutil create -fs APFS -volname "Plantoir" -srcfolder "${DMG_STAGE}" -ov -format UDZO "${DMG_PATH}"
fi

# ---- 6. Sign DMG, Notarize & Staple ------------------------------------------
if [[ "${SIGN}" == true ]]; then
  echo ""
  echo "🔏 Step 6: Signing DMG..."
  codesign --force --timestamp --sign "${IDENTITY}" "${DMG_PATH}"

  echo ""
  echo "☁️  Step 7: Submitting to Apple Notarization Service..."
  xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${KEYCHAIN_PROFILE}" --wait

  echo ""
  echo "📎 Step 8: Stapling Notarization Ticket to DMG..."
  xcrun stapler staple "${DMG_PATH}"

  echo ""
  echo "🛡️  Step 9: Assessing Gatekeeper Acceptance..."
  spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}" || true
  echo "✅ DMG notarized and stapled."
fi

# ---- Summary -----------------------------------------------------------------
HASH="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
SIZE="$(du -h "${DMG_PATH}" | cut -f1)"

echo ""
echo "============================================================"
echo "  macOS Release Asset Built Successfully!"
echo "============================================================"
echo "Asset:   ${DMG_PATH}"
echo "Size:    ${SIZE}"
echo "SHA-256: ${HASH}"
echo ""
echo "Next: Upload ${DMG_PATH} to GitHub Release."
echo ""
echo "Do not rebuild, re-sign or re-staple this DMG before the release is cut:"
echo "the update feed (website/update_feed.py) is signed against these exact bytes."
