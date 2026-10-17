#!/usr/bin/env bash
# Fetch the Obsidian add-ons Plantoir carries for diagrams and graphs (#495) —
# TikZJax and Functionplot, with their licences — into
# mac-app/Vendor/obsidian-addons/<id>/, which the app carries as
# Contents/Resources/obsidian-addons and writes into a course on the teacher's
# one yes (documentation/09-mac-app.md → "Obsidian's add-ons for diagrams and
# graphs (#495)").
#
# **The pins are the contract's, read from it — never repeated here.** Every
# add-on's id and version, and every file's name, size, SHA-256 and address,
# live in contracts/shared-rules.json → obsidianAddOnsForFigures.addOns, which
# the app's own pins and Windows' fetch read too; two lists would be two
# answers. ObsidianFigureAddOnsTests fails if a 64-character hex run is ever
# written into this file. Read with /usr/bin/plutil, so nothing but macOS is
# needed.
#
# **Checked before anything is installed.** Every file must be the size and
# SHA-256 its pin says; one mismatch installs NOTHING. The app hashes them
# again before it writes them into a course.
#
# **A cache outside the repository**, as fetch-helpers.sh keeps:
# ${PLANTOIR_ADDONS_CACHE:-~/Library/Caches/Plantoir-dev/obsidian-addons},
# files named by their SHA-256 and checked again before use, so a second clone
# or worktree costs no download.
#
# NOT committed, for the same reason llama.cpp is not (see fetch-llama.sh):
# this repository ships recipes, not binaries. Run it once per clone or
# worktree before `xcodegen generate` — project.yml names
# Vendor/obsidian-addons as a resource folder, so generating without it fails —
# and run `xcodegen generate` again after it replaces the folder (Trap 1 in
# CLAUDE.md). Idempotent: a folder that already matches every pin is left as
# it is.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="${HERE}/../../contracts/shared-rules.json"
DESTINATION="${HERE}/obsidian-addons"
CACHE="${PLANTOIR_ADDONS_CACHE:-$HOME/Library/Caches/Plantoir-dev/obsidian-addons}"
KEY="obsidianAddOnsForFigures.addOns"

# One value out of the contract: `field 0.files.1.sha256`.
field() {
  local value path="${KEY}${1:+.${1}}"
  if ! value="$(/usr/bin/plutil -extract "${path}" raw -o - "${CONTRACT}" 2>/dev/null)"; then
    echo "❌ contracts/shared-rules.json has no ${path}. Nothing was installed." >&2
    exit 1
  fi
  echo "${value}"
}

sha_of() {
  shasum -a 256 "$1" | cut -d' ' -f1
}

size_of() {
  stat -f %z "$1"
}

ADDON_COUNT="$(field "")"

# Already in place? Every pinned file present at its size and hash, and
# nothing else.
in_place=1
expected_files=0
for ((a = 0; a < ADDON_COUNT; a++)); do
  id="$(field "${a}.id")"
  file_count="$(field "${a}.files")"
  for ((f = 0; f < file_count; f++)); do
    name="$(field "${a}.files.${f}.name")"
    sha="$(field "${a}.files.${f}.sha256")"
    expected_files=$((expected_files + 1))
    if [[ ! -f "${DESTINATION}/${id}/${name}" ]] || [[ "$(sha_of "${DESTINATION}/${id}/${name}")" != "${sha}" ]]; then
      in_place=0
    fi
  done
done
if [[ "${in_place}" == 1 ]] && [[ "$(find "${DESTINATION}" -type f | wc -l | tr -d ' ')" == "${expected_files}" ]]; then
  echo "✅ The Obsidian add-ons are already in place (${DESTINATION})."
  exit 0
fi

mkdir -p "${CACHE}"
STAGED="$(mktemp -d "${HERE}/.obsidian-addons.XXXXXX")"
trap 'rm -rf "${STAGED}"' EXIT

for ((a = 0; a < ADDON_COUNT; a++)); do
  id="$(field "${a}.id")"
  version="$(field "${a}.version")"
  file_count="$(field "${a}.files")"
  echo "⬇️  ${id} ${version}…"
  mkdir -p "${STAGED}/${id}"
  for ((f = 0; f < file_count; f++)); do
    name="$(field "${a}.files.${f}.name")"
    bytes="$(field "${a}.files.${f}.bytes")"
    sha="$(field "${a}.files.${f}.sha256")"
    from="$(field "${a}.files.${f}.from")"
    cached="${CACHE}/${sha}"
    if [[ ! -f "${cached}" ]] || [[ "$(sha_of "${cached}")" != "${sha}" ]]; then
      curl -fsSL -o "${cached}.part" "${from}"
      mv "${cached}.part" "${cached}"
    fi
    if [[ "$(size_of "${cached}")" != "${bytes}" ]] || [[ "$(sha_of "${cached}")" != "${sha}" ]]; then
      echo "❌ ${id}/${name} does not match its pin. Nothing was installed."
      echo "   expected ${bytes} bytes, ${sha}"
      echo "   got      $(size_of "${cached}") bytes, $(sha_of "${cached}")"
      rm -f "${cached}"
      exit 1
    fi
    cp "${cached}" "${STAGED}/${id}/${name}"
  done
done

rm -rf "${DESTINATION}"
mv "${STAGED}" "${DESTINATION}"
trap - EXIT
echo "✅ The Obsidian add-ons are installed into ${DESTINATION} ($(du -sh "${DESTINATION}" | cut -f1))."
echo "   Run \`xcodegen generate\` again if the project already existed (Trap 1)."
