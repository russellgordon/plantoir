#!/usr/bin/env bash
# Fetch Sparkle — the framework the macOS app uses to find and install its own
# new versions (issue #204) — into mac-app/Vendor/Sparkle/.
#
# NOT committed, for the same reason llama.cpp is not (see fetch-llama.sh):
# this repository ships recipes, not binaries. Run this once before
# `xcodegen generate`; `project.yml` names Vendor/Sparkle/Sparkle.framework as
# a dependency, so generating without it fails.
#
# **Pinned by version AND by checksum.** The version says which release we
# meant; the SHA-256 says we got those exact bytes. A framework that installs
# new copies of the app is the one piece of code whose silent substitution
# would matter most, so a mismatch refuses and installs NOTHING.
#
# **Why 2.9.6 and not a later one.** Decided on issue #204 on 2026-09-19, when
# 2.9.6 was current. 2.10.0 followed on 2026-09-13 with no security fix and a
# macOS 12 minimum; nothing in it is needed here, so the pin stays until a
# release brings something we need — and moving it means re-reading the
# delegate hooks, because a near-miss Swift name compiles and is never called
# (documentation/09-mac-app.md → "Updating itself").
set -euo pipefail

VERSION="2.9.6"
SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
ARCHIVE="Sparkle-${VERSION}.tar.xz"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/${ARCHIVE}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTINATION="${HERE}/Sparkle"
INSTALLED_PLIST="${DESTINATION}/Sparkle.framework/Resources/Info.plist"

# Idempotent by VERSION rather than by presence (fetch-llama.sh checks only
# that a file exists): when the pin above moves, the next run replaces the old
# copy instead of reporting that one is "already in place".
if [[ -f "${INSTALLED_PLIST}" ]]; then
  INSTALLED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INSTALLED_PLIST}" 2>/dev/null || true)"
  if [[ "${INSTALLED}" == "${VERSION}" ]]; then
    echo "✅ Sparkle ${VERSION} is already in place (${DESTINATION})."
    echo "   Delete that folder and re-run to fetch it again."
    exit 0
  fi
  echo "↻  Sparkle ${INSTALLED:-(unknown)} is in place; the pin is ${VERSION}. Replacing it."
fi

WORKING="$(mktemp -d)"
trap 'rm -rf "${WORKING}"' EXIT

echo "⬇️  Fetching Sparkle ${VERSION}…"
curl -fsSL -o "${WORKING}/${ARCHIVE}" "${URL}"

echo "🔒 Checking it is the archive we pinned…"
if ! echo "${SHA256}  ${WORKING}/${ARCHIVE}" | shasum -a 256 -c - >/dev/null 2>&1; then
  echo "❌ ${ARCHIVE} does not match the pinned SHA-256. Nothing was installed."
  echo "   expected ${SHA256}"
  echo "   got      $(shasum -a 256 "${WORKING}/${ARCHIVE}" | cut -d' ' -f1)"
  exit 1
fi

echo "📦 Unpacking…"
mkdir -p "${WORKING}/unpacked"
tar -xJf "${WORKING}/${ARCHIVE}" -C "${WORKING}/unpacked"

SOURCE="${WORKING}/unpacked"
if [[ ! -d "${SOURCE}/Sparkle.framework/Versions/B" ]]; then
  echo "❌ That archive did not contain Sparkle.framework. Nothing was installed."
  exit 1
fi

# The two XPC services are for SANDBOXED apps only, and Plantoir is not
# sandboxed (QuartzTeachers.entitlements has no app-sandbox key). Sparkle's
# own guidance: "Do not enable this XPC Service if your application is not
# sandboxed", and its "Removing XPC Services" section says to delete them.
# Removing them means two fewer nested bundles to sign and notarize, 424 KB
# less, and no later edit that could switch one on by mistake.
rm -rf "${SOURCE}/Sparkle.framework/Versions/B/XPCServices"
rm -f "${SOURCE}/Sparkle.framework/XPCServices"

STAGED="${WORKING}/staged"
mkdir -p "${STAGED}/bin"
# ditto keeps the framework's version symlinks (Versions/Current -> B, and
# the top-level Sparkle / Autoupdate / Updater.app links) as symlinks.
ditto "${SOURCE}/Sparkle.framework" "${STAGED}/Sparkle.framework"
# The two tools the release needs: generate_appcast writes the update feed,
# sign_update signs and verifies it. The rest of bin/ is not used here.
cp -a "${SOURCE}/bin/generate_appcast" "${STAGED}/bin/"
cp -a "${SOURCE}/bin/sign_update" "${STAGED}/bin/"
# MIT: the notice travels with every copy, so the app carries it as a file —
# named for whose it is, since it lands at the top of the app's Resources.
cp -a "${SOURCE}/LICENSE" "${STAGED}/Sparkle-LICENSE"

rm -rf "${DESTINATION}"
mv "${STAGED}" "${DESTINATION}"

echo "✅ Sparkle ${VERSION} installed into ${DESTINATION} ($(du -sh "${DESTINATION}" | cut -f1))."
