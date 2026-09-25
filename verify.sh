#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# verify.sh — end-to-end verification of local toolchain changes (maintainer use)
#
# Builds a fresh local image (quartz-teacher:dev-test) from this repository,
# checks that everything baked into it matches the working tree, then drives
# the real launcher scripts against it so you can confirm that host-side and
# image-side changes work together — the same recipe every working
# folder builds from locally.
#
# What it does, in order:
#   0. Runs the shared scripts' pure-Python unit tests (no Docker needed) so a
#      broken script fails in milliseconds rather than after a full image
#      build. Step 0 also RUNS deploy.sh AND preview.sh — hollowed out with
#      --image and a Keychain user that does not exist, so they need no
#      container, no network and no credentials — because a launcher that is
#      only ever read is a launcher nobody has started (GitHub issues #129 and
#      #124). Note that these tests are a written LIST here, not a discovery:
#      a new scripts/test_*.py must be added below or it runs on Windows (whose
#      PythonToolchainTests does discover them) and nowhere on the mac.
#   1. Ensures the container runtime is up (shares an already-running Colima;
#      never stops it — safe to run alongside other Colima-based toolchains).
#   2. docker build -t quartz-teacher:dev-test .
#   3. Verifies 'export-scripts' emits launchers identical to the repo copies
#      (and that Windows launchers were converted to CRLF).
#   4. Verifies the Python scripts and Quartz patches baked into the image
#      match the working tree.
#   5. Removes this folder's existing container, then runs
#      ./preview.sh EXC2O 1 --image quartz-teacher:dev-test --full-rebuild --build-only
#      so the container is recreated FROM THE DEV-TEST IMAGE and a full static
#      build of the Example Course runs through the real launcher.
#   6. Confirms the built site exists, that it carries and links Plantoir's
#      own icon rather than Quartz's, and that the running container uses the
#      dev-test image, then prints a PASS/FAIL summary. Section 6e builds the
#      same fixture again from a folder called ".plantoir-verify-26:27" —
#      the name macOS writes when a teacher types "26/27" in Finder — in a
#      container of its own, removed before AND after, since a container left
#      behind would let the next run pass without creating one.
#
# Usage:
#   ./verify.sh [--no-cache] [--skip-build]
#
#   --no-cache     Build the image without Docker's layer cache.
#   --skip-build   Reuse an existing quartz-teacher:dev-test image (faster when
#                  only host-side scripts changed).
#
# Requires: courses/EXC2O (the Example Course) in this folder as the build
# fixture. courses/ is gitignored, so on a fresh clone install it first via
# ./setup.sh (answer 'y' to the Example Course prompt).
# ==============================================================================

cd "$(dirname "$0")"

DEV_TEST_IMAGE="quartz-teacher:dev-test"
# The launchers name their container after the working folder.
CONTAINER_NAME="teaching-quartz-$(pwd -P | shasum -a 256 | cut -c1-8)"
# The launchers' own way of naming a folder they hand to a container, loaded
# out of the block the three of them share rather than spelled a second way
# here. `-v src:dst` splits on ':', so a working folder called
# "Comm Tech 26:27" cannot be named with it at all (GitHub issue #221) — and
# a known-bad pattern left in the file that demonstrates the fix is how the
# pattern comes back. Section 6e below drives the real thing from a real
# colon-named folder; this is for the checks that mount a file into a
# throwaway container.
# shellcheck disable=SC1090
source /dev/stdin <<<"$(awk '/^# >>> CONTAINER MOUNT BLOCK >>>/{inside=1} inside{print} /^# <<< CONTAINER MOUNT BLOCK <<</{inside=0}' setup.sh)"
if ! declare -f bind_mount_argument >/dev/null; then
  echo "❌ setup.sh has no CONTAINER MOUNT BLOCK — verify.sh names its mounts with the launchers' own helper."
  exit 1
fi
NO_CACHE=""
SKIP_BUILD="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-cache)   NO_CACHE="--no-cache"; shift ;;
    --skip-build) SKIP_BUILD="true"; shift ;;
    --help|-h)
      # Print the banner by finding its end rather than by a fixed line
      # number: the range used to be hard-coded, so every line added to the
      # comment above quietly truncated the help text from the bottom — the
      # part that says how to install the fixture this script requires.
      sed -n '4,/^# =\{10,\}$/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'
      exit 0 ;;
    *) echo "❌ Unknown option: $1 (see --help)"; exit 1 ;;
  esac
done

# -------------------- Result bookkeeping --------------------
RESULTS=()
FAILED="false"
pass() { RESULTS+=("✅ PASS  $1"); echo "✅ PASS  $1"; }
fail() { RESULTS+=("❌ FAIL  $1"); echo "❌ FAIL  $1"; FAILED="true"; }

# -------------------- 0. A real terminal is required --------------------
# The launchers run the toolchain with `docker exec -it`, which refuses to
# start without a terminal on stdin. Say so now rather than failing several
# minutes in with a Docker error about attaching stdin.
if [[ ! -t 0 ]]; then
  echo "❌ verify.sh must be run from a terminal."
  echo "   The launchers use 'docker exec -it', which needs a TTY on stdin."
  echo "   To run it from a script or CI, give it one:"
  echo "     script -q /dev/null ./verify.sh"
  exit 1
fi

# -------------------- 0.2. One verify.sh at a time on this Mac --------------------
# >>> VERIFY LOCK >>> — extracted between these markers and run by
# scripts/test_verify_lock.py. Keep the markers.
#
# Two runs at once corrupt each other, and not only through the image tag:
# at least six things here are shared by every run on a Mac — the
# quartz-teacher:dev-test image, 78 fixed /tmp/verify_*.log paths (some are
# grepped for PASS/FAIL), $HOME/.plantoir-verify-26:27 and its workspace,
# $HOME/.plantoir-verify-locked, and the prune fixtures. Two agents' gates
# running together on 2026-09-24 was how GitHub #280 was found. A per-run
# image tag was REJECTED: it fixes one of the six, breaks --skip-build (the
# tag it would reuse is deleted at the end), and makes every document that
# names quartz-teacher:dev-test wrong.
#
# A second run does not wait: it says who holds the lock and exits 1. A gate
# that silently queues hides the contention it is waiting on; one that fails
# at once says so. /tmp rather than $TMPDIR because sessions carry different
# TMPDIRs, and per user because /tmp is shared.
#
# The lock is a directory (mkdir is the atomic test) holding one file, the
# holder's pid, folder and start time. A lock with NO such file yet is HELD —
# its maker may be between mkdir and the write — and never taken over; a lock
# whose pid is gone is stale and is taken over, saying so. It is released on
# every exit, Ctrl-C, a kill and a hang-up included (`script` and pty.spawn
# send HUP when their parent goes), and only by the run whose pid is in it. A
# SIGKILL cannot be caught and leaves it behind: the refusal names the path.
# (Measured under /bin/bash 3.2: the EXIT trap alone already runs on INT,
# TERM and HUP — scripts/test_verify_lock.py passes with the three signal
# traps removed and fails with the EXIT trap removed. The three are kept so
# the exit status says which signal ended the run.)
VERIFY_LOCK="${PLANTOIR_VERIFY_LOCK:-/tmp/plantoir-verify-$(id -u).lock}"

release_verify_lock() {
  local holder=""
  if [[ -f "$VERIFY_LOCK/holder" ]]; then
    holder="$(cut -d' ' -f1 "$VERIFY_LOCK/holder" 2>/dev/null || true)"
  fi
  if [[ "$holder" == "$$" ]]; then
    rm -f "$VERIFY_LOCK/holder"
    rmdir "$VERIFY_LOCK" 2>/dev/null || true
  fi
}

