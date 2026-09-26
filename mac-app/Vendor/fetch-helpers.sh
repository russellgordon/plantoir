#!/usr/bin/env bash
# Fetch the website builder's helper programs and its starting disk into
# mac-app/Vendor/helpers/, which the app carries as Contents/Resources/helpers
# (GitHub #312).
#
# What is fetched: Colima, Lima (limactl, its `lima` wrapper, the Linux guest
# agent and its templates), the Docker CLI, Buildx, and the Ubuntu disk image
# Colima creates its virtual machine from — for Apple silicon only. An Intel
# Mac downloads its own, as before: a universal copy would add about 500 MB to
# every Apple-silicon teacher's download (documentation/09-mac-app.md).
#
# **The pins are setup.sh's, read from it — never repeated here.** The versions
# and the SHA-256 of every file live in the launchers' shared first-run block,
# which also downloads them on a Mac without this copy; two lists would be two
# answers. HelperVersionsTests fails if a version or a checksum is written into
# this file.
#
# **Checked twice before anything is installed.** Every download must hash to
# its pinned SHA-256. And the disk image's pinned SHA-512 must be compiled into
# the pinned Colima, because Colima refuses any disk whose SHA-512 it does not
# carry: a Colima bump without a disk bump would otherwise be found at a
# teacher's first start, as a slow download, rather than here.
#
# **A cache outside the repository.** About 470 MB, so every clone and every
# worktree would otherwise download it again. Files are kept under
# ${PLANTOIR_HELPERS_CACHE:-~/Library/Caches/Plantoir-dev/helpers}, named by
# their SHA-256, and checked again before use; a cached file that no longer
# matches is fetched afresh. The folder in the repository is made with clones
# (cp -c), so it costs no disk on the same volume.
#
# NOT committed, for the same reason llama.cpp is not (see fetch-llama.sh).
# Run it once before `xcodegen generate` — project.yml names Vendor/helpers as a
# resource folder, so generating without it fails — and run `xcodegen generate`
# again after it replaces the folder (Trap 1 in CLAUDE.md).
#
# `fetch-helpers.sh --manifest-only <helpers folder>` writes that folder's
# MANIFEST again from the files as they are now. publish.sh uses it after it
# signs the programs, which changes their bytes.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="${HERE}/../../setup.sh"
DESTINATION="${HERE}/helpers"
CACHE="${PLANTOIR_HELPERS_CACHE:-$HOME/Library/Caches/Plantoir-dev/helpers}"

# One pin out of setup.sh: `pin COLIMA_VERSION`.
pin() {
  local value
  value="$(sed -n "s/^${1}=\"\\(.*\\)\"$/\\1/p" "${SETUP}" | head -n 1)"
  if [[ -z "${value}" ]]; then
    echo "❌ setup.sh has no ${1}. Nothing was installed." >&2
    exit 1
  fi
  echo "${value}"
}

COLIMA_V="$(pin COLIMA_VERSION)"
LIMA_V="$(pin LIMA_VERSION)"
DOCKER_V="$(pin DOCKER_CLI_VERSION)"
BUILDX_V="$(pin BUILDX_VERSION)"
IMAGE_RELEASE="$(pin VM_IMAGE_RELEASE)"
IMAGE_NAME="$(pin VM_IMAGE_NAME)"
IMAGE_SHA256="$(pin VM_IMAGE_SHA256)"
IMAGE_SHA512="$(pin VM_IMAGE_SHA512)"
PINS_LINE="pins ${COLIMA_V} ${LIMA_V} ${DOCKER_V} ${BUILDX_V} ${IMAGE_SHA512}"

