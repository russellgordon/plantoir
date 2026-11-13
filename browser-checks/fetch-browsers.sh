#!/usr/bin/env bash
# Fetches what the rendered check (browser-checks/rendered_features.mjs,
# #597) needs beyond Chrome for Testing: Playwright's driver, pinned exactly
# by package.json and package-lock.json beside this script, and the WebKit
# build that pin names (Safari's engine; 296 MB on disk, measured
# 2026-11-13 for webkit-2359).
#
# OPTIONAL. Without it verify.sh says the rendered check was SKIPPED, by
# name, never that it passed; with PLANTOIR_REQUIRE_ENGINES=chromium,webkit
# (the release gate and the director's merge gate set it) a missing engine
# is a FAILURE instead.
#
# Everything goes in a cache OUTSIDE the repository, the fetch-helpers.sh
# pattern, so a second clone or worktree costs nothing:
#
#   ${PLANTOIR_BROWSERS_CACHE:-~/Library/Caches/Plantoir-dev/browsers}/playwright/
#     node_modules/playwright-core/   the driver, from the lockfile (npm ci)
#     engines/webkit-<revision>/      the engine, PLAYWRIGHT_BROWSERS_PATH
#
# The engine lives in Plantoir's own folder rather than Playwright's shared
# ~/Library/Caches/ms-playwright, because `playwright install` from any other
# project removes the builds it no longer pins from that folder (the #597
# plan review, M1). When the shared folder already holds the same build it
# is COPIED from there (a clone on APFS: no download, no extra disk until
# one of them changes); otherwise Playwright's own installer downloads it.
#
# Chrome for Testing is not fetched here: it is documentation/06 F7's copy,
# the one every other browser check uses, given to the rendered check as
# its Chromium so a red in one check reproduces in another.
#
#   ./browser-checks/fetch-browsers.sh            fetch what is missing
#   ./browser-checks/fetch-browsers.sh --check    say what is there, fetch nothing
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${PLANTOIR_BROWSERS_CACHE:-$HOME/Library/Caches/Plantoir-dev/browsers}/playwright"
ENGINES="$CACHE/engines"
SHARED="${PLAYWRIGHT_SHARED_CACHE:-$HOME/Library/Caches/ms-playwright}"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "fetch-browsers: needs Node 22 or later and npm on the PATH" >&2
  exit 1
fi

PINNED="$(node -e 'console.log(require(process.argv[1]).packages["node_modules/playwright-core"].version)' "$HERE/package-lock.json")"

driver_ok() {
  [[ -f "$CACHE/node_modules/playwright-core/package.json" ]] \
    && [[ "$(node -e 'console.log(require(process.argv[1]).version)' "$CACHE/node_modules/playwright-core/package.json")" == "$PINNED" ]] \
    && cmp -s "$HERE/package-lock.json" "$CACHE/package-lock.json"
}

# The WebKit revision this Mac needs, as the pinned driver works it out
# (browsers.json, with its per-macOS overrides): asked of the driver itself
# rather than read here, so an override is never missed.
webkit_dir() {
  PLAYWRIGHT_BROWSERS_PATH="$ENGINES" node -e '
    const { webkit } = require(process.argv[1])
    const path = require("node:path")
    // executablePath() is <engines>/webkit-<rev>/pw_run.sh on macOS.
    console.log(path.dirname(webkit.executablePath()))
  ' "$CACHE/node_modules/playwright-core"
}

if [[ "${1:-}" == "--check" ]]; then
  if ! driver_ok; then
    echo "fetch-browsers: Playwright's driver $PINNED is not in $CACHE"
    exit 3
  fi
  dir="$(webkit_dir)"
  if [[ -f "$dir/INSTALLATION_COMPLETE" ]]; then
    echo "fetch-browsers: driver $PINNED and $(basename "$dir") ($(du -sh "$dir" | cut -f1)) in $CACHE"
    exit 0
  fi
  echo "fetch-browsers: driver $PINNED is there, but not $(basename "$dir")"
  exit 3
fi

mkdir -p "$CACHE" "$ENGINES"
if driver_ok; then
  echo "fetch-browsers: Playwright's driver $PINNED is already in $CACHE"
else
  cp "$HERE/package.json" "$HERE/package-lock.json" "$CACHE/"
  # --ignore-scripts: playwright-core has no install script, and nothing
  # else should run. The lockfile's integrity hash is what npm ci checks.
  (cd "$CACHE" && npm ci --ignore-scripts --no-audit --no-fund --loglevel=error)
  echo "fetch-browsers: installed Playwright's driver $PINNED in $CACHE"
fi

dir="$(webkit_dir)"
name="$(basename "$dir")"
if [[ -f "$dir/INSTALLATION_COMPLETE" ]]; then
  echo "fetch-browsers: $name is already in $ENGINES"
elif [[ -f "$SHARED/$name/INSTALLATION_COMPLETE" ]]; then
  rm -rf "${dir:?}"
  cp -Rc "$SHARED/$name" "$dir" 2>/dev/null || cp -R "$SHARED/$name" "$dir"
  echo "fetch-browsers: copied $name from $SHARED ($(du -sh "$dir" | cut -f1))"
else
  echo "fetch-browsers: downloading $name (about 300 MB)…"
  PLAYWRIGHT_BROWSERS_PATH="$ENGINES" node "$CACHE/node_modules/playwright-core/cli.js" install webkit
fi
[[ -f "$dir/INSTALLATION_COMPLETE" ]] || { echo "fetch-browsers: $name did not arrive" >&2; exit 1; }
echo "fetch-browsers: ready - the rendered check finds the driver and $name in $CACHE"