take_verify_lock() {
  local holder_line holder_pid
  if ! mkdir "$VERIFY_LOCK" 2>/dev/null; then
    holder_line=""
    if [[ -f "$VERIFY_LOCK/holder" ]]; then
      holder_line="$(cat "$VERIFY_LOCK/holder" 2>/dev/null || true)"
    fi
    holder_pid="${holder_line%% *}"
    # A pause between reading the holder and acting on it, for
    # scripts/test_verify_lock.py only: it is how the takeover race is made
    # to happen every time rather than once in a thousand. Unset, nothing.
    if [[ -n "${PLANTOIR_VERIFY_LOCK_TEST_PAUSE:-}" ]]; then
      sleep "$PLANTOIR_VERIFY_LOCK_TEST_PAUSE"
    fi
    if [[ -n "$holder_pid" ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
      # Taken over under a second lock, so that two runs finding the same
      # dead holder cannot both win: without it, B's rmdir removed the new,
      # still-empty lock A had just made, and both held it. Inside, the
      # holder is read AGAIN and the lock is removed only if it still names
      # the dead run.
      local took_over="false"
      if mkdir "$VERIFY_LOCK.takeover" 2>/dev/null; then
        if [[ "$(cat "$VERIFY_LOCK/holder" 2>/dev/null || true)" == "$holder_line" ]]; then
          echo "🧹 A verify.sh that is no longer running (pid $holder_pid) left its lock behind; taking it over."
          rm -f "$VERIFY_LOCK/holder"
          rmdir "$VERIFY_LOCK" 2>/dev/null || true
          if mkdir "$VERIFY_LOCK" 2>/dev/null; then
            took_over="true"
          fi
        fi
        rmdir "$VERIFY_LOCK.takeover" 2>/dev/null || true
      fi
      if [[ "$took_over" != "true" ]]; then
        echo "❌ Another verify.sh took the lock at the same moment; run this one again when it has finished."
        echo "   If nothing is running, remove $VERIFY_LOCK (and $VERIFY_LOCK.takeover if it is there)."
        exit 1
      fi
    else
      echo "❌ Another verify.sh is already running on this Mac, and two at once corrupt each other."
      if [[ -n "$holder_pid" ]]; then
        echo "   Held by pid $holder_pid: ${holder_line#* }"
      else
        echo "   Its holder has not written its name yet."
      fi
      echo "   Run this one again when it has finished. If nothing is running, remove $VERIFY_LOCK"
      exit 1
    fi
  fi
  trap release_verify_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf '%s %s (started %s)\n' "$$" "$(pwd -P)" "$(date '+%Y-%m-%d %H:%M:%S')" > "$VERIFY_LOCK/holder"
}
# <<< VERIFY LOCK <<<
take_verify_lock

# -------------------- 0.5. Pure-Python unit tests (no Docker needed) --------------------
# Fast, dependency-free checks that don't need the image — run first so a
# broken script.py change fails in milliseconds instead of after a full
# Docker build.
# No .pyc files. `scripts/` is a folder reference in the app's project, so
# anything left in it is copied into the bundle, mirrored into every working
# folder's `.toolchain/`, and hashed into the image tag — which means a test run
# here would hand teachers a rebuild for bytecode. Windows' PythonToolchainTests
# sets the same variable.
export PYTHONDONTWRITEBYTECODE=1

if (cd scripts && python3 test_site_health.py) >/tmp/verify_site_health_test.log 2>&1; then
  pass "site_health.py: the checks, and the words they say (scripts/test_site_health.py)"
else
  fail "site_health.py: the checks, and the words they say (scripts/test_site_health.py)"
  cat /tmp/verify_site_health_test.log
fi

if (cd scripts && python3 test_recipe_folders.py) >/tmp/verify_recipe_folders_test.log 2>&1; then
  pass "the toolchain recipe's folder list agrees everywhere it is copied (scripts/test_recipe_folders.py)"
else
  fail "the toolchain recipe's folder list agrees everywhere it is copied (scripts/test_recipe_folders.py)"
  cat /tmp/verify_recipe_folders_test.log
fi

if (cd scripts && python3 test_starting_content_prompts.py) >/tmp/verify_starting_content_test.log 2>&1; then
  pass "setup_course.py: what a teacher who declined the ready-made pages is told, and what lands in the course (scripts/test_starting_content_prompts.py)"
else
  fail "setup_course.py: what a teacher who declined the ready-made pages is told, and what lands in the course (scripts/test_starting_content_prompts.py)"
  cat /tmp/verify_starting_content_test.log
fi

if (cd scripts && python3 test_graded_folders_rerun.py) >/tmp/verify_graded_rerun_test.log 2>&1; then
  pass "setup_course.py: a re-run writes a saved marks pool back as it was (scripts/test_graded_folders_rerun.py)"
else
  fail "setup_course.py: a re-run writes a saved marks pool back as it was (scripts/test_graded_folders_rerun.py)"
  cat /tmp/verify_graded_rerun_test.log
fi

if (cd scripts && python3 test_contracts.py) >/tmp/verify_contracts_test.log 2>&1; then
  pass "contracts.py: the scripts can read the Plantoir contract (scripts/test_contracts.py)"
else
  fail "contracts.py: the scripts can read the Plantoir contract (scripts/test_contracts.py)"
  cat /tmp/verify_contracts_test.log
fi

if (cd scripts && python3 test_deploy_netlify_headers.py) >/tmp/verify_deploy_headers_test.log 2>&1; then
  pass "deploy.py: Netlify ad-badge suppression (scripts/test_deploy_netlify_headers.py)"
else
  fail "deploy.py: Netlify ad-badge suppression (scripts/test_deploy_netlify_headers.py)"
  cat /tmp/verify_deploy_headers_test.log
fi

if (cd scripts && python3 test_netlify_badge.py) >/tmp/verify_netlify_badge_test.log 2>&1; then
  pass "netlify_badge.py: shared ad-badge suppression module (scripts/test_netlify_badge.py)"
else
  fail "netlify_badge.py: shared ad-badge suppression module (scripts/test_netlify_badge.py)"
  cat /tmp/verify_netlify_badge_test.log
fi

if bash scripts/test_build_output_link.sh >/tmp/verify_build_output_link_test.log 2>&1; then
  pass "the launchers keep built websites outside the working folder, for every state an existing folder can be in (scripts/test_build_output_link.sh)"
else
  fail "the launchers keep built websites outside the working folder, for every state an existing folder can be in (scripts/test_build_output_link.sh)"
  cat /tmp/verify_build_output_link_test.log
fi

if bash scripts/test_container_mount.sh >/tmp/verify_container_mount_test.log 2>&1; then
  pass "the launchers name a teacher's folder in a form that survives a colon in it, and all three use it (scripts/test_container_mount.sh)"
else
  fail "the launchers name a teacher's folder in a form that survives a colon in it, and all three use it (scripts/test_container_mount.sh)"
  cat /tmp/verify_container_mount_test.log
fi

if (cd scripts && python3 test_deploy_course_dir_resolution.py) >/tmp/verify_deploy_course_dir_test.log 2>&1; then
  pass "deploy.py: course directory resolution under a native build root (scripts/test_deploy_course_dir_resolution.py)"
else
  fail "deploy.py: course directory resolution under a native build root (scripts/test_deploy_course_dir_resolution.py)"
  cat /tmp/verify_deploy_course_dir_test.log
fi

if (cd scripts && python3 test_deploy_non_interactive.py) >/tmp/verify_deploy_non_interactive_test.log 2>&1; then
  pass "deploy: a publish nobody is there to answer questions for refuses rather than waiting or guessing (scripts/test_deploy_non_interactive.py)"
else
  fail "deploy: a publish nobody is there to answer questions for refuses rather than waiting or guessing (scripts/test_deploy_non_interactive.py)"
  cat /tmp/verify_deploy_non_interactive_test.log
fi

if (cd scripts && python3 test_reference_course.py) >/tmp/verify_reference_course_test.log 2>&1; then
  pass "a course kept for reference is never deployed, at every door the shared toolchain owns (scripts/test_reference_course.py)"
else
  fail "a course kept for reference is never deployed, at every door the shared toolchain owns (scripts/test_reference_course.py)"
  cat /tmp/verify_reference_course_test.log
fi

# RUNS deploy.sh, where the test above only reads it. That distinction is the
# reason this exists: the flag was written on a machine with no bash, and
# starting the script found two things in prompt_for_cf_account that reading it
# had not (GitHub issue #129). No Docker, no network, no credentials.
if (cd scripts && python3 test_deploy_sh_questions.py) >/tmp/verify_deploy_sh_questions_test.log 2>&1; then
  pass "deploy.sh: every question it can ask refuses under the flag, and is still asked without it (scripts/test_deploy_sh_questions.py)"
else
  fail "deploy.sh: every question it can ask refuses under the flag, and is still asked without it (scripts/test_deploy_sh_questions.py)"
  cat /tmp/verify_deploy_sh_questions_test.log
fi

# The same for preview.sh, which took --non-interactive on 2026-09-09 (GitHub
# issue #124) because a scheduled publish BUILDS before it publishes. Its own
# file rather than a class in the one above: this drives a different launcher,
# and the twin's completeness test only ever asks about deploy.sh's questions.
if (cd scripts && python3 test_preview_sh_questions.py) >/tmp/verify_preview_sh_questions_test.log 2>&1; then
  pass "preview.sh: the one question it can ask refuses under the flag, and is still asked without it (scripts/test_preview_sh_questions.py)"
else
  fail "preview.sh: the one question it can ask refuses under the flag, and is still asked without it (scripts/test_preview_sh_questions.py)"
  cat /tmp/verify_preview_sh_questions_test.log
fi

if (cd scripts && python3 test_port_blocks.py) >/tmp/verify_port_blocks_test.log 2>&1; then
  pass "the launchers walk forty blocks for a folder's preview addresses, skip any another folder holds, and say so truthfully when none is free (scripts/test_port_blocks.py)"
else
  fail "the launchers walk forty blocks for a folder's preview addresses, skip any another folder holds, and say so truthfully when none is free (scripts/test_port_blocks.py)"
  cat /tmp/verify_port_blocks_test.log
fi

if (cd scripts && python3 test_verify_lock.py) >/tmp/verify_lock_test.log 2>&1; then
  pass "verify.sh lets one run at a time hold this Mac, names the holder to a second, and lets go on every exit (scripts/test_verify_lock.py)"
else
  fail "verify.sh lets one run at a time hold this Mac, names the holder to a second, and lets go on every exit (scripts/test_verify_lock.py)"
  cat /tmp/verify_lock_test.log
fi

# preview.sh announces the address the app opens, or says it cannot and stops;
# it never announces a port it guessed (GitHub #235). Runs the launcher's own
# functions with docker answering as told, so it needs no Docker at all.
if (cd scripts && python3 test_preview_address.py) >/tmp/verify_preview_address_test.log 2>&1; then
  pass "preview.sh announces the preview's real address or stops, never a guessed one (scripts/test_preview_address.py)"
else
  fail "preview.sh announces the preview's real address or stops, never a guessed one (scripts/test_preview_address.py)"
  cat /tmp/verify_preview_address_test.log
fi

# preview.sh makes sure this Mac can reach the builder before it builds, and
# stops in seconds when every try is refused (GitHub #234). Runs the launcher's
# own functions with docker, curl and sleep answering as told — no Docker, no
# network, no waiting. The previews verify.sh runs are --build-only, which
# asks nothing, so none of them exercises the probe against a real forward;
# a serving preview checked by hand is that proof (documentation/03).
if (cd scripts && python3 test_preview_reach.py) >/tmp/verify_preview_reach_test.log 2>&1; then
  pass "preview.sh checks this Mac can reach the builder before building, and stops only on a refusal (scripts/test_preview_reach.py)"
else
  fail "preview.sh checks this Mac can reach the builder before building, and stops only on a refusal (scripts/test_preview_reach.py)"
  cat /tmp/verify_preview_reach_test.log
fi

if (cd scripts && python3 test_preflight_exclusions.py) >/tmp/verify_preflight_exclusions_test.log 2>&1; then
  pass "build_site.py: preflight excluded_items discovery skipping & index.md notes (scripts/test_preflight_exclusions.py)"
else
  fail "build_site.py: preflight excluded_items discovery skipping & index.md notes (scripts/test_preflight_exclusions.py)"
  cat /tmp/verify_preflight_exclusions_test.log
fi

# Issue #265: the build never changes `hidden`, the sidebar filter keeps the
# stored names, and an older section's filter is repaired.
if (cd scripts && python3 test_sidebar_hiding.py) >/tmp/verify_sidebar_hiding_test.log 2>&1; then
  pass "build_site.py: the build keeps hidden as saved, and the sidebar filter and its repair (scripts/test_sidebar_hiding.py)"
else
  fail "build_site.py: the build keeps hidden as saved, and the sidebar filter and its repair (scripts/test_sidebar_hiding.py)"
  cat /tmp/verify_sidebar_hiding_test.log
fi

# Issue #265: the build notes when it STARTED, so a Save made during a
# publish's build makes the next Publish build again.
if (cd scripts && python3 test_build_started_marker.py) >/tmp/verify_build_started_marker_test.log 2>&1; then
  pass "build_site.py: the build notes when it started, for the freshness check (scripts/test_build_started_marker.py)"
else
  fail "build_site.py: the build notes when it started, for the freshness check (scripts/test_build_started_marker.py)"
  cat /tmp/verify_build_started_marker_test.log
fi

# Issue #136: one rule for "this built site is a preview's" — deploy.sh's
# check and deploy.py's, run against contracts/app-rules.json ->
# buildFreshness.previewBuild, the cases the apps read too.
if (cd scripts && python3 test_preview_build_detection.py) >/tmp/verify_preview_build_detection_test.log 2>&1; then
  pass "deploy.sh and deploy.py call a site a preview's by every page, as the apps do (scripts/test_preview_build_detection.py)"
else
  fail "deploy.sh and deploy.py call a site a preview's by every page, as the apps do (scripts/test_preview_build_detection.py)"
  cat /tmp/verify_preview_build_detection_test.log
fi

if (cd scripts && python3 test_publishable_site.py) >/tmp/verify_publishable_site_test.log 2>&1; then
  pass "build_site.py: a build with no front page produces no site, and clears the last one (scripts/test_publishable_site.py)"
else
  fail "build_site.py: a build with no front page produces no site, and clears the last one (scripts/test_publishable_site.py)"
  cat /tmp/verify_publishable_site_test.log
fi

if (cd scripts && python3 test_class_pages.py) >/tmp/verify_class_pages_test.log 2>&1; then
  pass "class_pages.py: what a course calls a unit, and what the build counts as a class page (scripts/test_class_pages.py)"
else
  fail "class_pages.py: what a course calls a unit, and what the build counts as a class page (scripts/test_class_pages.py)"
  cat /tmp/verify_class_pages_test.log
fi

if (cd scripts && python3 test_club_start.py) >/tmp/verify_club_start_test.log 2>&1; then
  pass "setup_course.py: a club starts with its front page heading and a published first page, and keeps its recorded class folder (scripts/test_club_start.py)"
else
  fail "setup_course.py: a club starts with its front page heading and a published first page, and keeps its recorded class folder (scripts/test_club_start.py)"
  cat /tmp/verify_club_start_test.log
fi

if (cd scripts && python3 test_page_visibility.py) >/tmp/verify_page_visibility_test.log 2>&1; then
  pass "page_visibility.py: whether the built site shows a page, against contracts/file-formats.json (scripts/test_page_visibility.py)"
else
  fail "page_visibility.py: whether the built site shows a page, against contracts/file-formats.json (scripts/test_page_visibility.py)"
  cat /tmp/verify_page_visibility_test.log
fi

# Runs BEFORE the image build below, on purpose: it answers in a tenth of a
# second the question the image build answers in three minutes.
if (cd scripts && python3 test_baked_modules.py) >/tmp/verify_baked_modules_test.log 2>&1; then
  pass "every module a baked script imports is baked into the image too (scripts/test_baked_modules.py)"
else
  fail "every module a baked script imports is baked into the image too (scripts/test_baked_modules.py)"
  cat /tmp/verify_baked_modules_test.log
fi

if (cd scripts && python3 test_stop_preview.py) >/tmp/verify_stop_preview_test.log 2>&1; then
  pass "a build for publishing stops only THIS section's preview (scripts/test_stop_preview.py)"
else
  fail "a build for publishing stops only THIS section's preview (scripts/test_stop_preview.py)"
  cat /tmp/verify_stop_preview_test.log
fi

if (cd scripts && python3 test_stop_quietly.py) >/tmp/verify_stop_quietly_test.log 2>&1; then
  pass "pressing Cancel ends a build or a publish quietly, exit 130 and no traceback (scripts/test_stop_quietly.py)"
else
  fail "pressing Cancel ends a build or a publish quietly, exit 130 and no traceback (scripts/test_stop_quietly.py)"
  cat /tmp/verify_stop_quietly_test.log
fi

if (cd scripts && python3 test_config_write_race.py) >/tmp/verify_config_race_test.log 2>&1; then
  pass "a build and a rename writing course_config.json cannot erase each other (scripts/test_config_write_race.py)"
else
  fail "a build and a rename writing course_config.json cannot erase each other (scripts/test_config_write_race.py)"
  cat /tmp/verify_config_race_test.log
fi

# A preview build must never reach a published site, and the FOLDER
# destination is the one that can: it publishes host-side and never enters the
# container, so deploy.py's own refusal never runs. Structural rather than
# behavioural — a real preview-then-publish cycle would add minutes to every
# run of this script — but it catches the guard being deleted, which is how it
# came to be missing in the first place.
_folder_guard_ok=true
for _launcher in deploy.sh deploy.ps1; do
  if ! grep -q "ws://localhost:" "$_launcher"; then
    _folder_guard_ok=false
    echo "   $_launcher does not check for a preview build before publishing to a folder"
  fi
done
if [ "$_folder_guard_ok" = true ]; then
  pass "publishing to a folder refuses a preview build (deploy.sh and deploy.ps1)"
else
  fail "publishing to a folder refuses a preview build (deploy.sh and deploy.ps1)"
fi

# A course kept for reference is never deployed, and the FOLDER destination is
# the door that needs the launcher's own refusal: it publishes host-side and
# exits 0 before the container is started, so deploy.py's check never runs on
# that path. Exactly the shape of the guard above, and the same reason for
# checking it structurally — a missing guard here is a deploy that REPORTS
# SUCCESS on a frozen course, which is the worst direction this can fail in.
_reference_guard_ok=true
for _launcher in deploy.sh deploy.ps1; do
  # `ept_for_reference`, not the whole key: both launchers match the key
  # WIDENED — `"[^"]*ept_for_reference"` — so that a key written with
  # backslash-u escapes cannot slip past a text reader. Grepping for the
  # narrow spelling started failing the moment that landed, which is the
  # structural check doing its job on itself.
  if ! grep -q "ept_for_reference" "$_launcher"; then
    _reference_guard_ok=false
    echo "   $_launcher does not refuse a course that is kept for reference"
  fi
  if ! grep -q "REFERENCE_COURSE_REFUSAL" "$_launcher"; then
    _reference_guard_ok=false
    echo "   $_launcher carries no refusal sentence to say when it does"
  fi
done
if [ "$_reference_guard_ok" = true ]; then
  pass "a course kept for reference is refused before anything is published (deploy.sh and deploy.ps1)"
else
  fail "a course kept for reference is refused before anything is published (deploy.sh and deploy.ps1)"
fi

# And a course code that begins with a DOT is refused outright, in all four
# launchers. Plantoir builds a reference course under a hidden folder inside
# `courses/` and renames it into place as the last act; handed that hidden
# name, a launcher treated it as an ordinary course — the uppercased name
# still resolves on a case-insensitive volume — and during the copy there is
# no marker yet for the guard above to find. Structural for the same reason as
# the guard above: this is a door, and the app cannot reach it to test it.
_dot_guard_ok=true
for _launcher in deploy.sh preview.sh deploy.ps1 preview.ps1; do
  if ! grep -q "cannot begin with a dot" "$_launcher"; then
    _dot_guard_ok=false
    echo "   $_launcher does not refuse a course code beginning with a dot"
  fi
done
if [ "$_dot_guard_ok" = true ]; then
  pass "a course code beginning with a dot is refused (all four launchers)"
else
  fail "a course code beginning with a dot is refused (all four launchers)"
fi

# No launcher may hand a program to `docker exec` on stdin without -i. Without
# it, docker discards stdin: the program never arrives, the command exits 0
# with no output, and whatever it was meant to check silently never runs.
# preview.sh's timetable-section check had exactly that shape from 2025-08-11
# until 2026-09-23, and every preview printed "Could not read allowed
# sections" because of it (GitHub #224). A second hit here is another dead
# check, not a reason to narrow this.
_dead_heredocs="$(grep -nE 'docker exec [^|]*python3 - <<' setup.sh preview.sh deploy.sh | grep -v 'exec -i' || true)"
if [ -z "$_dead_heredocs" ]; then
  pass "no launcher feeds a program to docker exec without -i (it would never run)"
else
  fail "a launcher feeds a program to docker exec without -i, so it never runs"
  echo "$_dead_heredocs"
fi

# No temporary-file template may carry anything after its X's. macOS mktemp
# fills in only TRAILING X's: with a suffix the name is used exactly as
# written, so the first run succeeds, and the second — or any run after one
# that was stopped before tidying up, or a second worktree running at the same
# time — dies with "File exists". verify.sh's prune check had exactly that
# shape until 2026-09-25 (GitHub #273). The list is every TRACKED shell file,
# not a hand list, because the next copy will be somewhere nobody thought to
# look; an empty list fails rather than passing having read nothing.
_tracked_shell_files="$(git ls-files -- '*.sh' .githooks 2>/dev/null || true)"
if [ -z "$_tracked_shell_files" ]; then
  fail "could not list the tracked shell files to check their temporary-file names"
else
  _literal_temp_names="$(git ls-files -z -- '*.sh' .githooks \
    | xargs -0 grep -nE 'mktemp[^|;]*X{3,}[^X"[:space:])]' || true)"
  if [ -z "$_literal_temp_names" ]; then
    pass "every temporary-file template ends in its X's (none is used literally)"
  else
    fail "a temporary-file template has text after its X's, so its name is fixed"
    echo "$_literal_temp_names"
  fi