# Every file but the disk, which Colima checks itself: one "<sha256>  <path>"
# line each, after the arch, pins and image lines.
write_manifest() {
  local folder="$1" next
  next="${folder}/MANIFEST.next"
  {
    echo "arch arm64"
    echo "${PINS_LINE}"
    echo "image vm/${IMAGE_NAME}"
    (cd "${folder}" && find . -type f ! -path './vm/*' ! -name 'MANIFEST' ! -name 'MANIFEST.next' \
        | sed 's#^\./##' | LC_ALL=C sort | while IFS= read -r file; do
      shasum -a 256 "${file}"
    done)
  } > "${next}"
  mv -f "${next}" "${folder}/MANIFEST"
}

if [[ "${1:-}" == "--manifest-only" ]]; then
  if [[ -z "${2:-}" || ! -d "${2}" ]]; then
    echo "usage: fetch-helpers.sh --manifest-only <helpers folder>" >&2
    exit 2
  fi
  write_manifest "$2"
  echo "✅ Wrote ${2}/MANIFEST again from the files there."
  exit 0
fi

# Idempotent by the pins line, not by presence: when a pin moves, the next run
# replaces the old copy instead of reporting that one is in place. And the
# files must still match their MANIFEST, so a half-edited folder is replaced.
if [[ -f "${DESTINATION}/MANIFEST" ]] && grep -qxF "${PINS_LINE}" "${DESTINATION}/MANIFEST"; then
  if (cd "${DESTINATION}" && grep '^[0-9a-f]\{64\}  ' MANIFEST | shasum -a 256 -c --status) \
     && [[ -f "${DESTINATION}/vm/${IMAGE_NAME}" ]]; then
    echo "✅ The helpers for Colima ${COLIMA_V}, Lima ${LIMA_V}, Docker CLI ${DOCKER_V} and Buildx ${BUILDX_V} are already in place (${DESTINATION})."
    exit 0
  fi
  echo "↻  ${DESTINATION} does not match its MANIFEST. Fetching it again."
elif [[ -d "${DESTINATION}" ]]; then
  echo "↻  ${DESTINATION} holds other versions than setup.sh pins. Replacing it."
fi

mkdir -p "${CACHE}"
WORKING="$(mktemp -d "${HERE}/.helpers.XXXXXX")"
trap 'rm -rf "${WORKING}"' EXIT

# A verified file in the cache, fetched when it is missing or no longer matches.
# Prints its path.
cached() {
  local url="$1" name="$2" sha="$3" file
  file="${CACHE}/${sha}-${name}"
  if [[ -f "${file}" ]] && echo "${sha}  ${file}" | shasum -a 256 -c --status; then
    echo "${file}"
    return 0
  fi
  echo "⬇️  Fetching ${name}…" >&2
  curl -fsSL --retry 3 -o "${file}.part" "${url}"
  if ! echo "${sha}  ${file}.part" | shasum -a 256 -c --status; then
    echo "❌ ${name} does not match the SHA-256 setup.sh pins. Nothing was installed." >&2
    echo "   expected ${sha}" >&2
    echo "   got      $(shasum -a 256 "${file}.part" | cut -d' ' -f1)" >&2
    rm -f "${file}.part"
    exit 1
  fi
  mv -f "${file}.part" "${file}"
  echo "${file}"
}

LIMA_FILE="$(cached "https://github.com/lima-vm/lima/releases/download/v${LIMA_V}/lima-${LIMA_V}-Darwin-arm64.tar.gz" \
  "lima-${LIMA_V}-Darwin-arm64.tar.gz" "$(pin LIMA_SHA256_ARM64)")"
COLIMA_FILE="$(cached "https://github.com/abiosoft/colima/releases/download/${COLIMA_V}/colima-Darwin-arm64" \
  "colima-${COLIMA_V}-Darwin-arm64" "$(pin COLIMA_SHA256_ARM64)")"
DOCKER_FILE="$(cached "https://download.docker.com/mac/static/stable/aarch64/docker-${DOCKER_V}.tgz" \
  "docker-${DOCKER_V}-aarch64.tgz" "$(pin DOCKER_CLI_SHA256_ARM64)")"
