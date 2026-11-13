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

found="$(cd "${RESOURCES}" && find patches scripts support contracts \
  \( -name '__pycache__' -o -name '*.pyc' \) -print 2>/dev/null || true)"

if [[ -n "${found}" ]]; then
  echo "${found}"
  echo "❌ This bundle carries compiled Python, which would rename the website builder's image on every Mac. Not a bundle to ship."
  exit 1
fi
echo "✅ No compiled Python in the toolchain the app carries."
