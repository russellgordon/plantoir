#!/usr/bin/env bash
# Sign the updater's own code inside a staged Plantoir.app (#204), item by item.
#
#     release/sign-updater.sh <Plantoir.app> <identity> [--no-timestamp]
#
# Called by publish.sh -Sign BEFORE it signs the dylibs, llama-server and the
# app. Xcode's "Code Sign On Copy" re-signs the framework's top level only; the
# helpers inside it — Autoupdate and Updater.app — arrive signed ad-hoc by the
# Sparkle project, and notarization refuses nested code that is not Developer
# ID signed with a timestamp. Worse, if one ever slipped through, Sparkle would
# find its installer on a different team from the update and silently skip its
# atomic swap and Gatekeeper scan.
#
# The ORDER is the rule: nested code first, innermost to outermost, the
# framework LAST of the updater's items (it seals what is inside it). Never
# --deep. Never the app's entitlements on any of these — Autoupdate and
# Updater.app need none, and the app's disable-library-validation on a helper
# is exactly what a reviewer of a notarized app asks about. The two XPC
# services are removed by fetch-sparkle.sh; they are signed here only if a
# later Sparkle brings them back.
#
# --no-timestamp is for the tests, which sign ad-hoc ("-") and have no
# timestamp server to ask. publish.sh never passes it.
set -euo pipefail

APP="${1:?usage: sign-updater.sh <Plantoir.app> <identity> [--no-timestamp]}"
IDENTITY="${2:?usage: sign-updater.sh <Plantoir.app> <identity> [--no-timestamp]}"
TIMESTAMP="--timestamp"
if [[ "${3:-}" == "--no-timestamp" ]]; then
  TIMESTAMP="--timestamp=none"
fi

FW="${APP}/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "${FW}" ]]; then
  echo "❌ ${FW} is not there — the app has no updater to sign. Was Vendor/Sparkle fetched before the build?"
  exit 1
fi
B="${FW}/Versions/B"

if [[ -d "${B}/XPCServices/Installer.xpc" ]]; then
  codesign --force "${TIMESTAMP}" --options runtime --sign "${IDENTITY}" "${B}/XPCServices/Installer.xpc"
fi
if [[ -d "${B}/XPCServices/Downloader.xpc" ]]; then
  # Downloader carries entitlements of its own; keep those, add none.
  codesign --force "${TIMESTAMP}" --options runtime --preserve-metadata=entitlements \
    --sign "${IDENTITY}" "${B}/XPCServices/Downloader.xpc"
fi
codesign --force "${TIMESTAMP}" --options runtime --sign "${IDENTITY}" "${B}/Autoupdate"
codesign --force "${TIMESTAMP}" --options runtime --sign "${IDENTITY}" "${B}/Updater.app"
codesign --force "${TIMESTAMP}" --options runtime --sign "${IDENTITY}" "${FW}"
echo "   - Signed the updater's helpers and framework."
