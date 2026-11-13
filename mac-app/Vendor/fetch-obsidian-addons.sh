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
# written into this file. Read with /usr/bin/jq, which macOS has shipped since
# macOS 15, and the Xcode this project builds with (26 or later) needs macOS
# 15.6 or later, so nothing but macOS is needed.
#
# **Not plutil (#864).** This used /usr/bin/plutil until 2026-11-13. plutil
# refuses a whole JSON file that holds an escaped NUL anywhere in it
# ("Unsupported escaped (unicode) null"), and #780's cases in the same
# contract carry eight of them on purpose, so from 2026-11-12 the script
# read nothing, said the contract had no add-ons, and stopped every fresh
# clone and every release build at this step. jq reads the file as JSON
# says. `--print-pins` runs only the reading step and prints what it read,
# which scripts/test_fetch_obsidian_addons.py compares with Python's own
# reading of the contract, so the next character a reader refuses fails a
# suite rather than a new machine.
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

JQ="/usr/bin/jq"
if [[ ! -x "${JQ}" ]]; then
  echo "❌ ${JQ} is not on this Mac (macOS 15 or later has it). Nothing was installed." >&2
  exit 1
fi

# One value out of the contract: `field 0.files.1.sha256`. A list answers
# with its length, as `plutil -extract … raw` did; anything missing, or an
# object where a value was expected, is refused.
# shellcheck disable=SC2016  # the $ names are jq's, not the shell's
READ_ONE='($path | split(".") | map(if test("^[0-9]+$") then tonumber else . end)) as $steps
  | getpath($steps)
  | if type == "array" then length
    elif type == "string" or type == "number" then .
    else error("no value") end'
field() {
  local value path="${KEY}${1:+.${1}}"
  if ! value="$("${JQ}" -er --arg path "${path}" "${READ_ONE}" "${CONTRACT}" 2>/dev/null)"; then
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

# The reading step alone (#864): every pin, one tab-separated line per file,
# and nothing fetched, checked or installed.
if [[ "${1:-}" == "--print-pins" ]]; then
  for ((a = 0; a < ADDON_COUNT; a++)); do
    id="$(field "${a}.id")"
    version="$(field "${a}.version")"
    file_count="$(field "${a}.files")"
    for ((f = 0; f < file_count; f++)); do
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${id}" "${version}" \
        "$(field "${a}.files.${f}.name")" "$(field "${a}.files.${f}.bytes")" \
        "$(field "${a}.files.${f}.sha256")" "$(field "${a}.files.${f}.from")"
    done
  done
  exit 0
fi

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