fi

# Nothing may have left bytecode behind. PYTHONDONTWRITEBYTECODE above stops
# the runs in THIS script, but `scripts/` is a folder reference in the app's
# project — whatever sits in it is copied into the bundle, mirrored into every
# working folder's `.toolchain/`, and hashed into the image tag. A `.pyc` there
# hands teachers a rebuild for nothing, and `.gitignore` hides it from `git
# status`, so a hand-run test that littered would never be noticed. Ten of them
# were found in a working folder's `.toolchain/` on 2026-09-09, mirrored from a
# bundle that had been carrying them for some time. The app's own
# `copyToolchainFiles` removes extraneous files, so a clean bundle heals a
# folder on the next touch; this keeps the bundle clean.
if [ -z "$(find scripts -name '__pycache__' -print -quit 2>/dev/null)" ]; then
  pass "no bytecode left in scripts/, which ships inside the app"
else
  fail "scripts/__pycache__ exists — it would be copied into the app bundle, mirrored into every working folder's .toolchain/, and change the image tag"
  find scripts -name '__pycache__' -print
  echo "   Remove it and run again:  rm -rf scripts/__pycache__"
  echo "   It gets there from running a test file BY HAND — this script exports"
  echo "   PYTHONDONTWRITEBYTECODE, a bare 'python3 scripts/test_x.py' does not,"
  echo "   and importing the module under test is what writes the .pyc."

