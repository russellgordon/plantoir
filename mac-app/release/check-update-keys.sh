#!/usr/bin/env bash
# Refuse a built Plantoir.app that cannot update itself, or would update from the wrong place (#204).
#
#     release/check-update-keys.sh <Plantoir.app> [<expected feed>]
#
# A Release build that lost its feed address ships an app that never offers an
# update and says nothing; one with the wrong public key refuses every update
# it is offered. Read from the BUILT bundle, after step 3 of publish.sh —
# the Info.plist is expanded per build, so project.yml alone proves nothing.
set -euo pipefail

APP="${1:?usage: check-update-keys.sh <Plantoir.app> [<expected feed>]}"
EXPECTED_FEED="${2:-https://plantoir.app/updates/macos.xml}"
EXPECTED_KEY="lYt8VK8iKB4jMy+b06j1m+GAedeTChAbX5NkMW2FSMw="
PLIST="${APP}/Contents/Info.plist"

feed="$(plutil -extract SUFeedURL raw -o - "${PLIST}" 2>/dev/null || true)"
key="$(plutil -extract SUPublicEDKey raw -o - "${PLIST}" 2>/dev/null || true)"
automatic="$(plutil -extract SUAllowsAutomaticUpdates raw -o - "${PLIST}" 2>/dev/null || true)"

faults=0
if [[ "${feed}" != "${EXPECTED_FEED}" ]]; then
  echo "WRONG FEED: '${feed}' (expected ${EXPECTED_FEED})"
  faults=$((faults + 1))
fi
if [[ "${key}" != "${EXPECTED_KEY}" ]]; then
  echo "WRONG PUBLIC KEY: '${key}'"
  faults=$((faults + 1))
fi
if [[ "${automatic}" != "false" ]]; then
  echo "INSTALLS WITHOUT ASKING: SUAllowsAutomaticUpdates is '${automatic}', not false"
  faults=$((faults + 1))
fi
if [[ ${faults} -gt 0 ]]; then
  echo "❌ This bundle's update keys are wrong — not a bundle to ship."
  exit 1
fi
echo "✅ Updates from ${feed}, signed with the plantoir-macos key, asking first."