BUILDX_FILE="$(cached "https://github.com/docker/buildx/releases/download/${BUILDX_V}/buildx-${BUILDX_V}.darwin-arm64" \
  "buildx-${BUILDX_V}.darwin-arm64" "$(pin BUILDX_SHA256_ARM64)")"
IMAGE_FILE="$(cached "https://github.com/abiosoft/colima-core/releases/download/${IMAGE_RELEASE}/${IMAGE_NAME}" \
  "${IMAGE_NAME}" "${IMAGE_SHA256}")"

echo "🔒 Checking the disk's SHA-512 is the one setup.sh pins and Colima ${COLIMA_V} expects…"
ACTUAL_SHA512="$(shasum -a 512 "${IMAGE_FILE}" | cut -d' ' -f1)"
if [[ "${ACTUAL_SHA512}" != "${IMAGE_SHA512}" ]]; then
  echo "❌ ${IMAGE_NAME} does not match VM_IMAGE_SHA512. Nothing was installed."
  exit 1
fi
if [[ "$(strings "${COLIMA_FILE}" | grep -c "${IMAGE_SHA512}" || true)" == "0" ]]; then
  echo "❌ Colima ${COLIMA_V} does not carry the SHA-512 of ${IMAGE_NAME}, so it would refuse it at a"
  echo "   teacher's first start and download its own. Bump VM_IMAGE_* in setup.sh with COLIMA_VERSION."
  echo "   Nothing was installed."
  exit 1
fi

echo "📦 Unpacking…"
STAGED="${WORKING}/helpers"
mkdir -p "${STAGED}/bin" "${STAGED}/cli-plugins" "${STAGED}/share/lima" "${STAGED}/vm"
mkdir -p "${WORKING}/lima" "${WORKING}/docker"
tar xzf "${LIMA_FILE}" -C "${WORKING}/lima"
tar xzf "${DOCKER_FILE}" -C "${WORKING}/docker"

# From Lima: limactl, the `lima` wrapper Colima's dependency check looks for
# beside it (without it: "lima not found, run 'brew install lima'"), the Linux
# guest agent and the templates. NOT the macOS guest agent (a gzipped program
# nobody signs, for macOS guests only), the krunkit driver or limactl-mcp —
# vz needs neither, measured — nor the manuals.
cp -c "${WORKING}/lima/bin/limactl" "${WORKING}/lima/bin/lima" "${STAGED}/bin/"
cp -c "${WORKING}/lima/share/lima/lima-guestagent.Linux-aarch64.gz" "${STAGED}/share/lima/"
cp -Rc "${WORKING}/lima/share/lima/templates" "${STAGED}/share/lima/templates"
cp -c "${COLIMA_FILE}" "${STAGED}/bin/colima"
cp -c "${WORKING}/docker/docker/docker" "${STAGED}/bin/docker"
cp -c "${BUILDX_FILE}" "${STAGED}/cli-plugins/docker-buildx"
chmod 755 "${STAGED}/bin/colima" "${STAGED}/bin/limactl" "${STAGED}/bin/lima" "${STAGED}/bin/docker" \
  "${STAGED}/cli-plugins/docker-buildx"
# The disk as downloaded, never recompressed: Colima checks its SHA-512.
cp -c "${IMAGE_FILE}" "${STAGED}/vm/${IMAGE_NAME}"
chmod 644 "${STAGED}/vm/${IMAGE_NAME}"
xattr -cr "${STAGED}" 2>/dev/null || true

write_manifest "${STAGED}"

# Replace the whole folder, which changes its parent's modification time —
# but run `xcodegen generate` anyway before building (Trap 1).
rm -rf "${DESTINATION}"
mv "${STAGED}" "${DESTINATION}"

echo "✅ The helpers for Colima ${COLIMA_V}, Lima ${LIMA_V}, Docker CLI ${DOCKER_V} and Buildx ${BUILDX_V},"
echo "   and the starting disk, are in ${DESTINATION} ($(du -sh "${DESTINATION}" | cut -f1))."
echo "   Run 'xcodegen generate' before building, so Xcode copies the new folder."