fi

# -------------------- 1. Container runtime (shared Colima) --------------------
# Maintainer variant: assumes Colima and the Docker CLI are installed (the
# teacher-facing launchers handle installation). Never stops a running VM.
if ! docker info >/dev/null 2>&1; then
  if ! command -v colima >/dev/null 2>&1; then
    echo "❌ No running Docker engine and Colima is not installed."
    echo "   Install with: brew install colima docker"
    exit 1
  fi
  echo "▶️  Starting Colima…"
  colima start
  for _ in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 2
  done
fi
if docker info >/dev/null 2>&1; then
  pass "Container runtime is up (context: $(docker context show 2>/dev/null || echo '?'))"
else
  fail "Container runtime did not become ready"
  echo "   Try: colima status && colima stop --force && colima start"
  exit 1
fi

# -------------------- Preconditions --------------------
if [[ ! -d "courses/EXC2O" || ! -f "courses/EXC2O/course_config.json" ]]; then
  fail "Test fixture courses/EXC2O is missing"
  echo "   The Example Course is required. Install it via ./setup.sh (answer 'y'"
  echo "   to the Example Course prompt) or copy support/example_course/EXC2O to courses/."
  exit 1
fi

# -------------------- 2. Build the dev-test image --------------------
if [[ "$SKIP_BUILD" == "true" ]] && docker image inspect "$DEV_TEST_IMAGE" >/dev/null 2>&1; then
  pass "Reusing existing image $DEV_TEST_IMAGE (--skip-build)"
else
  echo ""
  echo "🧱 Building $DEV_TEST_IMAGE from ./Dockerfile ${NO_CACHE:+(no cache)}…"
  # The Dockerfile uses a BuildKit heredoc (RUN cat <<'EOF'), which the legacy
  # builder silently mishandles (it produced an EMPTY export-scripts file).
  # The launchers build with buildx, so verify must too, to stay representative.
  if docker buildx version >/dev/null 2>&1; then
    BUILD_CMD=(docker buildx build --load)
  else
    BUILD_CMD=(env DOCKER_BUILDKIT=1 docker build)
  fi
  if "${BUILD_CMD[@]}" $NO_CACHE -t "$DEV_TEST_IMAGE" .; then
    pass "Image built: $DEV_TEST_IMAGE (BuildKit)"
  else
    fail "docker build failed"
    exit 1
  fi
fi

# ---- build_site.py: which folders count for marks ----
echo ""
echo "🔎 Checking build_site.py's graded-folder rule against the shared contract…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/test_graded_folders.py" /opt/scripts/test_graded_folders.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_graded_folders.py >/tmp/verify_graded_test.log 2>&1; then
  pass "build_site.py: graded-folder rule matches contracts/shared-rules.json (scripts/test_graded_folders.py)"
else
  fail "build_site.py: graded-folder rule matches contracts/shared-rules.json (scripts/test_graded_folders.py)"
  cat /tmp/verify_graded_test.log
fi

# ---- build_site.py: the class-folder rule, against the SHARED contract ----
# Same reason as the domain test below: build_site.py imports `frontmatter`,
# which lives only inside the container. This one ALSO needs the contract, and
# reads it from the image's own /opt/contracts — which is the end-to-end check
# that the contract really travels with the toolchain, not just that the rule
# is right.
echo ""
echo "🔎 Checking build_site.py's class-folder rule against the shared contract…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/test_class_folder.py" /opt/scripts/test_class_folder.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_class_folder.py >/tmp/verify_class_folder_test.log 2>&1; then
  pass "build_site.py: class-folder rule matches contracts/class-planning.json (scripts/test_class_folder.py)"
else
  fail "build_site.py: class-folder rule matches contracts/class-planning.json (scripts/test_class_folder.py)"
  cat /tmp/verify_class_folder_test.log
fi

# ---- build_site.py: pages take their class's date, in the teacher's files ----
# The front page and every page a visible class brings (#275, #276), run
# against the shared contract in the image for the same reason as above — and
# every case built TWICE, because a second build that rewrote anything would
# make every publish build once more (#265).
echo ""
echo "🔎 Checking that pages take their class's date, against the shared contract…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/test_dates_follow_the_class.py" /opt/scripts/test_dates_follow_the_class.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_dates_follow_the_class.py >/tmp/verify_dates_follow_the_class_test.log 2>&1; then
  pass "build_site.py: the front page and linked pages take their class's date, per section (scripts/test_dates_follow_the_class.py)"
else
  fail "build_site.py: the front page and linked pages take their class's date, per section (scripts/test_dates_follow_the_class.py)"
  cat /tmp/verify_dates_follow_the_class_test.log
fi

# ---- build_site.py: a page whose settings cannot be read is hidden ----
# GitHub #246. Every case in contracts/shared-rules.json ->
# unreadablePageSettings through the real process_frontmatter, in the image
# because it needs python-frontmatter: hidden, named with its line, its body
# kept, the teacher's file untouched, and an unreadable front page clearing
# the last site and saying so in its own words.
echo ""
echo "🔎 Checking that a page whose settings cannot be read is hidden and named…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/test_unreadable_page_settings.py" /opt/scripts/test_unreadable_page_settings.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_unreadable_page_settings.py >/tmp/verify_unreadable_page_settings_test.log 2>&1; then
  pass "build_site.py: a page whose settings cannot be read is hidden and named (scripts/test_unreadable_page_settings.py)"
else
  fail "build_site.py: a page whose settings cannot be read is hidden and named (scripts/test_unreadable_page_settings.py)"
  cat /tmp/verify_unreadable_page_settings_test.log
fi

# ---- Whether the site shows a page: the contract, run down the REAL chain ----
# The one check here that is not about a rule being implemented right — it is
# about the rule being TRUE. Both apps are tested against
# contracts/file-formats.json -> pageVisibility.readingCases, so if that list
# is wrong they are confidently wrong together and every suite stays green.
# This runs each case through process_frontmatter (python-frontmatter, PyYAML)
# and then through the image's OWN gray-matter/js-yaml on JSON_SCHEMA plus
# patches/publish.ts's expression — which is exactly what Quartz v4.5.0 does.
# So a PyYAML bump, a Quartz bump or a rewritten patch cannot move the table
# without this failing.
echo ""
echo "🔎 Checking the visibility contract against what the real build does…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/check_visibility_against_the_site.py" /opt/scripts/check_visibility_against_the_site.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/check_visibility_against_the_site.py \
  >/tmp/verify_visibility_site.log 2>&1; then
  pass "every pageVisibility reading case agrees with the built site (scripts/check_visibility_against_the_site.py)"
else
  fail "every pageVisibility reading case agrees with the built site (scripts/check_visibility_against_the_site.py)"
  cat /tmp/verify_visibility_site.log
fi

# ---- The date and title writers, against what the site reads ----
# GitHub #199. `contracts/file-formats.json` -> `datesAndTitles.writingCases`
# says what the built site reads from each page a writer produces; this runs
# every `after` through the real process_frontmatter so that stays true.
echo ""
echo "🔎 Checking the date and title writing cases against what the real build reads…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/check_dates_and_titles_against_the_site.py" /opt/scripts/check_dates_and_titles_against_the_site.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/check_dates_and_titles_against_the_site.py \
  >/tmp/verify_dates_titles_site.log 2>&1; then
  pass "every datesAndTitles writing case reads on the site as the contract says (scripts/check_dates_and_titles_against_the_site.py)"
else
  fail "every datesAndTitles writing case reads on the site as the contract says (scripts/check_dates_and_titles_against_the_site.py)"
  cat /tmp/verify_dates_titles_site.log
fi

# ---- The sidebar's hide rule, against the REAL Quartz file tree ----
# Issue #265. Every `file-formats.json` -> `sidebarHiding.matchRule` case is
# run through Quartz 4.5's own FileTrieNode with the filter text the build
# writes, rebuilt from that text the way the page does in the browser. Needs
# Node and Quartz's sources, which only the image has — so it is here and
# not a `test_` file (Windows' Python suite has neither).
echo ""
echo "🔎 Checking the sidebar's hide rule against the real Quartz file tree…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/check_sidebar_hiding_against_the_site.py" /opt/scripts/check_sidebar_hiding_against_the_site.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/check_sidebar_hiding_against_the_site.py \
  >/tmp/verify_sidebar_hiding.log 2>&1; then
  pass "every sidebarHiding.matchRule case agrees with the real Quartz file tree (scripts/check_sidebar_hiding_against_the_site.py)"
else
  fail "every sidebarHiding.matchRule case agrees with the real Quartz file tree (scripts/check_sidebar_hiding_against_the_site.py)"
  cat /tmp/verify_sidebar_hiding.log
fi

# ---- build_site.py: custom-domain resolution follows the primary destination ----
# Needs the real image, not a host run — build_site.py imports `frontmatter`,
# which lives only inside the container (see Dockerfile's `pip install`), so
# this cannot join the fast host-side pre-checks above. The test file itself
# is mounted in rather than baked into the image — it is dev-only, and the
# image should not carry test fixtures a teacher's build never needs.
echo ""
echo "🔎 Checking build_site.py's custom-domain resolution against the real image…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/test_build_site_domain_resolution.py" /opt/scripts/test_build_site_domain_resolution.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_build_site_domain_resolution.py >/dev/null 2>&1; then
  pass "build_site.py: custom-domain resolution follows the primary destination (scripts/test_build_site_domain_resolution.py)"
else
  fail "build_site.py: custom-domain resolution follows the primary destination (scripts/test_build_site_domain_resolution.py)"
fi

# -------------------- 3. export-scripts fidelity --------------------
# NOTE: must live under $HOME — Colima's VM only shares the home directory,
# so a /var/folders/... temp dir would silently arrive empty in the container.

