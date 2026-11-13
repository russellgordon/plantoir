#!/usr/bin/env bash
# Refuse a built Plantoir.app that carries compiled Python in its toolchain (#747).
#
#     release/check-no-bytecode.sh <Plantoir.app>
#
# The four folders the app mirrors into every working folder's `.toolchain/`
# (patches, scripts, support, contracts) are hashed by the launchers to name
# the website builder's image. A `__pycache__` folder or a `.pyc` file in them
# gives the same recipe a different image name, and every Mac builds the image
# again for nothing. The build phase that writes `toolchain.hashes`
# (BuildScripts/write_toolchain_hashes.py) removes them from the bundle, so
# this should never fire; it is the release's own proof, read from the BUILT
# bundle after step 3 of publish.sh.
set -euo pipefail

APP="${1:?usage: check-no-bytecode.sh <Plantoir.app>}"
RESOURCES="${APP}/Contents/Resources"

if [[ ! -d "${RESOURCES}/scripts" ]]; then
  echo "❌ ${RESOURCES} holds no scripts/ folder, so this is not a built Plantoir.app."
  exit 1
fi

for folder in patches scripts support contracts; do
  if [[ ! -d "${RESOURCES}/${folder}" || -L "${RESOURCES}/${folder}" ]]; then
    echo "❌ ${RESOURCES}/${folder} is missing or is not a real folder, so the bundle cannot be checked."
    exit 1
  fi
done

# find's own errors are shown and fail the check: a folder it cannot read is
# a folder nobody has looked in.
if ! found="$(cd "${RESOURCES}" && find patches scripts support contracts \
  \( -name '__pycache__' -o -name '*.pyc' -o -name '*.pyo' \) -print)"; then
  echo "❌ The toolchain the app carries could not be read in full, so it is not a bundle to ship."
  exit 1
fi

if [[ -n "${found}" ]]; then
  echo "${found}"
  echo "❌ This bundle carries compiled Python, which would rename the website builder's image on every Mac. Not a bundle to ship."
  exit 1
fi
echo "✅ No compiled Python in the toolchain the app carries."
