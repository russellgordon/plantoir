#!/usr/bin/env bash
# Refuse a signed Plantoir.app whose updater was not signed by the app's own team (#204).
#
#     release/check-signatures.sh <Plantoir.app>                 # team read from the app
#     release/check-signatures.sh <Plantoir.app> --expect-team T  # team given
#     release/check-signatures.sh <Plantoir.app> --ad-hoc-for-tests
#
# `codesign --verify --deep --strict` CANNOT see a missing step: an app
# re-signed with a Developer ID around Sparkle's helpers left ad-hoc still
# verifies (measured for #204's plan, `C.app`). Notarization would reject it
# five minutes later — or, if it ever got through another way, Sparkle would
# skip its atomic swap. This asks the question that matters, of every updater
# item and the app: the SAME team as the app, the hardened runtime, and — for
# the helpers — none of the app's entitlements. Prints each fault; exit 1 on any.
#
# The team is read from the app's own signature rather than typed in, so it is
# not a second copy of a value. An app with no team (ad-hoc) is refused: that
# is exactly what a release must never be. --ad-hoc-for-tests lifts that ONE
# rule so the other checks can be proven on this Mac without a Developer ID.
set -uo pipefail

APP="${1:?usage: check-signatures.sh <Plantoir.app> [--expect-team TEAM | --ad-hoc-for-tests]}"
MODE="${2:-}"
WANT_TEAM=""
AD_HOC_ALLOWED=false
case "${MODE}" in
  --expect-team) WANT_TEAM="${3:?--expect-team needs a team}" ;;
  --ad-hoc-for-tests) AD_HOC_ALLOWED=true ;;
  "") ;;
  *) echo "Unknown option: ${MODE}"; exit 2 ;;
esac

team_of() {
  codesign -dvv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'
}

if [[ -z "${WANT_TEAM}" ]]; then
  WANT_TEAM="$(team_of "${APP}")"
fi

faults=0
if [[ "${WANT_TEAM}" == "not set" || -z "${WANT_TEAM}" ]] && [[ "${AD_HOC_ALLOWED}" != true ]]; then
  echo "NOT SIGNED BY A TEAM: the app itself (a release must be Developer ID signed)"
  faults=$((faults + 1))
fi

FW="${APP}/Contents/Frameworks/Sparkle.framework"
items=()
if [[ -d "${FW}" ]]; then
  while IFS= read -r -d '' helper; do
    items+=("${helper}")
  done < <(find "${FW}/Versions/B" -maxdepth 2 \( -name '*.xpc' -o -name '*.app' -o -name 'Autoupdate' \) -print0)
  items+=("${FW}")
else
  echo "NO UPDATER: ${FW} is missing"
  faults=$((faults + 1))
fi
items+=("${APP}")

for item in "${items[@]}"; do
  name="${item#"${APP}"/}"
  [[ "${item}" == "${APP}" ]] && name="Plantoir.app"
  info="$(codesign -dvv "${item}" 2>&1)"
  team="$(printf '%s\n' "${info}" | sed -n 's/^TeamIdentifier=//p')"
  if [[ "${team}" != "${WANT_TEAM}" ]]; then
    echo "WRONG TEAM (${team:-none}, expected ${WANT_TEAM}): ${name}"
    faults=$((faults + 1))
  fi
  if ! printf '%s\n' "${info}" | grep -q 'flags=.*runtime'; then
    echo "NO HARDENED RUNTIME: ${name}"
    faults=$((faults + 1))
  fi
  if [[ "${item}" != "${APP}" ]]; then
    entitlements="$(codesign -d --entitlements - --xml "${item}" 2>/dev/null)"
    if printf '%s' "${entitlements}" | grep -q 'disable-library-validation\|network.server'; then
      echo "CARRIES THE APP'S ENTITLEMENTS: ${name}"
      faults=$((faults + 1))
    fi
  fi
done

if [[ ${faults} -gt 0 ]]; then
  echo "❌ ${faults} signing fault(s) — not a bundle to notarize."
  exit 1
fi
echo "✅ The updater and the app are signed by team ${WANT_TEAM}, with the hardened runtime, and no helper carries the app's entitlements."