# ---- Every helper a launcher calls must be defined in that same file ----
# The launchers are three standalone scripts sharing copied helper blocks,
# so a helper added to two of them but not the third fails only at runtime
# — and only on the code path that calls it. (setup.sh once called
# run_container_with_mount while only preview.sh and deploy.sh defined it:
# exit 127 at the first fresh course creation, missed by every other check.)
echo ""
echo "🔎 Cross-checking helper functions in the launchers…"
ALL_HELPERS="$(grep -hoE '^[a-z_][a-z0-9_]*\(\)' setup.sh preview.sh deploy.sh | tr -d '()' | sort -u)"
HELPERS_OK="true"
for f in setup.sh preview.sh deploy.sh; do
  # Comments stripped, and only command-position uses count — a helper's
  # name inside an echoed sentence is prose, not a call.
  UNCOMMENTED="$(sed -e 's/^[[:space:]]*#.*$//' "$f")"
  for fn in $ALL_HELPERS; do
    if echo "$UNCOMMENTED" | grep -qE "(^[[:space:]]*(if |elif |while |until )?!?[[:space:]]*|\\$\(|&&[[:space:]]*|\|\|[[:space:]]*)${fn}([[:space:]]|;|\)|$)"; then
      if ! grep -qE "^[[:space:]]*${fn}\(\)" "$f"; then
        HELPERS_OK="false"
        fail "$f calls ${fn} but never defines it (would exit 127 at runtime)"
      fi
    fi
  done
done
if [[ "$HELPERS_OK" == "true" ]]; then
  pass "Every helper called in a launcher is defined in that launcher"
fi

EXPORT_TMP="$(mktemp -d "$(pwd)/.verify-export.XXXXXX")"
echo ""
echo "📤 Testing 'export-scripts' → $EXPORT_TMP"
if docker run --rm --mount "$(bind_mount_argument "$EXPORT_TMP" /out)" "$DEV_TEST_IMAGE" export-scripts >/dev/null; then
  EXPORT_OK="true"
  for f in setup.sh preview.sh deploy.sh; do
    if ! cmp -s "$f" "$EXPORT_TMP/$f"; then
      EXPORT_OK="false"
      fail "Exported $f differs from repo copy (stale image?)"
    fi
  done
  for f in setup.bat preview.bat deploy.bat setup.ps1 preview.ps1 deploy.ps1; do
    if [[ ! -f "$EXPORT_TMP/$f" ]]; then
      EXPORT_OK="false"
      fail "Exported $f is missing"
    elif ! grep -q $'\r' "$EXPORT_TMP/$f"; then
      EXPORT_OK="false"
      fail "Exported $f lacks CRLF line endings (unix2dos step broken?)"
    fi
  done
  [[ "$EXPORT_OK" == "true" ]] && pass "export-scripts emits current launchers (CRLF intact on Windows files)"
else
  fail "export-scripts did not run"
fi
rm -rf "$EXPORT_TMP"

# ---------- 3c. Superseded builder images are removed, and ONLY those ----------
# The launchers mint a new 'teaching-quartz:src-<hash>' tag on every recipe
# change, so without this the orphans accumulate forever. The danger is the
# opposite one: Docker here is SHARED with other projects, so a cleanup that
# reached past its own tags would delete somebody else's images. This drives
# the launcher's REAL function (extracted from preview.sh, not retyped) against
# throwaway fixtures standing in for each case.
echo ""
echo "🔎 Checking that a new build removes superseded builder images…"
# The X's must END the template: macOS mktemp fills in only trailing X's, and
# with anything after them the name is used as written — so a second run, or
# any run after a stopped one, died here on "File exists" (GitHub #273).
# `source` below needs no extension.
PRUNE_SRC="$(mktemp "${TMPDIR:-/tmp}/verify_prune.XXXXXX")"
awk '/^prune_superseded_images\(\) \{/,/^\}/' preview.sh > "$PRUNE_SRC"
# The three launchers are standalone scripts sharing hand-copied helper blocks,
# and the cross-check above only proves each NAME is defined — not that the
# three bodies still say the same thing. Testing preview.sh's copy while
# setup.sh's has drifted would be a green suite over a real difference.
PRUNE_COPIES_MATCH="true"
for f in setup.sh deploy.sh; do
  if ! awk '/^prune_superseded_images\(\) \{/,/^\}/' "$f" | cmp -s - "$PRUNE_SRC"; then
    fail "prune_superseded_images() in $f differs from the copy in preview.sh"
    PRUNE_COPIES_MATCH="false"
  fi
done
[[ "$PRUNE_COPIES_MATCH" == "true" ]] && pass "prune_superseded_images() is identical in all three launchers"

if [[ ! -s "$PRUNE_SRC" ]]; then
  fail "Could not extract prune_superseded_images() from preview.sh"
else
  # shellcheck source=/dev/null
  source "$PRUNE_SRC"

  PRUNE_KEEP="teaching-quartz:src-verifykeep"
  PRUNE_OLD="teaching-quartz:src-verifyold"
  PRUNE_INUSE="teaching-quartz:src-verifyinuse"
  PRUNE_OTHER="verify-other-project:latest"
  PRUNE_CONTAINER="verify-prune-inuse"

  # Distinct image IDs matter: tags sharing one ID cannot tell these cases
  # apart, because 'docker rmi <tag>' on a shared ID only untags.
  prune_fixture_image() {
    printf 'FROM scratch\nLABEL ca.russellgordon.verify=%s\n' "$2" \
      | command docker buildx build --load -q -t "$1" - >/dev/null 2>&1
  }
  prune_image_exists() { command docker image inspect "$1" >/dev/null 2>&1; }

  command docker rm -f "$PRUNE_CONTAINER" >/dev/null 2>&1 || true
  prune_fixture_image "$PRUNE_KEEP"  keep
  prune_fixture_image "$PRUNE_OLD"   old
  prune_fixture_image "$PRUNE_INUSE" inuse
  prune_fixture_image "$PRUNE_OTHER" other
  # An explicit command is required even though this container never runs:
  # 'docker create' refuses an image with no entrypoint, and a container that
  # was never created would make the in-use case pass vacuously.
  if ! command docker create --name "$PRUNE_CONTAINER" "$PRUNE_INUSE" /noop >/dev/null 2>&1; then
    fail "prune: could not create the fixture container — the in-use case was not exercised"
  fi
  # The cases below that assert an image SURVIVED cannot pass vacuously — a
  # fixture that failed to build fails them. The case that proves pruning
  # HAPPENS is an absence, so it can; prove the fixture exists first.
  if ! prune_image_exists "$PRUNE_OLD"; then
    fail "prune: fixture $PRUNE_OLD was never built — the removal case proves nothing"
  fi

  # Two stubs, in place only while the real function runs.
  #
  # 'docker' scopes the IMAGE LISTING to this test's own fixtures. Without it,
  # sourcing the real function and calling it for effect would delete the
  # maintainer's genuine 'teaching-quartz:src-*' images as a side effect of
  # running verify.sh — a multi-minute, network-dependent rebuild in every
  # working folder, from a command whose banner promises only to check things.
  # The trade-off, stated plainly: '--filter reference=' is stubbed out and so
  # is not itself covered. 'verify-other-project:latest' sits in the listing
  # precisely so the second filter — the in-function prefix test, which runs on
  # this machine's own data — still has to do its job. The ancestor check, the
  # age check and the rmi all run unmodified against the real daemon.
  #
  # It also rewrites the AGE column, which is otherwise untestable: every
  # fixture is seconds old, so the real guard would spare all of them and the
  # removal case could never fire. Setting the age at either extreme tests the
  # rule in both directions instead of neutralising it.
  prune_stub_docker() {
    docker() {
      if [[ "${1:-}" == "images" ]]; then
        command docker "$@" \
          | grep -E "^(teaching-quartz:src-verify|verify-other-project:)" \
          | sed -E "s/^([^ ]+) .*/\\1 $PRUNE_STUB_AGE/" || true
      else
        command docker "$@"
      fi
    }
  }
  prune_unstub() { unset -f docker; }

  PRUNE_OK="true"

  # (a) Everything is too NEW — the age guard must spare it all.
  PRUNE_STUB_AGE="2 hours ago"
  prune_stub_docker; prune_superseded_images "$PRUNE_KEEP"; prune_unstub
  if ! prune_image_exists "$PRUNE_OLD"; then
    fail "prune: $PRUNE_OLD was removed despite being only hours old — the age guard is not working, and it is what protects a folder that is mid-recreate"
    PRUNE_OK="false"
  fi

  # (b) The tag just built is not one of ours (--image override) — refuse
  #     to touch anything, rather than treating every real tag as superseded.
  PRUNE_STUB_AGE="3 weeks ago"
  prune_stub_docker; prune_superseded_images "quartz-teacher:dev-test"; prune_unstub
  if ! prune_image_exists "$PRUNE_OLD"; then
    fail "prune: an --image override deleted $PRUNE_OLD — with a foreign keep-tag the function must do nothing at all"
    PRUNE_OK="false"
  fi

  # (c) The real case: superseded, old enough, unreferenced.
  PRUNE_STUB_AGE="3 weeks ago"
  prune_stub_docker; prune_superseded_images "$PRUNE_KEEP"; prune_unstub
  if prune_image_exists "$PRUNE_OLD"; then
    fail "prune: superseded tag $PRUNE_OLD was NOT removed"
    PRUNE_OK="false"
  fi
  if ! prune_image_exists "$PRUNE_KEEP"; then
    fail "prune: the tag just built ($PRUNE_KEEP) was removed"
    PRUNE_OK="false"
  fi
  if ! prune_image_exists "$PRUNE_INUSE"; then
    fail "prune: $PRUNE_INUSE was removed while a container still referenced it"
    PRUNE_OK="false"
  fi
  if ! prune_image_exists "$PRUNE_OTHER"; then
    fail "prune: removed $PRUNE_OTHER — another project's image is not ours to delete"
    PRUNE_OK="false"
  fi
  [[ "$PRUNE_OK" == "true" ]] && pass "Superseded builder images are removed; the current tag, an in-use tag, a recently-built tag, another project's image, and everything under an --image override are left alone"

  command docker rm -f "$PRUNE_CONTAINER" >/dev/null 2>&1 || true
  for t in "$PRUNE_KEEP" "$PRUNE_OLD" "$PRUNE_INUSE" "$PRUNE_OTHER"; do
    command docker rmi -f "$t" >/dev/null 2>&1 || true
  done
  unset -f prune_superseded_images prune_fixture_image prune_image_exists \
           prune_stub_docker prune_unstub
fi
rm -f "$PRUNE_SRC"

