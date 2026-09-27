#!/usr/bin/env bash
# Sign the website builder's helper programs inside a staged Plantoir.app
# (GitHub #312), one by one, and write their MANIFEST again.
#
#     release/sign-helpers.sh <Plantoir.app> <identity> [--no-timestamp]
#
# Called by publish.sh -Sign after the updater, the dylibs and llama-server,
# and BEFORE the app, so the new MANIFEST is sealed inside the app's own
# signature. Colima, limactl, the Docker CLI and buildx arrive signed ad-hoc
# by their projects (buildx by Docker's own team), and notarization refuses
# nested code that is not Developer ID signed with a timestamp and the
# hardened runtime.
#
# **limactl keeps its entitlements, and only limactl has any.**
# release/limactl.entitlements is upstream's own set, read from Lima 2.2.0's
# signature: com.apple.security.virtualization (without it a hardened limactl
# cannot start a vz virtual machine — found only at a teacher's first start),
# and network.client and network.server. Never the app's entitlements:
# disable-library-validation on a command-line program is exactly what a
# reviewer of a notarized app asks about. The others need none.
#
# **Signing changes the bytes, so the MANIFEST is written again** from the
# signed files (fetch-helpers.sh --manifest-only). A launcher checks the copies
# it installs against it; a stale one would make every teacher's Mac refuse
# the app's copy and quietly download instead. check-signatures.sh asks.
#
# The identifiers are fixed, rather than kept from upstream (the Docker CLI's
# is "a.out"), so every release signs each program under the same name.
#
# --no-timestamp is for the tests, which sign ad-hoc ("-").
set -euo pipefail

APP="${1:?usage: sign-helpers.sh <Plantoir.app> <identity> [--no-timestamp]}"
IDENTITY="${2:?usage: sign-helpers.sh <Plantoir.app> <identity> [--no-timestamp]}"
TIMESTAMP="--timestamp"
if [[ "${3:-}" == "--no-timestamp" ]]; then
  TIMESTAMP="--timestamp=none"
fi
RELEASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPERS="${APP}/Contents/Resources/helpers"
if [[ ! -f "${HELPERS}/MANIFEST" ]]; then
  echo "❌ ${HELPERS} is not there — the app carries no helper programs. Was Vendor/fetch-helpers.sh run before the build?"
  exit 1
fi

signed=0
while IFS= read -r -d '' program; do
  if ! file -b "${program}" | grep -q '^Mach-O'; then
    continue
  fi
  name="$(basename "${program}")"
  if [[ "${name}" == "limactl" ]]; then
    codesign --force "${TIMESTAMP}" --options runtime \
      --identifier "ca.russellgordon.Plantoir.helper.${name}" \
      --entitlements "${RELEASE}/limactl.entitlements" --sign "${IDENTITY}" "${program}"
  else
    codesign --force "${TIMESTAMP}" --options runtime \
      --identifier "ca.russellgordon.Plantoir.helper.${name}" --sign "${IDENTITY}" "${program}"
  fi
  signed=$((signed + 1))
done < <(find "${HELPERS}" -type f -print0)

"${RELEASE}/../Vendor/fetch-helpers.sh" --manifest-only "${HELPERS}" >/dev/null
echo "   - Signed ${signed} helper programs, limactl with its own entitlements; MANIFEST written again."