# -------------------- 4. Baked files match the working tree --------------------
echo ""
echo "🔬 Comparing files baked into the image against the working tree…"
BAKED_OK="true"
check_baked() {
  local repo_path="$1" image_path="$2"
  if ! docker run --rm --mount "$(bind_mount_argument "$(pwd)" /repo),readonly" "$DEV_TEST_IMAGE" cmp -s "/repo/$repo_path" "$image_path"; then
    BAKED_OK="false"
    fail "Image file $image_path differs from repo $repo_path"
  fi
}
check_baked scripts/contracts.py          /opt/scripts/contracts.py
check_baked scripts/site_health.py        /opt/scripts/site_health.py
# The contract itself must be IN the image: the container's only bind mount is
# `courses`, so a rule the scripts read has nowhere else to come from. One file
# stands for the directory — the Dockerfile copies it wholesale.
check_baked contracts/class-planning.json /opt/contracts/class-planning.json
check_baked scripts/page_visibility.py    /opt/scripts/page_visibility.py
check_baked scripts/setup_course.py       /opt/scripts/setup_course.py
check_baked scripts/build_site.py         /opt/scripts/build_site.py
check_baked scripts/deploy.py             /opt/scripts/deploy.py
check_baked scripts/netlify_badge.py      /opt/scripts/netlify_badge.py
check_baked patches/Explorer.tsx          /opt/quartz/quartz/components/Explorer.tsx
check_baked patches/FolderContent.tsx     /opt/quartz/quartz/components/pages/FolderContent.tsx
check_baked patches/explorer.inline.ts    /opt/quartz/quartz/components/scripts/explorer.inline.ts
# Head.tsx carries the <link rel="icon"> tags, so a stale copy in the image is
# how a site would quietly go back to wearing the Quartz logo.
check_baked patches/Head.tsx              /opt/quartz/quartz/components/Head.tsx
check_baked support/Backlinks.tsx         /opt/support/Backlinks.tsx
check_baked support/colour_schemes.json   /opt/support/colour_schemes.json
check_baked support/favicon/favicon.ico   /opt/support/favicon/favicon.ico
check_baked support/favicon/icon.svg      /opt/support/favicon/icon.svg
check_baked support/favicon/apple-touch-icon.png /opt/support/favicon/apple-touch-icon.png
check_baked support/favicon/icon.png      /opt/support/favicon/icon.png
[[ "$BAKED_OK" == "true" ]] && pass "Baked scripts, patches, and support files match the working tree"

# -------------------- 4b. The hide filter must be IN THE IMAGE --------------------
# The Explorer's filterFn is what makes a teacher's hidden pages hidden, and
# build_site.py can only rewrite the omit Set inside it — never create it. It
# used to be patched into a RUNNING container by setup_course.py, which meant
# any container recreation silently published Private Notes, Curriculum and
# Learning Goals. Asserted against the IMAGE on purpose: a check that ran in a
# long-lived container would have passed throughout the whole time this was
# broken.
#
# Structural, not a bare substring grep (tightened 2026-08-23 after an
# adversarial review of this fix): the marker comment proves nothing on its
# own if it has drifted away from the `omit` Set it documents — a file can
# contain the literal string CQ4T-OMIT-ANCHOR while nothing wires the hidden
# list into `filterFn`. `-Pzo` treats the whole file as one NUL-terminated
# record so the match can span the single newline between the marker's own
# line and the `const omit =` line it must sit directly above — deliberately
# NOT `.` matching across arbitrary further lines, which would let an anchor
# "match" a Set pages of unrelated code away and defeat the point of asking.
# The same adjacency `build_site.py`'s `_anchor_is_structurally_wired` now
# requires — read that function's comment before touching either.
echo ""
echo "🔎 Checking the Explorer's hide filter is baked into the image, and wired to a live omit Set…"
ANCHOR_OK="true"
for layout in /opt/quartz/quartz.layout.ts /opt/quartz-site/quartz.layout.ts; do
  if ! docker run --rm "$DEV_TEST_IMAGE" grep -Pzoq '//[ \t]*CQ4T-OMIT-ANCHOR:[^\n]*\n[ \t]*const[ \t]+omit[ \t]*=[ \t]*new[ \t]+Set' "$layout" 2>/dev/null; then
    fail "The Explorer's hide filter is missing or structurally detached from $layout in the image — hidden pages would be published"
    ANCHOR_OK="false"
  fi
done
[[ "$ANCHOR_OK" == "true" ]] && pass "The Explorer's hide filter is baked into the image and wired to a live omit Set (both Quartz copies)"

# -------------------- 5. Drive the real launcher against the image --------------------
echo ""
echo "🧹 Removing existing '$CONTAINER_NAME' container so the launcher recreates it"
echo "   from ${DEV_TEST_IMAGE}…"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

STAMP_FILE="$(mktemp -t cq4t-stamp)"
echo ""
echo "🚦 Running: ./preview.sh EXC2O 1 --image $DEV_TEST_IMAGE --full-rebuild --build-only"
echo "   (full rebuild ensures the Quartz scaffold comes from the dev-test image)"
echo ""
if ./preview.sh EXC2O 1 --image "$DEV_TEST_IMAGE" --full-rebuild --build-only; then
  pass "preview.sh completed against $DEV_TEST_IMAGE"
else
  fail "preview.sh exited non-zero"
fi

# -------------------- 6. Post-flight checks --------------------
SITE_PUBLIC="courses/EXC2O/.merged_output/section1/public"
SITE_INDEX="$SITE_PUBLIC/index.html"
if [[ -f "$SITE_INDEX" && "$SITE_INDEX" -nt "$STAMP_FILE" ]]; then
  pass "Built site is present and freshly generated ($SITE_INDEX)"
else
  fail "Built site missing or stale at $SITE_INDEX"
fi
rm -f "$STAMP_FILE"

# -------------------- 6a. The built site is OUTSIDE the working folder ------
# The site above was read through `courses/EXC2O/.merged_output`, which is a
# LINK. Checked here because every other check in this file would pass just as
# happily with a real folder in the old place — and the whole point of the
# change is that the bytes are not in the working folder any more.
EXPECTED_BUILD_ROOT="${HOME%/}/Library/Application Support/Plantoir/builds/$(pwd -P | shasum -a 256 | cut -c1-8)"
LINK_TARGET="$(readlink courses/EXC2O/.merged_output 2>/dev/null || true)"
if [[ -L "courses/EXC2O/.merged_output" && "$LINK_TARGET" == "$EXPECTED_BUILD_ROOT/EXC2O" ]]; then
  pass "The built site is kept outside the working folder ($LINK_TARGET)"
else
  fail "courses/EXC2O/.merged_output is not a link to $EXPECTED_BUILD_ROOT/EXC2O (it is: ${LINK_TARGET:-a real folder})"
fi

# -------------------- 6b. The site wears Plantoir's icon, not Quartz's --------------------
# Two halves that fail independently: the FILES have to be emitted (static/ by
# the Static emitter, the root copy by the Assets emitter out of content/), and
# the PAGE has to link them. A site can have all four files and still show the
# Quartz logo if Head.tsx did not make it into the image.
if [[ -f "$SITE_INDEX" ]]; then
  ICON_OK="true"
  for asset in static/icon.svg static/favicon.ico static/apple-touch-icon.png static/icon.png favicon.ico; do
    if [[ ! -f "$SITE_PUBLIC/$asset" ]]; then
      fail "Built site is missing $asset"
      ICON_OK="false"
    fi
  done
  # The root favicon.ico and quartz/static/icon.png must be OURS, byte for byte.
  # Note what this does NOT prove: build_site.py looks for support/favicon
  # relative to the container's WORKDIR before /opt/support/favicon, and when
  # verify.sh runs, that WORKDIR *is* this repo — so these two lines compare
  # the working tree with itself. What proves the IMAGE carries the right
  # bytes is the four check_baked lines above; a teacher's working folder has
  # .toolchain/support rather than support/, so it correctly falls through to
  # the baked copy.
  for pair in "favicon.ico:favicon.ico" "static/icon.png:icon.png"; do
    built="$SITE_PUBLIC/${pair%%:*}"
    source_file="support/favicon/${pair##*:}"
    if [[ -f "$built" ]] && ! cmp -s "$built" "$source_file"; then
      fail "$built is not $source_file — the site is carrying a different icon"
      ICON_OK="false"
    fi
  done
  for needle in 'static/icon.svg' 'static/favicon.ico' 'apple-touch-icon'; do
    if ! grep -q "$needle" "$SITE_INDEX"; then
      fail "index.html does not link $needle"
      ICON_OK="false"
    fi
  done
  [[ "$ICON_OK" == "true" ]] && pass "Built site carries and links the Plantoir icon (tab, root, Apple touch)"
fi

# -------------------- 6c. An existing teacher's container is recreated ------
# Every container that exists today was made WITHOUT the builds mount, and a
# mount cannot be added to a container that already exists — so the launcher
# has to notice and recreate it. Nothing else here exercises that branch: the
# run above starts by REMOVING the container, so the launcher always takes the
# create-from-new path. This puts a teacher's container back, deliberately
# without the mount, and asks the launcher to cope.
echo ""
echo "🚦 Putting back a container made WITHOUT the builds mount, the way every"
echo "   existing teacher's is, and building again…"
# Cleared first, so the check after this section can never read a log left by
# an earlier run.
rm -f /tmp/verify_old_container.log
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
# No published ports: this stand-in only has to EXIST without the builds
# mount, and the launcher replaces it before anything serves. Publishing
# 8081-8084 here would fail whenever a real preview is running on this Mac —
# which is the very situation the launcher's own free-port search exists to
# cope with — and would have read as a fault in the code under test.
#
# The `-v` below is DELIBERATE and must stay — it is the only one left in this
# file. This stand-in exists to be an EXISTING teacher's container, and every
# one of those was made with `-v`; writing it the new way would quietly stop
# testing that an updated launcher accepts an old container (measured: it
# does, both directions, because the two forms produce identical `.Mounts`).
if docker run -dit --name "$CONTAINER_NAME" \
     -v "$(pwd)/courses":/teaching/courses \
     "$DEV_TEST_IMAGE" tail -f /dev/null >/dev/null 2>&1; then
  if ./preview.sh EXC2O 1 --image "$DEV_TEST_IMAGE" --build-only >/tmp/verify_old_container.log 2>&1; then
    pass "a build in a container made before the builds mount existed still works"
  else
    fail "a build in a container made before the builds mount existed FAILED"
    tail -30 /tmp/verify_old_container.log
  fi
  if docker inspect -f '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$CONTAINER_NAME" 2>/dev/null \
       | grep -Fxq "$EXPECTED_BUILD_ROOT"; then
    pass "and the container was recreated WITH the builds mount"
  else
    fail "the container still has no builds mount, so the link dangles inside it"
  fi
  # WHICH branch did it. The mount check above also passes if the launcher
  # recreated for some OTHER reason — a courses mount that did not match, say —
  # in which case this section would be reporting a pass for the wrong work and
  # the branch it exists to exercise would still be untested.
  if grep -q "so built websites can be kept outside" /tmp/verify_old_container.log; then
    pass "and it recreated it because the builds mount was missing, not for some other reason"
  else
    fail "the container was recreated, but not by the missing-builds-mount branch this checks"
  fi
  if [[ -f "$SITE_INDEX" ]]; then
    pass "and the site is still readable at the path every reader names"
  else
    fail "the site is gone from $SITE_INDEX after the recreate"
  fi
else
  fail "could not put back a container without the builds mount"
fi

# A real preview through the launcher must not print the line that went with
# the removed timetable-section check (GitHub #224). It was printed on every
# preview for over a year and was never true. Outside the block above so it
# cannot be skipped: no log is a failure, not a pass.
if [[ ! -f /tmp/verify_old_container.log ]]; then
  fail "no preview output to read for the removed 'allowed sections' line"
elif grep -q "Could not read allowed sections" /tmp/verify_old_container.log; then
  fail "a preview still prints 'Could not read allowed sections', which was never true"
else
  pass "a preview no longer prints 'Could not read allowed sections'"
fi

# -------------------- 6d. --stop stops this section, and only this one ------
# Nothing here drove `--stop` before, so the mac's stop path had no automated
# gate at all: the rule was unit-tested against a snapshot and the LAUNCHER
# that carries it into the container was never run. Both halves of that are
# checked here against real processes in the real container.
#
# The stand-ins are shells, not node: what the rule reads is the command line
# and the working directory, and `sh -c "sleep 600" <args>` puts whatever is
# wanted on the command line while genuinely sleeping. Using the real Quartz
# CLI would test node's ability to start, which is not what is in question.
echo ""
echo "🚦 Driving ./preview.sh EXC2O 1 --stop against real processes…"

_count_matching() {
  # Skips its OWN process, which is not a nicety: the needle is on this
  # counter's command line too, so without it every count reads one too high
  # and every check in this section fails while the code under test is right.
  docker exec "$CONTAINER_NAME" python3 -c '
import os, sys
needle = sys.argv[1]
mine = str(os.getpid())
found = 0
for entry in os.listdir("/proc"):
    if not entry.isdigit() or entry == mine:
        continue
    try:
        line = open("/proc/%s/cmdline" % entry, "rb").read().replace(b"\x00", b" ").decode("utf-8", "replace")
    except OSError:
        continue
    if needle in line:
        found += 1
print(found)
' "$1" 2>/dev/null || echo 0
}

_start_stand_ins() {
  # Serving this section: caught by the directory on its command line.
  docker exec -d "$CONTAINER_NAME" sh -c \
    'exec sh -c "sleep 600" /tmp/quartz-builds/EXC2O/section1/quartz/bootstrap-cli.mjs --serve cq4t-probe-serve-1' \
    >/dev/null 2>&1
  # Serving ANOTHER section. Must survive: this is the regression that started
  # the whole rule — publishing section 2 taking section 1's preview down.
  docker exec -d "$CONTAINER_NAME" sh -c \
    'exec sh -c "sleep 600" /tmp/quartz-builds/EXC2O/section2/quartz/bootstrap-cli.mjs --serve cq4t-probe-serve-2' \
    >/dev/null 2>&1
  # In this section's folder with NOTHING on its command line to say so —
  # the `npm install` shape, which only a working-directory sweep can see.
  docker exec -d -w /tmp/quartz-builds/EXC2O/section1 "$CONTAINER_NAME" sh -c \
    'exec sh -c "sleep 600" cq4t-probe-cwd' >/dev/null 2>&1
  sleep 1
}

# Only section 1, which the cwd stand-in needs for `docker exec -w`. NOT
# section 2: `build_site.py` skips the scaffold copy whenever the output
# directory already exists, so an empty one left behind here makes a later
# `./preview.sh EXC2O 2` fail on a missing bootstrap-cli.mjs — in the very
# container this script leaves running and invites you to poke at. That is
# the "litter that reads as a broken toolchain" this section warns about,
# committed by the section itself.
docker exec "$CONTAINER_NAME" mkdir -p /tmp/quartz-builds/EXC2O/section1 >/dev/null 2>&1 || true
_start_stand_ins
if [[ "$(_count_matching cq4t-probe-serve-1)" == "1" && "$(_count_matching cq4t-probe-cwd)" == "1" \
      && "$(_count_matching cq4t-probe-serve-2)" == "1" ]]; then
  pass "three stand-in processes are running in the container"
else
  fail "could not start the stand-in processes, so --stop was not exercised"
fi

./preview.sh EXC2O 1 --stop >/tmp/verify_stop.log 2>&1 || true
sleep 1
if [[ "$(_count_matching cq4t-probe-serve-1)" == "0" ]]; then
  pass "--stop ended this section's preview server"
else
  fail "--stop left this section's preview server running"
  tail -10 /tmp/verify_stop.log
fi
if [[ "$(_count_matching cq4t-probe-cwd)" == "0" ]]; then
  pass "--stop ended a process known only by its working directory"
else
  fail "--stop missed a process sitting in the section's folder with nothing on its command line"
fi
if [[ "$(_count_matching cq4t-probe-serve-2)" == "1" ]]; then
  pass "--stop left ANOTHER section's preview alone"
else
  fail "--stop took down another section's preview — the regression this rule exists to prevent"
fi

# ---- The same, against a container that predates the shared rule ----------
# Stop mode must never build anything, so it runs against whatever container
# is already there — and right after an upgrade that is one built from the
# PREVIOUS image, with no stop_preview.py baked in. The launcher therefore
# pipes the recipe's own copy in over stdin. Naming the baked path instead
# would fail with a message nobody sees: both callers send this launcher's
# output to the null device and neither checks its exit code, so the teacher
# would be told nothing while the build carried on running.
docker exec "$CONTAINER_NAME" rm -f /opt/scripts/stop_preview.py >/dev/null 2>&1 || true
_start_stand_ins
if [[ "$(_count_matching cq4t-probe-serve-1)" == "1" ]]; then
  ./preview.sh EXC2O 1 --stop >/tmp/verify_stop_old.log 2>&1 || true
  sleep 1
  if [[ "$(_count_matching cq4t-probe-serve-1)" == "0" ]]; then
    pass "--stop still works against a container built before the shared rule existed"
  else
    fail "--stop cannot stop anything in a container that predates stop_preview.py"
    tail -10 /tmp/verify_stop_old.log
  fi
else
  fail "could not restart the stand-in process for the older-container check"
fi

# Leave the container as it was found: the stand-ins ended, and the file this
# section deleted from it put back. The container is left running on purpose
# (the summary tells you so), and handing it on with a hole in /opt/scripts
# would make the NEXT run's older-container check pass for the wrong reason —
# and, sooner than that, make an ordinary build fail on `import stop_preview`
# with an error that reads like a broken toolchain rather than like litter.
#
# Children too, not only the marked shells: this image's /bin/sh FORKS
# `sleep 600` rather than exec'ing it, so each stand-in leaves a child whose
# own command line carries no marker. Matching on the parent as well is what
# makes "leaves the container as it found it" true rather than nearly true.
docker exec "$CONTAINER_NAME" python3 -c '
import os, signal
# Skip THIS process. Its own command line carries the marker — the script
# text is the argument — so without this it marks itself, SIGKILLs itself
# part-way through, prints nothing and leaves the children it was written to
# collect. That is exactly what happened, and it is the second time
# self-matching has bitten in this one section: `_count_matching` above needs
# the same guard for the same reason. A process scanning for a string it is
# itself carrying is the shape to watch for here.
mine = os.getpid()
marked = set()
for entry in os.listdir("/proc"):
    if not entry.isdigit() or int(entry) == mine:
        continue
    try:
        line = open("/proc/%s/cmdline" % entry, "rb").read()
    except OSError:
        continue
    if b"cq4t-probe" in line:
        marked.add(int(entry))
doomed = set(marked)
for entry in os.listdir("/proc"):
    if not entry.isdigit() or int(entry) == mine:
        continue
    try:
        for row in open("/proc/%s/status" % entry, encoding="utf-8", errors="replace"):
            if row.startswith("PPid:") and int(row.split()[1]) in marked:
                doomed.add(int(entry))
                break
    except (OSError, ValueError, IndexError):
        continue
for pid in doomed:
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
' >/dev/null 2>&1 || true

docker cp scripts/stop_preview.py "$CONTAINER_NAME:/opt/scripts/stop_preview.py" >/dev/null 2>&1 || true
if docker exec "$CONTAINER_NAME" test -f /opt/scripts/stop_preview.py 2>/dev/null; then
  pass "and the container was left as it was found (the rule put back in /opt/scripts)"
else
  fail "the container is still missing /opt/scripts/stop_preview.py — the next build in it will fail on an import, which reads as a broken toolchain rather than as this section's litter"
fi

# -------------------- 6e. A working folder whose name has a colon ----------
# A teacher typed "Comm Tech 26/27" into Finder; macOS stored it as
# "Comm Tech 26:27"; `docker run -v "$path":/teaching/courses` read
# "/teaching/courses" as the MODE and refused — after 147 seconds of
# first-run setup (GitHub issue #221). Everything else in this file runs from
# THIS repository, whose path has no colon in it, so nothing here would ever
# have noticed.
#
# Its own folder, its own container, its own builds folder, all removed
# afterwards. And removed BEFORE as well, which is the part that matters: the
# launcher keeps a container it is happy with, so a second run would print
# "already running with correct mount", never call `docker run`, and pass
# having tested nothing — including when the fix has been taken back out.
VERIFY_COLON_DIR="$HOME/.plantoir-verify-26:27"
echo ""
echo "🚦 Building from a working folder called '$(basename "$VERIFY_COLON_DIR")'…"
rm -rf "$VERIFY_COLON_DIR"
mkdir -p "$VERIFY_COLON_DIR/courses"
cp setup.sh preview.sh deploy.sh "$VERIFY_COLON_DIR/"
cp -R courses/EXC2O "$VERIFY_COLON_DIR/courses/EXC2O"
# The fixture's .merged_output is a LINK to THIS folder's builds root. Copied
# as a link, it would aim the colon folder's build at this one's built site.
rm -rf "$VERIFY_COLON_DIR/courses/EXC2O/.merged_output"
VERIFY_COLON_ID="$(cd "$VERIFY_COLON_DIR" && pwd -P | shasum -a 256 | cut -c1-8)"
VERIFY_COLON_CONTAINER="teaching-quartz-${VERIFY_COLON_ID}"
VERIFY_COLON_BUILDS="${HOME%/}/Library/Application Support/Plantoir/builds/${VERIFY_COLON_ID}"
docker rm -f "$VERIFY_COLON_CONTAINER" >/dev/null 2>&1 || true
rm -rf "$VERIFY_COLON_BUILDS"
if (cd "$VERIFY_COLON_DIR" && ./preview.sh EXC2O 1 --image "$DEV_TEST_IMAGE" --build-only) \
     >/tmp/verify_colon_folder.log 2>&1; then
  pass "a working folder whose name contains a colon builds a website"
else
  fail "a working folder whose name contains a colon could not build"
  tail -20 /tmp/verify_colon_folder.log
fi
if [[ -f "$VERIFY_COLON_BUILDS/EXC2O/section1/public/index.html" ]]; then
  pass "and the site is where every reader of it looks"
else
  fail "no site at $VERIFY_COLON_BUILDS/EXC2O/section1/public/index.html"
fi
# WHICH folder the container was actually given. A container that mounted
# something else would still build something, and the something would be
# wrong.
COLON_MOUNT_SRC="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/teaching/courses"}}{{.Source}}{{end}}{{end}}' \
  "$VERIFY_COLON_CONTAINER" 2>/dev/null || echo "")"
if [[ "$COLON_MOUNT_SRC" == "$VERIFY_COLON_DIR/courses" ]]; then
  pass "and the workspace was given the colon-named folder itself, byte for byte"
else
  fail "the workspace was given [${COLON_MOUNT_SRC:-nothing}], not $VERIFY_COLON_DIR/courses"
fi
docker rm -f "$VERIFY_COLON_CONTAINER" >/dev/null 2>&1 || true
rm -rf "$VERIFY_COLON_DIR" "$VERIFY_COLON_BUILDS"

# -------------------- 6f. A LOCKED reference course builds ----------------
# The case the plan's own ruling owed and did not get: the mechanism decision
# — `chflags uchg` alone, never mode 444 — was made from a measurement, and a
# measurement made once is not a standing gate.
#
# What it pins, in the REAL image, over a real bind mount:
#   * a course whose every content file carries `uchg` builds at all;
#   * a page hidden in the SOURCE is hidden in the built site;
#   * building again over the existing build works;
#   * the source is untouched, and still locked, afterwards.
# The must-fail the plan ruling asked for — the same case with mode 444 — was
# tried here and does NOT reproduce through the real launcher. Written down
# rather than quietly dropped: the 444 fault needs the build tree to be the
# HOST BIND MOUNT, where container root does not get its usual permission
# override. `preview.sh --build-only` builds in the container's own
# /tmp/quartz-builds and syncs public/ out afterwards, so the frontmatter
# rewrite happens on container-local storage — where root CAN write a 444
# file. Run with `chmod 444` as well as the flag, this case still passed.
# The original measurement stands; it was taken against a bind mount on
# purpose. What this case cannot be is the standing gate on THAT, so it is
# the standing gate on everything else instead.
#
# Its own folder under $HOME (the VM mounts nothing else), its own container
# and its own builds folder, every flag cleared and all three removed
# afterwards — a locked tree that escaped would be undeletable litter.
VERIFY_LOCK_DIR="$HOME/.plantoir-verify-locked"
echo ""
echo "🚦 Building a LOCKED reference course in ${DEV_TEST_IMAGE}…"
chflags -R nouchg "$VERIFY_LOCK_DIR" 2>/dev/null || true
rm -rf "$VERIFY_LOCK_DIR"
mkdir -p "$VERIFY_LOCK_DIR/courses"
cp setup.sh preview.sh deploy.sh "$VERIFY_LOCK_DIR/"
cp -R courses/EXC2O "$VERIFY_LOCK_DIR/courses/EXC2O"
rm -rf "$VERIFY_LOCK_DIR/courses/EXC2O/.merged_output"
VERIFY_LOCK_COURSE="$VERIFY_LOCK_DIR/courses/EXC2O"
# One page the teacher has held back, and one they have not.
VERIFY_LOCK_SECTION="$VERIFY_LOCK_COURSE/section1"
# The LEGACY spelling, deliberately: `publish: false` needs no rewrite, so it
# would stay hidden even when the rewrite FAILS - and the rewrite failing is
# exactly what mode 444 introduces. A real reference course is this shape:
# measured on a previous-generation folder, 220 of its 320 pages carry `draft:`
# and none carries the modern key.
printf -- '---\ntitle: Held Back\ndraft: true\n---\n\nNot for students.\n' \
  > "$VERIFY_LOCK_SECTION/Held Back.md"
printf -- '---\ntitle: Out In The Open\npublish: true\n---\n\nFor students.\n' \
  > "$VERIFY_LOCK_SECTION/Out In The Open.md"
VERIFY_LOCK_ID="$(cd "$VERIFY_LOCK_DIR" && pwd -P | shasum -a 256 | cut -c1-8)"
VERIFY_LOCK_CONTAINER="teaching-quartz-${VERIFY_LOCK_ID}"
VERIFY_LOCK_BUILDS="${HOME%/}/Library/Application Support/Plantoir/builds/${VERIFY_LOCK_ID}"
docker rm -f "$VERIFY_LOCK_CONTAINER" >/dev/null 2>&1 || true
rm -rf "$VERIFY_LOCK_BUILDS"
# Exactly what `ReferenceLock` does: every FILE, no directory, and never
# course_config.json — the build's own preflight rewrites that one.
find "$VERIFY_LOCK_COURSE" -type f ! -name 'course_config.json' \
  ! -name 'course_config.backup.json' ! -name '.DS_Store' \
  ! -path '*/.obsidian/*' -exec chflags uchg {} + 2>/dev/null || true
VERIFY_LOCK_BEFORE="$(shasum -a 256 "$VERIFY_LOCK_SECTION/Held Back.md" | cut -d' ' -f1)"

if (cd "$VERIFY_LOCK_DIR" && ./preview.sh EXC2O 1 --image "$DEV_TEST_IMAGE" --build-only) \
     >/tmp/verify_locked_course.log 2>&1; then
  pass "a course whose pages are locked builds a website"
else
  fail "a locked course could not be built"
  tail -25 /tmp/verify_locked_course.log
fi
VERIFY_LOCK_PUBLIC="$VERIFY_LOCK_BUILDS/EXC2O/section1/public"
if [[ -f "$VERIFY_LOCK_PUBLIC/index.html" ]]; then
  pass "and the built site is where every reader of it looks"
else
  fail "no site at $VERIFY_LOCK_PUBLIC/index.html"
fi
# THE ONE THAT DECIDED THE MECHANISM: a page hidden in the source stays
# hidden. With mode 444 as well as the flag, the copy's frontmatter rewrite
# fails on the bind mount and this page is PUBLISHED.
if [[ -e "$VERIFY_LOCK_PUBLIC/Held-Back.html" || -e "$VERIFY_LOCK_PUBLIC/Held Back.html" ]]; then
  fail "A PAGE THE TEACHER HELD BACK WAS PUBLISHED from a locked course"
else
  pass "and a page hidden in the source is hidden in the built site"
fi
if [[ -e "$VERIFY_LOCK_PUBLIC/Out-In-The-Open.html" || -e "$VERIFY_LOCK_PUBLIC/Out In The Open.html" ]]; then
  pass "and a page the teacher published IS in it (so the check above means something)"
else
  fail "the published page is missing too — this build produced nothing to judge"
fi
# Again, over the existing build.
if (cd "$VERIFY_LOCK_DIR" && ./preview.sh EXC2O 1 --image "$DEV_TEST_IMAGE" --build-only) \
     >>/tmp/verify_locked_course.log 2>&1; then
  pass "and building again over the existing build works"
else
  fail "a second build over the existing one failed"
  tail -25 /tmp/verify_locked_course.log
fi
VERIFY_LOCK_AFTER="$(shasum -a 256 "$VERIFY_LOCK_SECTION/Held Back.md" | cut -d' ' -f1)"
if [[ "$VERIFY_LOCK_BEFORE" == "$VERIFY_LOCK_AFTER" ]]; then
  pass "and the source page is byte-for-byte what it was"
else
  fail "the build CHANGED a locked source page"
fi
if ls -lO "$VERIFY_LOCK_SECTION/Held Back.md" | grep -q uchg; then
  pass "and it is still locked"
else
  fail "the source page came back unlocked"
fi
docker rm -f "$VERIFY_LOCK_CONTAINER" >/dev/null 2>&1 || true
chflags -R nouchg "$VERIFY_LOCK_DIR" 2>/dev/null || true
rm -rf "$VERIFY_LOCK_DIR" "$VERIFY_LOCK_BUILDS"

RUNNING_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo '(none)')"
if [[ "$RUNNING_IMAGE" == "$DEV_TEST_IMAGE" ]]; then
  pass "Container '$CONTAINER_NAME' is running from $DEV_TEST_IMAGE"
else
  fail "Container '$CONTAINER_NAME' is running from '$RUNNING_IMAGE', not $DEV_TEST_IMAGE"
fi

# -------------------- Summary --------------------
echo ""
echo "==================== verify.sh summary ===================="
for line in "${RESULTS[@]}"; do echo "$line"; done
echo "==========================================================="
if [[ "$FAILED" == "true" ]]; then
  echo "❌ Verification FAILED — see items above."
  exit 1
fi
echo "✅ All checks passed."
echo ""
echo "ℹ️  Notes:"
echo "   • The '$CONTAINER_NAME' container was left running from $DEV_TEST_IMAGE"
echo "     so you can poke at it (e.g., ./preview.sh EXC2O 1 --image $DEV_TEST_IMAGE)."
echo "   • To return to the normal image, run:  docker rm -f $CONTAINER_NAME"
echo "     (the next ./setup.sh or ./preview.sh run recreates it automatically)."
echo "   • Colima was left exactly as it was found — never stopped by this script."
