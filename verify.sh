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
CONTAINER_NAME="teaching-quartz-$(/bin/pwd -P | shasum -a 256 | cut -c1-8)"
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
# A check that could not run here (it needs the network, say) is a SKIP:
# listed and printed like a failure so it is seen, but it does not fail the
# run - and it is never a pass (#594).
skip() { RESULTS+=("⏭️  SKIP  $1"); echo "⏭️  SKIP  $1"; }

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

# Not toolchain tests, and deliberately not in scripts/: they live beside the
# screenshot scripts so plantoir.app's marketing data never enters the recipe
# or the image hash. They are here because nothing else runs them on the mac
# (#445). Neither reads the kept folders: HOME is an empty temporary folder
# for both, so test_marketing_folder.py's College Board extraction (which
# looks in ~/Plantoir Marketing/.sources) skips rather than reading Russell's.
# The default run of test_demo_folders.py checks the courses, colours, markers
# and every scene's files at two clock years, and the REQUESTS that would set
# each front page; the front pages themselves are set and checked only by the
# opt-in run with PLANTOIR_DEMO_FOLDERS_APP (website/README.md).
DEMO_HOME=$(mktemp -d)
if env -u PLANTOIR_CED_PDF -u PLANTOIR_DEMO_FOLDERS_APP -u PLANTOIR_DEMO_FOLDERS_COMPARE HOME="$DEMO_HOME" \
     python3 website/shots/test_demo_folders.py >/tmp/verify_demo_folders_test.log 2>&1; then
  pass "plantoir.app's demo folders: every course, colour, site marker and scene's files can be made from the repository alone in 2026 and 2027, and each front page is asked of the app correctly (website/shots/test_demo_folders.py, #445; the front pages themselves only with PLANTOIR_DEMO_FOLDERS_APP)"
else
  fail "plantoir.app's demo folders: every course, colour, site marker and scene's files can be made from the repository alone in 2026 and 2027, and each front page is asked of the app correctly (website/shots/test_demo_folders.py, #445; the front pages themselves only with PLANTOIR_DEMO_FOLDERS_APP)"
  cat /tmp/verify_demo_folders_test.log
fi
if env -u PLANTOIR_CED_PDF HOME="$DEMO_HOME" \
     python3 website/shots/test_marketing_folder.py >/tmp/verify_marketing_folder_test.log 2>&1; then
  pass "the marketing folder's file steps: idempotent, never over a changed file, the second semester in the week of 1 February (website/shots/test_marketing_folder.py)"
else
  fail "the marketing folder's file steps: idempotent, never over a changed file, the second semester in the week of 1 February (website/shots/test_marketing_folder.py)"
  cat /tmp/verify_marketing_folder_test.log
fi
rm -rf "$DEMO_HOME"

if (cd scripts && python3 test_getting_ready_turn.py) >/tmp/verify_getting_ready_turn_test.log 2>&1; then
  pass "Launchers: one at a time gets the website builder ready, and setup.sh --prepare-builder does only that (scripts/test_getting_ready_turn.py, bundle B)"
else
  fail "Launchers: one at a time gets the website builder ready, and setup.sh --prepare-builder does only that (scripts/test_getting_ready_turn.py, bundle B)"
  cat /tmp/verify_getting_ready_turn_test.log
fi

if (cd scripts && python3 test_section_fingerprint.py) >/tmp/verify_section_fingerprint_test.log 2>&1; then
  pass "section_fingerprint.py: the \"— Edited\" fingerprint's rule 2 leaves How I Teach out, and the default stays rule 1 until Windows moves (scripts/test_section_fingerprint.py, #330)"
else
  fail "section_fingerprint.py: the \"— Edited\" fingerprint's rule 2 leaves How I Teach out, and the default stays rule 1 until Windows moves (scripts/test_section_fingerprint.py, #330)"
  cat /tmp/verify_section_fingerprint_test.log
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

if (cd scripts && python3 test_install_link_readers.py) >/tmp/verify_install_link_readers_test.log 2>&1; then
  pass "setup_course.py and the coverage map: every link shape the contract names is read by the installer's and the map's link readers (scripts/test_install_link_readers.py)"
else
  fail "setup_course.py and the coverage map: every link shape the contract names is read by the installer's and the map's link readers (scripts/test_install_link_readers.py)"
  cat /tmp/verify_install_link_readers_test.log
fi

if (cd scripts && python3 test_markdown_code.py) >/tmp/verify_markdown_code_test.log 2>&1; then
  pass "markdown_code.py: a link written inside code is not a link, for the build's and the installer's readers and the coverage map (scripts/test_markdown_code.py, #313)"
else
  fail "markdown_code.py: a link written inside code is not a link, for the build's and the installer's readers and the coverage map (scripts/test_markdown_code.py, #313)"
  cat /tmp/verify_markdown_code_test.log
fi

if (cd scripts && python3 test_graded_folders_rerun.py) >/tmp/verify_graded_rerun_test.log 2>&1; then
  pass "setup_course.py: a re-run writes a saved marks pool back as it was (scripts/test_graded_folders_rerun.py)"
else
  fail "setup_course.py: a re-run writes a saved marks pool back as it was (scripts/test_graded_folders_rerun.py)"
  cat /tmp/verify_graded_rerun_test.log
fi

if (cd scripts && python3 test_graded_folders_new_course.py) >/tmp/verify_graded_new_course_test.log 2>&1; then
  pass "setup_course.py: a new course is written its marks pool, as both apps write it (scripts/test_graded_folders_new_course.py)"
else
  fail "setup_course.py: a new course is written its marks pool, as both apps write it (scripts/test_graded_folders_new_course.py)"
  cat /tmp/verify_graded_new_course_test.log
fi

if (cd scripts && python3 test_folder_titles.py) >/tmp/verify_folder_titles_test.log 2>&1; then
  pass "setup_course.py: a folder's index page names it in a title YAML reads back, by the titleQuoting rule (scripts/test_folder_titles.py, #506)"
else
  fail "setup_course.py: a folder's index page names it in a title YAML reads back, by the titleQuoting rule (scripts/test_folder_titles.py, #506)"
  cat /tmp/verify_folder_titles_test.log
fi

if (cd scripts && python3 test_course_code_rule.py) >/tmp/verify_course_code_rule_test.log 2>&1; then
  pass "setup_course.py: a typed course code is asked the apps' rule, every courseCode case (scripts/test_course_code_rule.py, #402)"
else
  fail "setup_course.py: a typed course code is asked the apps' rule, every courseCode case (scripts/test_course_code_rule.py, #402)"
  cat /tmp/verify_course_code_rule_test.log
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

if (cd scripts && python3 test_quartz_analytics_off.py) >/tmp/verify_analytics_off_test.log 2>&1; then
  pass "build_site.py: Quartz's own page-view counter, which nobody set up, is switched off in every build (#594, scripts/test_quartz_analytics_off.py)"
else
  fail "build_site.py: Quartz's own page-view counter is not switched off (scripts/test_quartz_analytics_off.py, #594)"
  cat /tmp/verify_analytics_off_test.log
fi
if (cd scripts && python3 test_netlify_badge.py) >/tmp/verify_netlify_badge_test.log 2>&1; then
  pass "netlify_badge.py: shared ad-badge suppression module, and the hosts a page's scripts import code from allowed - Mermaid from cdnjs, never a fetch target (#594, scripts/test_netlify_badge.py)"
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

if (cd scripts && python3 test_deploy_cloudflare_project.py) >/tmp/verify_deploy_cloudflare_project_test.log 2>&1; then
  pass "deploy: Cloudflare's own deploy tool is never left a question to ask, and a deleted project is made again (scripts/test_deploy_cloudflare_project.py)"
else
  fail "deploy: Cloudflare's own deploy tool is never left a question to ask, and a deleted project is made again (scripts/test_deploy_cloudflare_project.py)"
  cat /tmp/verify_deploy_cloudflare_project_test.log
fi

if (cd scripts && python3 test_backup_leaves_plantoir_addons.py) >/tmp/verify_backup_addons_test.log 2>&1; then
  pass "the setup wizard's backup leaves Plantoir's Obsidian add-ons out and keeps the teacher's own (scripts/test_backup_leaves_plantoir_addons.py, #495)"
else
  fail "the setup wizard's backup leaves Plantoir's Obsidian add-ons out and keeps the teacher's own (scripts/test_backup_leaves_plantoir_addons.py, #495)"
  cat /tmp/verify_backup_addons_test.log
fi

if (cd scripts && python3 test_reference_course.py) >/tmp/verify_reference_course_test.log 2>&1; then
  pass "a course kept for reference is never deployed, at every door the shared toolchain owns (scripts/test_reference_course.py)"
else
  fail "a course kept for reference is never deployed, at every door the shared toolchain owns (scripts/test_reference_course.py)"
  cat /tmp/verify_reference_course_test.log
fi

# The teacher's How I Teach page is never on the website (#209): the name
# rule against the contract's nameCases, discovery, preflight, the lists the
# copy loops read and the final sweep. The real build is checked further down.
if (cd scripts && python3 test_how_i_teach.py) >/tmp/verify_how_i_teach_test.log 2>&1; then
  pass "the How I Teach page is never listed, copied or left in a site's pages (scripts/test_how_i_teach.py)"
else
  fail "the How I Teach page is never listed, copied or left in a site's pages (scripts/test_how_i_teach.py)"
  cat /tmp/verify_how_i_teach_test.log
fi

# What the LOCAL model is shown has not moved a byte (#209's plan review):
# the full digest of toolSchemas.local, made by research/ai-assist/toolhash.py.
if (cd scripts && python3 test_tool_surface_digest.py) >/tmp/verify_tool_digest_test.log 2>&1; then
  pass "the local assistant's thirteen tools are the ones routing was measured against (scripts/test_tool_surface_digest.py)"
else
  fail "the local assistant's thirteen tools are the ones routing was measured against (scripts/test_tool_surface_digest.py)"
  cat /tmp/verify_tool_digest_test.log
fi

# DEPLOY puts a site online; PUBLISH only marks a page (#443, v1.4.4). The
# sentences that said publish for a deploy were moved; this keeps them moved,
# in the mac app's Swift, the launchers and the shared Python. Reads files only.
if (cd scripts && python3 test_deploy_words.py) >/tmp/verify_deploy_words_test.log 2>&1; then
  pass "no sentence a teacher reads says publish for a deploy (scripts/test_deploy_words.py, #443)"
else
  fail "no sentence a teacher reads says publish for a deploy (scripts/test_deploy_words.py, #443)"
  cat /tmp/verify_deploy_words_test.log
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

if (cd scripts && python3 test_preview_while_deploying.py) >/tmp/verify_preview_while_deploying_test.log 2>&1; then
  pass "preview.sh: a section being deployed cannot be previewed, whoever deploys it, and a build or an unreadable process table does not refuse (scripts/test_preview_while_deploying.py, #381)"
else
  fail "preview.sh: a section being deployed cannot be previewed, whoever deploys it, and a build or an unreadable process table does not refuse (scripts/test_preview_while_deploying.py, #381)"
  cat /tmp/verify_preview_while_deploying_test.log
fi

if (cd scripts && python3 test_deploy_while_its_section_deploys.py) >/tmp/verify_deploy_while_its_section_deploys_test.log 2>&1; then
  pass "deploy.sh and preview.sh --build-only: a section still being deployed (a deploy set for later, even one whose run was ended, or deploy.sh) is not deployed again (scripts/test_deploy_while_its_section_deploys.py, #439)"
else
  fail "deploy.sh and preview.sh --build-only: a section still being deployed (a deploy set for later, even one whose run was ended, or deploy.sh) is not deployed again (scripts/test_deploy_while_its_section_deploys.py, #439)"
  cat /tmp/verify_deploy_while_its_section_deploys_test.log
fi

if (cd scripts && python3 test_colour_scheme_names.py) >/tmp/verify_colour_scheme_names_test.log 2>&1; then
  pass "a colour scheme's name never names the machinery (scripts/test_colour_scheme_names.py, #383)"
else
  fail "a colour scheme's name never names the machinery (scripts/test_colour_scheme_names.py, #383)"
  cat /tmp/verify_colour_scheme_names_test.log
fi

if (cd scripts && python3 test_sidebar_page_marker.py) >/tmp/verify_sidebar_page_marker_test.log 2>&1; then
  pass "the sidebar's page dot: at least 3:1 on the sidebar in every colour scheme, light and dark, and no rule on a link, its hover or the current page (scripts/test_sidebar_page_marker.py, #515)"
else
  fail "the sidebar's page dot: too faint in a colour scheme, a rule on the sidebar's links, or not carried to the site (scripts/test_sidebar_page_marker.py, #515)"
  cat /tmp/verify_sidebar_page_marker_test.log
fi

if (cd scripts && python3 test_code_lines_style.py) >/tmp/verify_code_lines_style_test.log 2>&1; then
  pass "every code block's line numbers: one gutter style with its hairline for static and runnable blocks, no ligatures in code, the editor's colour categories the contract's, and a handout's wrapped line hung under its code (scripts/test_code_lines_style.py, #585)"
else
  fail "every code block's line numbers or the editor's colours are not as the contract and each other say (scripts/test_code_lines_style.py, #585)"
  cat /tmp/verify_code_lines_style_test.log
fi

if (cd scripts && python3 test_folder_spelling.py) >/tmp/verify_folder_spelling_test.log 2>&1; then
  pass "one working folder, one spelling: every spelling of a folder names one website builder and one builds folder (scripts/test_folder_spelling.py, #189)"
else
  fail "one working folder, one spelling: every spelling of a folder names one website builder and one builds folder (scripts/test_folder_spelling.py, #189)"
  cat /tmp/verify_folder_spelling_test.log
fi

if (cd scripts && python3 test_launcher_words.py) >/tmp/verify_launcher_words_test.log 2>&1; then
  pass "Launchers: no line a teacher reads says container, Docker or image, and every bar can reach the step it watches a launcher for (scripts/test_launcher_words.py, #382)"
else
  fail "Launchers: no line a teacher reads says container, Docker or image, and every bar can reach the step it watches a launcher for (scripts/test_launcher_words.py, #382)"
  cat /tmp/verify_launcher_words_test.log
fi

# Printable pages (#454): which pages opt in and which make a site carry the
# print engine, a teacher's own PDF resolved against Media, the gate, and the
# printPdfNotFound finding; then the corners, page labels and words a printed
# page carries. Both read the contract; stdlib only. Since #455 the same file
# runs runnable code's cases too: the language table, which fences run and
# where they can sit, ids, what a site carries, the engine's overlay, and the
# words file.
if (cd scripts && python3 test_page_features.py) >/tmp/verify_page_features_test.log 2>&1; then
  pass "pages that ask for more: printing, a page's own PDF, runnable code, and the engines a site carries (scripts/test_page_features.py, #454, #455)"
else
  fail "pages that ask for more: printing, a page's own PDF, runnable code, and the engines a site carries (scripts/test_page_features.py, #454, #455)"
  cat /tmp/verify_page_features_test.log
fi

# Live input (#583): which built pages a publish isolates (a block that can
# ask, and nothing from another website the headers would break), each
# host's MEASURED spelling of a page's path, the marked _headers block -
# replaced, never appended, beside the badge rule - Cloudflare's 100 rules,
# and the note lines. Reads the contract; stdlib only.
if (cd scripts && python3 test_isolation_headers.py) >/tmp/verify_isolation_headers_test.log 2>&1; then
  pass "live input: which pages a publish lets ask for input as the program runs, each host's spelling of their paths, the _headers block replaced beside the badge rule, Cloudflare's 100 rules and the note lines (scripts/test_isolation_headers.py, #583)"
else
  fail "live input: which pages a publish lets ask for input as the program runs, each host's spelling of their paths, the _headers block replaced beside the badge rule, Cloudflare's 100 rules and the note lines (scripts/test_isolation_headers.py, #583)"
  cat /tmp/verify_isolation_headers_test.log
fi

# Runnable Swift (#493): the key a block is cached by, the toolchain id, what
# the launcher's plan writes and what the build's prepare gives the site and
# says, and that the Swift image's recipe holds every pin and flag the
# contract names. Stdlib only; the compiler itself is the Swift gate below.
if (cd scripts && python3 test_swift_blocks.py) >/tmp/verify_swift_blocks_test.log 2>&1; then
  pass "runnable Swift: the cache key, the toolchain id, the launcher's plan, the build's prepare and its words, and the Swift image's pins and flags (scripts/test_swift_blocks.py, #493)"
else
  fail "runnable Swift: the cache key, the toolchain id, the launcher's plan, the build's prepare and its words, and the Swift image's pins and flags (scripts/test_swift_blocks.py, #493)"
  cat /tmp/verify_swift_blocks_test.log
fi

# KaTeX served by the site itself (#494): the copy from Quartz's own package
# and the latex.ts patch that links it; and (#455) the edits that wire
# Plantoir's additions into a section's Quartz copy. Stdlib only.
if (cd scripts && python3 test_katex_assets.py) >/tmp/verify_katex_assets_test.log 2>&1; then
  pass "maths: KaTeX's stylesheet, copy-tex and faces copied into every site, and latex.ts linking them instead of a CDN (scripts/test_katex_assets.py, #494)"
else
  fail "maths: KaTeX's stylesheet, copy-tex and faces copied into every site, and latex.ts linking them instead of a CDN (scripts/test_katex_assets.py, #494)"
  cat /tmp/verify_katex_assets_test.log
fi
if (cd scripts && python3 test_quartz_additions_wiring.py) >/tmp/verify_quartz_wiring_test.log 2>&1; then
  pass "Plantoir's additions are wired into a section's Quartz copy once, in the right places, and a second build changes nothing (scripts/test_quartz_additions_wiring.py, #455)"
else
  fail "Plantoir's additions are wired into a section's Quartz copy once, in the right places, and a second build changes nothing (scripts/test_quartz_additions_wiring.py, #455)"
  cat /tmp/verify_quartz_wiring_test.log
fi

# Task boxes students tick (#519): the box's edge, its tick and a ticked
# item's words stand out in every colour scheme, light and dark, and the dark
# theme's paper ink on white. Stdlib only.
if (cd scripts && python3 test_task_box_contrast.py) >/tmp/verify_task_box_contrast_test.log 2>&1; then
  pass "task boxes: the edge and the tick at least 3:1, a ticked item's words at least 4.5:1, in every colour scheme, light and dark, with no fill, and the dark theme's paper ink (scripts/test_task_box_contrast.py, #519)"
else
  fail "task boxes: a colour too faint in a colour scheme, a fill on a ticked box, or no paper ink for the dark theme (scripts/test_task_box_contrast.py, #519)"
  cat /tmp/verify_task_box_contrast_test.log
fi

# Self-check quizzes (#563): every recognise and answers.parse case through
# the folder check's mirror, the line in the teacher's file, the
# quizzesNotReady finding, the words and pages files the site reads, and the
# pages the check reads. Stdlib only.
if (cd scripts && python3 test_quizzes.py) >/tmp/verify_quizzes_test.log 2>&1; then
  pass "self-check quizzes: every quiz shape the contract names read by the folder check, its lines in the teacher's file, the quizzesNotReady finding, and the files the site reads (scripts/test_quizzes.py, #563)"
else
  fail "self-check quizzes: every quiz shape the contract names read by the folder check, its lines in the teacher's file, the quizzesNotReady finding, and the files the site reads (scripts/test_quizzes.py, #563)"
  cat /tmp/verify_quizzes_test.log
fi

# My Progress (#545): the two settings (read as include_curriculum_coverage
# is), the headings, the build's gate over every sections and gate case, the
# tables' labels, Key Links first, the words, the marker lines, and the
# build's own steps - the page, the plan, the sidebar pin and the emitter's
# wiring - over temporary folders. Stdlib only.
if (cd scripts && python3 test_my_progress.py) >/tmp/verify_my_progress_test.log 2>&1; then
  pass "My Progress: the settings, the headings, the build's gate over every contract case, the labels, Key Links first, the words, the marker, the page, the plan, the sidebar pin and the emitter's wiring (scripts/test_my_progress.py, #545)"
else
  fail "My Progress: the settings, the headings, the build's gate over every contract case, the labels, Key Links first, the words, the marker, the page, the plan, the sidebar pin and the emitter's wiring (scripts/test_my_progress.py, #545)"
  cat /tmp/verify_my_progress_test.log
fi

if (cd scripts && python3 test_print_settings.py) >/tmp/verify_print_settings_test.log 2>&1; then
  pass "printable pages: the corners, page labels and words a printed page carries (scripts/test_print_settings.py, #454)"
else
  fail "printable pages: the corners, page labels and words a printed page carries (scripts/test_print_settings.py, #454)"
  cat /tmp/verify_print_settings_test.log
fi

# Diagrams and graphs (#485 E1): the fences, the tidying and key every engine
# shares, the cache, the clock, the restart after a diagram that never
# finishes, the gate and the words - against a stand-in engine, stdlib only.
# The real engines are checked in the image below.
if (cd scripts && python3 test_figures.py) >/tmp/verify_figures_test.log 2>&1; then
  pass "diagrams and graphs: fences, tidying, the cache and its clock, what a site carries, and the words (scripts/test_figures.py, #485)"
else
  fail "diagrams and graphs: fences, tidying, the cache and its clock, what a site carries, and the words (scripts/test_figures.py, #485)"
  cat /tmp/verify_figures_test.log
fi

if (cd scripts && python3 test_port_blocks.py) >/tmp/verify_port_blocks_test.log 2>&1; then
  pass "the launchers walk forty blocks for a folder's preview addresses, skip any another folder holds, and say so truthfully when none is free (scripts/test_port_blocks.py)"
else
  fail "the launchers walk forty blocks for a folder's preview addresses, skip any another folder holds, and say so truthfully when none is free (scripts/test_port_blocks.py)"
  cat /tmp/verify_port_blocks_test.log
fi

if (cd scripts && python3 test_trail_lock.py) >/tmp/verify_trail_lock_test.log 2>&1; then
  pass "every launcher adds its line to the activity trail holding the app's lock, so a trim never loses it (scripts/test_trail_lock.py)"
else
  fail "every launcher adds its line to the activity trail holding the app's lock, so a trim never loses it (scripts/test_trail_lock.py)"
  cat /tmp/verify_trail_lock_test.log
fi

# RUNS deploy.sh's folder publish from a working folder whose own name has a
# colon, to relative folders with colons in them (GitHub issue #227): where
# each one lands, and that a copy that did not finish is never "Published".
if (cd scripts && python3 test_deploy_folder_target.py) >/tmp/verify_deploy_folder_target_test.log 2>&1; then
  pass "deploy.sh: a publish to a folder lands in the folder it names, and a copy that did not finish says so (scripts/test_deploy_folder_target.py)"
else
  fail "deploy.sh: a publish to a folder lands in the folder it names, and a copy that did not finish says so (scripts/test_deploy_folder_target.py)"
  cat /tmp/verify_deploy_folder_target_test.log
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

# The first-run block every launcher shares, RUN against every case in
# contracts/app-rules.json → helperBootstrap (GitHub #312): the helper programs
# copied out of the Mac app or downloaded and checked, the install stamp, and
# the website builder created from the app's starting disk. Stand-ins for the
# network and the programs; real shasum, cp -c, xattr and bash 3.2.
if (cd scripts && python3 test_helper_bootstrap.py) >/tmp/verify_helper_bootstrap_test.log 2>&1; then
  pass "the launchers install the helper programs from inside the app, or download and check them, and create the website builder from the app's starting disk (scripts/test_helper_bootstrap.py)"
else
  fail "the launchers install the helper programs from inside the app, or download and check them, and create the website builder from the app's starting disk (scripts/test_helper_bootstrap.py)"
  cat /tmp/verify_helper_bootstrap_test.log
fi

if (cd scripts && python3 test_preflight_exclusions.py) >/tmp/verify_preflight_exclusions_test.log 2>&1; then
  pass "build_site.py: preflight excluded_items discovery skipping & index.md notes (scripts/test_preflight_exclusions.py)"
else
  fail "build_site.py: preflight excluded_items discovery skipping & index.md notes (scripts/test_preflight_exclusions.py)"
  cat /tmp/verify_preflight_exclusions_test.log
fi

# Issue #128: one coverage map per curriculum folder, and what setup records.
if (cd scripts && python3 test_coverage_maps.py) >/tmp/verify_coverage_maps_test.log 2>&1; then
  pass "build_site.py: one curriculum coverage map per curriculum folder, the code rule, and single-map output unchanged (scripts/test_coverage_maps.py)"
else
  fail "build_site.py: one curriculum coverage map per curriculum folder, the code rule, and single-map output unchanged (scripts/test_coverage_maps.py)"
  sed 's/^/     /' /tmp/verify_coverage_maps_test.log | tail -40
fi

# Issue #505: an overall expectation's backlinks gather its specific expectations'.
if (cd scripts && python3 test_overall_backlinks.py) >/tmp/verify_overall_backlinks_test.log 2>&1; then
  pass "build_site.py: an overall expectation's page lists the pages of its specific expectations, once each (scripts/test_overall_backlinks.py)"
else
  fail "build_site.py: an overall expectation's page lists the pages of its specific expectations, once each (scripts/test_overall_backlinks.py)"
  sed 's/^/     /' /tmp/verify_overall_backlinks_test.log | tail -40
fi

# Issue #520: folder pages (a curriculum folder's index among them) get the
# table of contents, wired through wire_quartz_additions.
if (cd scripts && python3 test_folder_page_toc.py) >/tmp/verify_folder_page_toc_test.log 2>&1; then
  pass "build_site.py: folder pages get the table of contents, once, and the page layout keeps its own (scripts/test_folder_page_toc.py)"
else
  fail "build_site.py: folder pages get the table of contents, once, and the page layout keeps its own (scripts/test_folder_page_toc.py)"
  sed 's/^/     /' /tmp/verify_folder_page_toc_test.log | tail -40
fi

if (cd scripts && python3 test_setup_curriculum_folders.py) >/tmp/verify_setup_curriculum_folders_test.log 2>&1; then
  pass "setup_course.py: curriculum_folders written for a new course, and a re-run keeps a recorded folder (scripts/test_setup_curriculum_folders.py)"
else
  fail "setup_course.py: curriculum_folders written for a new course, and a re-run keeps a recorded folder (scripts/test_setup_curriculum_folders.py)"
  sed 's/^/     /' /tmp/verify_setup_curriculum_folders_test.log | tail -40
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
#
# deploy.sh is asked for its ONE reader of the rule (#291), which
# scripts/test_preview_build_detection.py then runs against every case in
# contracts/app-rules.json; deploy.ps1 still carries the bare address until
# Windows adopts the same rule (GitHub #272).
_folder_guard_ok=true
if ! grep -q 'site_carries_preview_client "${PUBLIC_DIR_HOST}"' deploy.sh; then
  _folder_guard_ok=false
  echo "   deploy.sh does not check for a preview build before publishing to a folder"
fi
if ! grep -q "ws://localhost:" deploy.ps1; then
  _folder_guard_ok=false
  echo "   deploy.ps1 does not check for a preview build before publishing to a folder"
fi
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

# ---- folder titles read back through the build's own reader (#506) ----
# The host run in step 0 has no frontmatter reader, so it checks the rule and
# the wizard's pages only; here every titleQuoting case and a sweep of awkward
# names are read back by the reader the build uses, and a missing reader fails.
echo ""
echo "🔎 Checking that every folder title reads back through the build's reader…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/test_folder_titles.py" /opt/scripts/test_folder_titles.py),readonly" \
  -e PLANTOIR_REQUIRE_FRONTMATTER=1 \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_folder_titles.py >/tmp/verify_folder_titles_image_test.log 2>&1; then
  pass "folder titles: every titleQuoting case and the sweep read back as their names in the build's reader (scripts/test_folder_titles.py in the image, #506)"
else
  fail "folder titles: every titleQuoting case and the sweep read back as their names in the build's reader (scripts/test_folder_titles.py in the image, #506)"
  cat /tmp/verify_folder_titles_image_test.log
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

# ---- the line the app writes on a front page still names the class (#397) ----
# The app's pointer keeps the form the teacher wrote; the build turns a
# section path into its display name. Every expected line in the contract is
# run through the build's own rewrite, in the image, because build_site needs
# python-frontmatter.
echo ""
echo "🔎 Checking that every front-page line the app writes still names its class on the site…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/test_front_page_lines_resolve.py" /opt/scripts/test_front_page_lines_resolve.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_front_page_lines_resolve.py >/tmp/verify_front_page_lines_test.log 2>&1; then
  pass "the app's front-page line names its class once the build has read it (scripts/test_front_page_lines_resolve.py)"
else
  fail "the app's front-page line names its class once the build has read it (scripts/test_front_page_lines_resolve.py)"
  cat /tmp/verify_front_page_lines_test.log
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

# ---- build_site.py: links students would find dead (#333) ----
# Every case in contracts/shared-rules.json -> siteHealth.linksIntoHiddenPages
# through the build's own reader, in the image because it imports build_site
# (python-frontmatter): a link on a page students can see into one they
# cannot, named by its place in the course folder, once, and ONE finding.
echo ""
echo "🔎 Checking that links into hidden pages are named…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/test_links_into_hidden_pages.py" /opt/scripts/test_links_into_hidden_pages.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_links_into_hidden_pages.py >/tmp/verify_links_into_hidden_pages_test.log 2>&1; then
  pass "build_site.py: a link on a page students can see into a hidden page is named (scripts/test_links_into_hidden_pages.py, #333)"
else
  fail "build_site.py: a link on a page students can see into a hidden page is named (scripts/test_links_into_hidden_pages.py, #333)"
  cat /tmp/verify_links_into_hidden_pages_test.log
fi

# ---- build_site.py: the links checklist's offer (#379) ----
# Every case in contracts/class-planning.json -> datingPagesAClassBrings.
# fromTheLinksChecklist and shared-rules.json -> linksChecklist.buildCases
# through the build's own offer: which hidden pages are offered, in which
# group, ticked or not, with which date; the file removed when empty and
# never written for a reference course; and no page's visibility touched.
echo ""
echo "🔎 Checking the links checklist the build offers…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/test_links_checklist.py" /opt/scripts/test_links_checklist.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_links_checklist.py >/tmp/verify_links_checklist_test.log 2>&1; then
  pass "build_site.py: the links checklist offers what the contract says (scripts/test_links_checklist.py, #379)"
else
  fail "build_site.py: the links checklist offers what the contract says (scripts/test_links_checklist.py, #379)"
  cat /tmp/verify_links_checklist_test.log
fi

# ---- the published-pages record (#379) ----
# The build's list of the pages it shows (beside public/, never inside it,
# written only after the site was built), deploy.py's fragment after each
# upload, deploy.sh's folder branch recording for itself, and the union read.
echo ""
echo "🔎 Checking the record of pages that have been published…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/test_published_pages_record.py" /opt/scripts/test_published_pages_record.py),readonly" \
  --mount "$(bind_mount_argument "$(pwd)/deploy.sh" /opt/deploy.sh),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_published_pages_record.py >/tmp/verify_published_pages_record_test.log 2>&1; then
  pass "build_site.py, deploy.py, deploy.sh: the pages a publish put on a site are recorded, and only then (scripts/test_published_pages_record.py, #379)"
else
  fail "build_site.py, deploy.py, deploy.sh: the pages a publish put on a site are recorded, and only then (scripts/test_published_pages_record.py, #379)"
  cat /tmp/verify_published_pages_record_test.log
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

# ---- Printable pages (#454): the rules, run where they really run ----
# printRules.ts is the file the page's own print code imports; it is bundled
# with the image's esbuild and every printablePages case is run through it in
# Node. And every typed pageOptIns line goes through the build's own reader.
echo ""
echo "🔎 Checking the printing rules against what the site and the build run…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/check_print_rules_against_the_site.py" /opt/scripts/check_print_rules_against_the_site.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/check_print_rules_against_the_site.py \
  >/tmp/verify_print_rules_site.log 2>&1; then
  pass "every printablePages rule case holds in the site's own code, and every pageOptIns line reads as the contract says (scripts/check_print_rules_against_the_site.py, #454)"
else
  fail "every printablePages rule case holds in the site's own code, and every pageOptIns line reads as the contract says (scripts/check_print_rules_against_the_site.py, #454)"
  cat /tmp/verify_print_rules_site.log
fi

# ---- Runnable code (#455): the rules, run where they really run ----
# codeRunnerRule.ts (the file the site's transformer and the page's script
# both import) is bundled with Quartz's own parser, and every fences,
# pageShapes and ids case is run through it in Node; the transformer is run
# over a page whose engine the site does and does not carry (siteDisagrees);
# the build's fence reader reads every pageShapes case too; and every typed
# codeRunner: line goes through the build's own reader.
echo ""
echo "🔎 Checking the runnable-code rules against what the site and the build run…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/check_runner_rules_against_the_site.py" /opt/scripts/check_runner_rules_against_the_site.py),readonly" \
  --mount "$(bind_mount_argument "$(pwd)/scripts/fixtures/runner-colour" /opt/scripts/fixtures/runner-colour),readonly" \
  --mount "$(bind_mount_argument "$(pwd)/swift-gate" /opt/swift-gate),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/check_runner_rules_against_the_site.py \
  >/tmp/verify_runner_rules_site.log 2>&1; then
  pass "every codeRunnerBlocks case holds in the site's own code and Quartz's own parser, the build reads every fence shape alike, every codeRunner: line reads as the contract says, and the editor's colours agree with the image's own Shiki case for case, colour for colour and over the example content - $(grep '^codeRunnerColour.ts' /tmp/verify_runner_rules_site.log | sed 's/^codeRunnerColour.ts: //') (scripts/check_runner_rules_against_the_site.py, #455, #585)"
else
  fail "every codeRunnerBlocks case holds in the site's own code and Quartz's own parser, the build reads every fence shape alike, and every codeRunner: line reads as the contract says (scripts/check_runner_rules_against_the_site.py, #455)"
  cat /tmp/verify_runner_rules_site.log
fi

# ---- Self-check quizzes (#563): the rules, run where they really run ----
# quizRules.ts (the file the site's transformer and the page's script both
# check answers with) is bundled and every answers.parse, answers.check and
# shuffle case is run through it in Node, with 1,000 shuffles each a
# permutation; the transformer's text hook leaves every untouched page byte
# for byte and makes a CR LF page LF; and every word the site asks for is in
# the contract.
echo ""
echo "🔎 Checking the self-check quiz rules against what the site runs…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/check_quiz_rules_against_the_site.py" /opt/scripts/check_quiz_rules_against_the_site.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/check_quiz_rules_against_the_site.py \
  >/tmp/verify_quiz_rules_site.log 2>&1; then
  pass "every quizCallouts answer, check and shuffle case holds in the site's own code, the text hook leaves pages without a quiz untouched, and every word the site shows is the contract's (scripts/check_quiz_rules_against_the_site.py, #563)"
else
  fail "every quizCallouts answer, check and shuffle case holds in the site's own code, the text hook leaves pages without a quiz untouched, and every word the site shows is the contract's (scripts/check_quiz_rules_against_the_site.py, #563)"
  cat /tmp/verify_quiz_rules_site.log
fi

# ---- Task boxes students tick (#519): the rules, run where they really run ----
# taskRules.ts and the transformer (plantoirTasks.ts - the only producer of an
# item's id) are bundled with Quartz's own text transform and parser, and every
# taskBoxes case is run through them in Node: each case's Markdown reads as
# Quartz rewrites it, the transformer stamps the case's ids in order, and the
# key, the id and the read API are the contract's.
echo ""
echo "🔎 Checking the task-box rules against what the site runs…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/check_task_rules_against_the_site.py" /opt/scripts/check_task_rules_against_the_site.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/check_task_rules_against_the_site.py \
  >/tmp/verify_task_rules_site.log 2>&1; then
  pass "every taskBoxes case holds in the site's own code over Quartz's own text transform and parser: the item's text, its id, the key and the read API (scripts/check_task_rules_against_the_site.py, #519)"
else
  fail "every taskBoxes case holds in the site's own code over Quartz's own text transform and parser: the item's text, its id, the key and the read API (scripts/check_task_rules_against_the_site.py, #519)"
  cat /tmp/verify_task_rules_site.log
fi

# ---- My Progress (#545): the rules, run where they really run ----
# progressRules.ts and the emitter are bundled with Quartz's own FrontMatter,
# ObsidianFlavoredMarkdown and GitHubFlavoredMarkdown, PlantoirQuizzes and
# PlantoirTasks, and every site-side myProgress case is run through them in
# Node - the same sections and gate cases the build's gate reads in
# test_my_progress.py (#545 plan review F3) - with the grouping cases through
# the build's own date pass and plan, and the emitter over a plan on disk.
echo ""
echo "🔎 Checking the My Progress rules against what the site runs…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/check_progress_rules_against_the_site.py" /opt/scripts/check_progress_rules_against_the_site.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/check_progress_rules_against_the_site.py \
  >/tmp/verify_progress_rules_site.log 2>&1; then
  pass "every myProgress case holds in the site's own code over Quartz's own transformers: the headings, the sections, the gate, the roll-up, the sidebar, the grouping through the build's date pass, and the emitter's notes (scripts/check_progress_rules_against_the_site.py, #545)"
else
  fail "every myProgress case holds in the site's own code over Quartz's own transformers: the headings, the sections, the gate, the roll-up, the sidebar, the grouping through the build's date pass, and the emitter's notes (scripts/check_progress_rules_against_the_site.py, #545)"
  cat /tmp/verify_progress_rules_site.log
fi

# ---- Diagrams and graphs (#485 E1): the rules, run against the real engines ----
# figureRules.js (the file the site's transformer and the build's helper both
# import) runs every tidy and cacheKey case in Node; the helper, driven as a
# build drives it, answers every texErrors case with real TeX and every
# functionplot case with the real evaluator.
echo ""
echo "🔎 Checking the figure rules against the real engines…"
if docker run --rm \
  --mount "$(bind_mount_argument "$(pwd)/scripts/check_figure_rules_against_the_site.py" /opt/scripts/check_figure_rules_against_the_site.py),readonly" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/check_figure_rules_against_the_site.py \
  >/tmp/verify_figure_rules_site.log 2>&1; then
  pass "every figureFences case holds in the real engines: the shared rules in Node, TeX's own errors, the graph evaluator (scripts/check_figure_rules_against_the_site.py, #485)"
else
  fail "every figureFences case holds in the real engines (scripts/check_figure_rules_against_the_site.py, #485)"
  cat /tmp/verify_figure_rules_site.log
fi

# Every figure in the example courses draws, with its description, in the
# real engines (#485 E1): a payload's figure that could not be drawn would
# put "This diagram couldn't be drawn." on a page a teacher just installed.
if docker run --rm "$DEV_TEST_IMAGE" python3 -c '
import sys, tempfile, shutil
from pathlib import Path
sys.path.insert(0, "/opt/scripts")
import figures, toolchain_paths
root = toolchain_paths.SUPPORT_DIR / "example_content"
pages = []
for page in sorted(root.rglob("*.md")):
    text = page.read_text(encoding="utf-8")
    if "```tikz" in text or "```functionplot" in text:
        pages.append({"place": str(page.relative_to(root))[:-3], "text": text, "source": text})
work = Path(tempfile.mkdtemp())
rules = work / "quartz" / "plugins" / "transformers"
rules.mkdir(parents=True)
shutil.copyfile(toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers" / "figureRules.js", rules / "figureRules.js")
(work / "package.json").write_text("{\"type\": \"module\"}")
outcome = figures.prepare(pages, work, work / "cache")
count = outcome["figures"]
print(str(count) + " figure(s) on " + str(len(pages)) + " page(s)")
sys.exit(1 if outcome["problems"] or outcome["notes"] or outcome["figures"] == 0 else 0)
' >/tmp/verify_payload_figures.log 2>&1; then
  pass "every diagram and graph in the example courses draws, each with its description ($(tail -1 /tmp/verify_payload_figures.log), #485)"
else
  fail "a diagram or graph in the example courses cannot be drawn, or has no description (#485)"
  cat /tmp/verify_payload_figures.log
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
check_baked scripts/markdown_code.py      /opt/scripts/markdown_code.py
check_baked scripts/how_i_teach.py        /opt/scripts/how_i_teach.py
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
# Printable pages (#454): the two modules, Plantoir's additions to Quartz, and
# the guidance the app writes into each working folder.
check_baked scripts/page_features.py      /opt/scripts/page_features.py
check_baked scripts/print_settings.py     /opt/scripts/print_settings.py
# Diagrams and graphs (#485 E1): the build's pass, and (in the loop) the
# helper, its lockfile and the site's transformer, script and styles.
check_baked scripts/figures.py            /opt/scripts/figures.py
# Runnable Swift (#493): plan and prepare; and (in the loop) the Swift image's
# recipe, which the build hashes for its toolchain id, and the page's thread.
check_baked scripts/swift_blocks.py       /opt/scripts/swift_blocks.py
# Self-check quizzes (#563): the folder check. The site's transformer, script
# and styles are in support/quartz (the loop below).
check_baked scripts/quizzes.py            /opt/scripts/quizzes.py
# My Progress (#545): the gate, the page and its Key Links entry. The site's
# emitter, rules, script and styles are in support/quartz (the loop below).
check_baked scripts/my_progress.py        /opt/scripts/my_progress.py
# Live input (#583): which pages a publish isolates. The preview's half is in
# support/quartz (the loop below).
check_baked scripts/isolation_headers.py  /opt/scripts/isolation_headers.py
while IFS= read -r addition; do
  check_baked "$addition" "/opt/$addition"
done < <(find support/quartz support/agent_guidance support/figures support/gated support/swift -type f ! -name '.*' | sort)
# The print engine itself, by the hash the pin carries (contracts/toolchain.json).
PAGEDJS_PIN="$(python3 -c 'import json; print([p["fileSha256"] for p in json.load(open("contracts/toolchain.json"))["pins"] if p["pin"] == "pagedjs"][0])')"
PAGEDJS_BAKED="$(docker run --rm "$DEV_TEST_IMAGE" sha256sum /opt/vendor/pagedjs/paged.min.js 2>/dev/null | cut -d' ' -f1)"
if [[ "$PAGEDJS_BAKED" == "$PAGEDJS_PIN" ]]; then
  pass "The image carries Paged.js at /opt/vendor/pagedjs, matching the pin (#454)"
else
  fail "The image's /opt/vendor/pagedjs/paged.min.js is '${PAGEDJS_BAKED:-missing}', not the pinned $PAGEDJS_PIN"
fi
# The faces a handout is set in (#499), by the hashes the pin carries: the
# Dockerfile takes them from Debian without a hash, so this is where a
# changed file is noticed.
LM_PROBLEMS="$(python3 - "$DEV_TEST_IMAGE" <<'LMPY'
import json, subprocess, sys
pin = [p for p in json.load(open("contracts/toolchain.json"))["pins"] if p["pin"] == "latinModern"][0]
names = sorted(pin["files"])
out = subprocess.run(["docker", "run", "--rm", sys.argv[1], "sh", "-c",
                      "cd /opt/vendor/pagedjs/fonts && sha256sum " + " ".join(names) + " && ls LICENSE-Latin-Modern.txt"],
                     capture_output=True, text=True).stdout
baked = {}
for line in out.splitlines():
    parts = line.split()
    if len(parts) == 2:
        baked[parts[1]] = parts[0]
problems = [f"{name} is {baked.get(name, 'missing')}" for name in names if baked.get(name) != pin["files"][name]]
if "LICENSE-Latin-Modern.txt" not in out:
    problems.append("the licence is missing")
print("; ".join(problems))
LMPY
)"
if [[ -z "$LM_PROBLEMS" ]]; then
  pass "The image carries the six Latin Modern faces at /opt/vendor/pagedjs/fonts, matching the pin, with their licence (#499)"
else
  fail "The image's Latin Modern faces do not match contracts/toolchain.json: $LM_PROBLEMS"
fi
# The two figure engines (#485 E1), by the hashes their pins carry:
# function-plot's file, node-tikzjax's version, and its TeX engine's three
# files - the ones that are byte-identical to the Obsidian plugin's.
FIGURE_ENGINE_PROBLEMS="$(python3 - "$DEV_TEST_IMAGE" <<'FEPY'
import json, subprocess, sys
pins = {p["pin"]: p for p in json.load(open("contracts/toolchain.json"))["pins"]}
plot, tikz = pins["functionPlot"], pins["nodeTikzjax"]
files = sorted(tikz["files"])
script = ("sha256sum /opt/vendor/function-plot/function-plot.js && ls /opt/vendor/function-plot/LICENSE"
          " && cd /opt/vendor/tikz-engine/node_modules/node-tikzjax && sha256sum " + " ".join(files)
          + " && node -p 'require(\"./package.json\").version' && ls css/bakoma/LICENCE")
out = subprocess.run(["docker", "run", "--rm", sys.argv[1], "sh", "-c", script], capture_output=True, text=True).stdout
problems = []
if plot["fileSha256"] + "  /opt/vendor/function-plot/function-plot.js" not in out:
    problems.append("function-plot.js does not match its pin")
for name in files:
    if tikz["files"][name] + "  " + name not in out:
        problems.append(f"node-tikzjax's {name} does not match its pin")
if "\n" + tikz["value"] + "\n" not in "\n" + out:
    problems.append(f"node-tikzjax is not {tikz['value']}")
for licence in ("LICENSE", "css/bakoma/LICENCE"):
    if licence not in out:
        problems.append(f"{licence} is missing")
print("; ".join(problems))
FEPY
)"
if [[ -z "$FIGURE_ENGINE_PROBLEMS" ]]; then
  pass "The image carries function-plot and node-tikzjax at /opt/vendor, matching their pins, with their licences (#485)"
else
  fail "The image's figure engines do not match contracts/toolchain.json: $FIGURE_ENGINE_PROBLEMS"
fi
# Runnable code's engine (#455) and the site's own KaTeX (#494), by their
# pins: exactly the five Pyodide files, each matching, with the README that
# names the licence; and Quartz's katex at the pinned version, with the three
# files a site carries hashed.
RUNNER_ENGINE_PROBLEMS="$(python3 - "$DEV_TEST_IMAGE" <<'REPY'
import json, subprocess, sys
pins = {p["pin"]: p for p in json.load(open("contracts/toolchain.json"))["pins"]}
pyodide, katex = pins["pyodide"], pins["katex"]
names = sorted(pyodide["files"])
kfiles = sorted(katex["files"])
script = ("cd /opt/vendor/pyodide && ls -1 && echo LISTED && sha256sum " + " ".join(names)
          + " && cat README.txt && cd /opt/quartz/node_modules/katex && node -p 'require(\"./package.json\").version' && sha256sum " + " ".join(kfiles))
out = subprocess.run(["docker", "run", "--rm", sys.argv[1], "sh", "-c", script], capture_output=True, text=True).stdout
problems = []
listed = out.split("LISTED\n", 1)[0].split()
if sorted(listed) != sorted(names + ["README.txt"]):
    problems.append(f"/opt/vendor/pyodide holds {sorted(listed)}, not the five pinned files and the README")
for name in names:
    if pyodide["files"][name] + "  " + name not in out:
        problems.append(f"Pyodide's {name} does not match its pin")
if "MPL-2.0" not in out:
    problems.append("Pyodide's README does not name its licence")
if "\n" + katex["value"] + "\n" not in "\n" + out:
    problems.append(f"Quartz's katex is not {katex['value']}")
for name in kfiles:
    if katex["files"][name] + "  " + name not in out:
        problems.append(f"katex's {name} does not match its pin")
print("; ".join(problems))
REPY
)"
if [[ -z "$RUNNER_ENGINE_PROBLEMS" ]]; then
  pass "The image carries Pyodide at /opt/vendor/pyodide (the five pinned files and its README) and Quartz's katex at the pinned version, matching their pins (#455, #494)"
else
  fail "The image's Pyodide or katex does not match contracts/toolchain.json: $RUNNER_ENGINE_PROBLEMS"
fi
[[ "$BAKED_OK" == "true" ]] && pass "Baked scripts, patches, and support files match the working tree"

# -------------------- 4a. The live-reload client is still the one the rule names --------------------
# Every check for "this site is a preview's" looks for the client's script tag
# followed by its first statement (contracts/app-rules.json ->
# buildFreshness.previewBuild.signature, #291). Those bytes are Quartz's, not
# ours: if a Quartz raise or a patch changes them, the rule matches NOTHING,
# every preview reads as a production build, and a preview is published — the
# one catastrophic direction. So the source that produces them is asked for
# here, in the image, which takes seconds rather than a serve cycle and fails
# the day Quartz is raised. verify-deploy.sh checks a real serve-mode page
# against the rule as well.
#
# The client's template is checked for ADJACENCY, not for its words: the
# inline script's template literal must open with nothing but whitespace
# before `const socket = new WebSocket(`, read as one record in the C locale
# as deploy.sh reads a page. Three separate `grep -F`s (the first version)
# would all still pass if a Quartz raise put a comment or "use strict" first,
# and the rule would then match nothing (found by review, #291). The other two
# lines — the address and the tag's type — are words, so a fixed string does.
echo ""
echo "🔎 Checking the image's Quartz still writes the live-reload client the preview rule looks for…"
CLIENT_OK="true"
check_client_source() {
  local image_path="$1" expected="$2"
  if ! docker run --rm "$DEV_TEST_IMAGE" grep -Fq -- "$expected" "$image_path" 2>/dev/null; then
    CLIENT_OK="false"
    fail "$image_path no longer holds: $expected — re-measure the preview rule in contracts/app-rules.json (#291)"
  fi
}
QUARTZ_CLIENT_TEMPLATE='script: `[[:space:]]*const socket = new WebSocket('"'"'${wsUrl}'"'"')'
if ! docker run --rm -e LC_ALL=C "$DEV_TEST_IMAGE" grep -zq -- "$QUARTZ_CLIENT_TEMPLATE" /opt/quartz/quartz/plugins/index.ts 2>/dev/null; then
  CLIENT_OK="false"
  fail "/opt/quartz/quartz/plugins/index.ts no longer opens the live-reload script with const socket = new WebSocket(…) — re-measure the preview rule in contracts/app-rules.json (#291)"
fi
check_client_source /opt/quartz/quartz/plugins/index.ts 'ws://localhost:${ctx.argv.wsPort}'
check_client_source /opt/quartz/quartz/util/resources.tsx 'moduleType ?? "application/javascript"'
[[ "$CLIENT_OK" == "true" ]] && pass "The image's Quartz writes the live-reload client the preview rule looks for (#291)"

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
for layout in /opt/quartz/quartz.layout.ts; do
  if ! docker run --rm "$DEV_TEST_IMAGE" grep -Pzoq '//[ \t]*CQ4T-OMIT-ANCHOR:[^\n]*\n[ \t]*const[ \t]+omit[ \t]*=[ \t]*new[ \t]+Set' "$layout" 2>/dev/null; then
    fail "The Explorer's hide filter is missing or structurally detached from $layout in the image — hidden pages would be published"
    ANCHOR_OK="false"
  fi
done
[[ "$ANCHOR_OK" == "true" ]] && pass "The Explorer's hide filter is baked into the image and wired to a live omit Set"

# #334: the unused second copy of the scaffold is gone (it was 468 MB of
# image disk that nothing read), and Quartz is a one-commit clone.
if docker run --rm "$DEV_TEST_IMAGE" test -e /opt/quartz-site; then
  fail "The image still carries /opt/quartz-site, which nothing reads (#334)"
else
  pass "The image carries one copy of the website builder's scaffold (#334)"
fi
QUARTZ_COMMITS="$(docker run --rm "$DEV_TEST_IMAGE" git -C /opt/quartz rev-list --count HEAD 2>/dev/null || echo "?")"
if [[ "$QUARTZ_COMMITS" == "1" ]]; then
  pass "Quartz is cloned at depth 1: the tag's one commit (#334)"
else
  fail "Quartz carries ${QUARTZ_COMMITS} commits of history; the clone should be depth 1 (#334)"
fi

# -------------------- 4c. The Swift gate (#493) --------------------
# The Swift image is built from support/swift under the tag the launcher
# itself computes (preview.sh's toolchain_hash over that folder ONLY), so the
# build in section 5 finds it and compiles its planted blocks without
# building it again. Reused when it is already on this Mac, as the launcher
# would; --no-cache rebuilds it. Then every swift-gate/ fragment is compiled
# in it and run through the site's own WASI shim in Node
# (browser-checks/wasi_run.mjs): the library each compiled with, its output,
# its trap and Fatal-error line, the stdin echo, and the must-fail that the
# Fatal-error line is LOST without the shim's rights (spike G5, review S10).
# Skipped, saying why, when the image cannot be built (offline the first time).
eval "$(sed -n '/^toolchain_hash() {/,/^}/p' preview.sh)"
SWIFT_GATE_TAG="teaching-quartz-swift:src-$(toolchain_hash support/swift)"
SWIFT_GATE_DIR="$HOME/.plantoir-verify-swift-gate"
SWIFT_GATE_READY="false"
echo ""
echo "🦅 The Swift gate: ${SWIFT_GATE_TAG}…"
SWIFT_BUILD_STARTED=$(date +%s)
if [[ -z "$NO_CACHE" ]] && docker image inspect "$SWIFT_GATE_TAG" >/dev/null 2>&1; then
  SWIFT_GATE_READY="true"
  SWIFT_BUILT_HOW="already on this Mac"
elif docker buildx build --load $NO_CACHE --progress=plain -t "$SWIFT_GATE_TAG" support/swift >/tmp/verify_swift_image.log 2>&1; then
  SWIFT_GATE_READY="true"
  SWIFT_BUILT_HOW="built in $(( $(date +%s) - SWIFT_BUILD_STARTED )) s"
fi
if [[ "$SWIFT_GATE_READY" == "true" ]]; then
  SWIFT_IMAGE_SIZE="$(docker images --format '{{.Size}}' "$SWIFT_GATE_TAG" 2>/dev/null | head -1)"
  pass "the Swift image exists from support/swift ($SWIFT_BUILT_HOW, ${SWIFT_IMAGE_SIZE:-size unknown}) (#493)"
  # The trim (ruling Q2) and the off-PATH wasm-opt (Phase 0 trap 1), as built.
  if docker run --rm "$SWIFT_GATE_TAG" sh -c 'test ! -e /opt/swift/usr/bin/lldb && test ! -e /opt/swift/usr/bin/sourcekit-lsp && test ! -e /opt/swift/usr/lib/swift_static && ! command -v wasm-opt >/dev/null && test -x /opt/binaryen/bin/wasm-opt && test -d /opt/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle' >/dev/null 2>&1; then
    pass "the Swift image is trimmed (no lldb, sourcekit or host libraries), its SDK is installed, and wasm-opt is off PATH (#493)"
  else
    fail "the Swift image is not trimmed as its recipe says, lacks its SDK, or has wasm-opt on PATH (#493)"
  fi
  rm -rf "$SWIFT_GATE_DIR"
  mkdir -p "$SWIFT_GATE_DIR/jobs" "$SWIFT_GATE_DIR/out" "$SWIFT_GATE_DIR/again/jobs" "$SWIFT_GATE_DIR/again/out"
  cp swift-gate/*.swift "$SWIFT_GATE_DIR/jobs/"
  cp swift-gate/01-greeting.swift swift-gate/05-arrays.swift "$SWIFT_GATE_DIR/again/jobs/"
  SWIFT_COMPILE_STARTED=$(date +%s)
  docker run --rm --network none --mount "$(bind_mount_argument "$SWIFT_GATE_DIR" "$SWIFT_GATE_DIR")" \
    "$SWIFT_GATE_TAG" python3 /opt/plantoir-swift/compile.py "$SWIFT_GATE_DIR/jobs" "$SWIFT_GATE_DIR/out" \
    >/tmp/verify_swift_compile.log 2>&1
  SWIFT_COMPILE_SECONDS=$(( $(date +%s) - SWIFT_COMPILE_STARTED ))
  if node browser-checks/wasi_run.mjs swift-gate "$SWIFT_GATE_DIR/out" >/tmp/verify_swift_gate.log 2>&1; then
    pass "the Swift gate: all $(ls swift-gate/*.swift | wc -l | tr -d ' ') fragments compiled in ${SWIFT_COMPILE_SECONDS} s with the library swift-gate/expected.json names, ran through the site's WASI shim as expected, traps kept their Fatal error line, input echoed after its prompt, and the G5 must-fail failed (browser-checks/wasi_run.mjs, #493)"
  else
    fail "the Swift gate: a fragment did not compile, chose the wrong library, printed the wrong thing or lost its Fatal error line (browser-checks/wasi_run.mjs, #493)"
    cat /tmp/verify_swift_compile.log /tmp/verify_swift_gate.log
  fi
  sed -n '/^| fragment/,/^| G5/p' /tmp/verify_swift_gate.log
  # The same code compiles to the same bytes in a second container (spike G4:
  # the object file's path is fixed per key).
  docker run --rm --network none --mount "$(bind_mount_argument "$SWIFT_GATE_DIR" "$SWIFT_GATE_DIR")" \
    "$SWIFT_GATE_TAG" python3 /opt/plantoir-swift/compile.py "$SWIFT_GATE_DIR/again/jobs" "$SWIFT_GATE_DIR/again/out" \
    >/tmp/verify_swift_again.log 2>&1
  if cmp -s "$SWIFT_GATE_DIR/out/01-greeting.wasm" "$SWIFT_GATE_DIR/again/out/01-greeting.wasm" \
     && cmp -s "$SWIFT_GATE_DIR/out/05-arrays.wasm" "$SWIFT_GATE_DIR/again/out/05-arrays.wasm"; then
    pass "the Swift image compiles the same code to the same bytes in a second run (spike G4, #493)"
  else
    fail "the Swift image compiled the same code to different bytes in a second run (spike G4, #493)"
  fi
  rm -rf "$SWIFT_GATE_DIR"
else
  RESULTS+=("⏭️  SKIPPED  the Swift gate (#493): the Swift image could not be built - the first build needs the internet (/tmp/verify_swift_image.log)")
  echo "⏭️  SKIPPED  the Swift gate: the Swift image could not be built (see /tmp/verify_swift_image.log)"
fi

# -------------------- 5. Drive the real launcher against the image --------------------
echo ""
echo "🧹 Removing existing '$CONTAINER_NAME' container so the launcher recreates it"
echo "   from ${DEV_TEST_IMAGE}…"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

# ---- #209: How I Teach pages, planted for the build below ----
# Three pages, each carrying its own sentinel phrase so the check after the
# build can look for the WORDS anywhere in the site (pages, contentIndex.json,
# the sitemap, the RSS feed) rather than for a file name — the section's page
# is spelled in capitals, whose web address a case-sensitive name check would
# miss (#209 plan review, item 9). The course's settings are made to LIST the
# two reserved pages, the way a course whose page predates the rule does, so
# the preflight drop runs for real.
#
# They are put back by an EXIT trap, not only at the end of 6h: the fixture is
# the developer's own git-ignored course, and a run stopped between here and
# the check (^C, HUP, a hard exit) must not leave three pages and an edited
# configuration for the next run to start from (#209 implementation review,
# item 4). The build's preflight also rewrites course_config.backup.json, so
# that is kept and put back too — or removed if there was none.
HIT_COURSE="courses/EXC2O"
HIT_CONFIG_BACKUP="$(mktemp -t cq4t-hit-config)"
HIT_CONFIG_BACKUP_BACKUP="$(mktemp -t cq4t-hit-config-backup)"
cp "$HIT_COURSE/course_config.json" "$HIT_CONFIG_BACKUP"
HIT_HAD_CONFIG_BACKUP="no"
if [[ -f "$HIT_COURSE/course_config.backup.json" ]]; then
  cp "$HIT_COURSE/course_config.backup.json" "$HIT_CONFIG_BACKUP_BACKUP"
  HIT_HAD_CONFIG_BACKUP="yes"
fi
restore_hit_fixture() {
  [[ -n "${HIT_CONFIG_BACKUP:-}" && -f "$HIT_CONFIG_BACKUP" ]] || return 0
  rm -f "$HIT_COURSE/How I Teach.md" "$HIT_COURSE/section1/HOW I TEACH.md" "$HIT_COURSE/How I Teach 1.md"
  rm -f "$HIT_COURSE/Plain Long Page.md"
  rm -f "$HIT_COURSE/Discussions/Marker Fixture Long.md" "$HIT_COURSE/Discussions/Marker Fixture Word.md"
  # Only a Discussions/Tasks this run made: it carries the marker file.
  # The marker proves this run made the folder, so the whole folder goes,
  # a stray .DS_Store included (the #515 fix review): removing the files one
  # by one and then rmdir left it behind, unmarked, when anything else was in it.
  if [[ -f "$HIT_COURSE/Discussions/Tasks/.plantoir-verify-fixture" ]]; then
    rm -rf "$HIT_COURSE/Discussions/Tasks"
  fi
  rm -f "$HIT_COURSE/Printable Fixture.md" "$HIT_COURSE/Printable Not Opted.md" \
        "$HIT_COURSE/Printable PDF Fixture.md" "$HIT_COURSE/Printable Bad PDF.md" \
        "$HIT_COURSE/Printable Too Tall.md" \
        "$HIT_COURSE/Figures Fixture.md" "$HIT_COURSE/Figures Hidden.md" \
        "$HIT_COURSE/Figures Math Heading.md" "$HIT_COURSE/Figures Exports Heading.md" \
        "$HIT_COURSE/Runner Fixture.md" "$HIT_COURSE/Runner Not Opted.md" "$HIT_COURSE/Runner Plain Twin.md" \
        "$HIT_COURSE/Runner Playground.md" "$HIT_COURSE/Runner Hidden.md" "$HIT_COURSE/Runner Autorun.md" \
        "$HIT_COURSE/Discussions/Runner Printable.md" \
        "$HIT_COURSE/Swift Playground.md" "$HIT_COURSE/Swift Hidden.md" \
        "$HIT_COURSE/Live Plain Link.md" "$HIT_COURSE/Live Framed.md" "$HIT_COURSE/Live Autorun.md" "$HIT_COURSE/Live Box.md" \
        "$HIT_COURSE/Discussions/Overall Backlinks Fixture.md" "$HIT_COURSE/Discussions/Overall Backlinks Specific.md" \
        "$HIT_COURSE/Curriculum/Z1. Planted 100% Overall.md" "$HIT_COURSE/Curriculum/Z1.1.md" \
        "$HIT_COURSE/Quiz Fixture.md" "$HIT_COURSE/Quiz CRLF.md" "$HIT_COURSE/Quiz Lookalikes.md" \
        "$HIT_COURSE/Quiz Printable.md" "$HIT_COURSE/Quiz Hidden.md" "$HIT_COURSE/Quiz Source.md" \
        "$HIT_COURSE/Quiz Host.md" "$HIT_COURSE/Quiz Playground.md" "$HIT_COURSE/Media/plantoir-quiz-choice.png" \
        "$HIT_COURSE/Quiz Code Shown.md" "$HIT_COURSE/Quiz Summary.md" "$HIT_COURSE/Quiz Twice.md" \
        "$HIT_COURSE/Quiz One Blank.md" \
        "$HIT_COURSE/Task Fixture.md" "$HIT_COURSE/Task CRLF.md" "$HIT_COURSE/Task Host.md" \
        "$HIT_COURSE/Task Twin A.md" "$HIT_COURSE/Task Twin B.md" "$HIT_COURSE/Task Printable.md" \
        "$HIT_COURSE/Task Raw Box.md" "$HIT_COURSE/Progress Fixture.md" \
        "$HIT_COURSE/Media/plantoir-print-fixture & key.pdf" \
        "$HIT_COURSE/Media/plantoir-hazard-tall.png" "$HIT_COURSE/Media/plantoir-hazard-wide.png" \
        "$HIT_COURSE/Media/plantoir-hazard-viewbox.svg"
  if [[ -n "${PROGRESS_CLASS_BACKUP:-}" && -f "$PROGRESS_CLASS_BACKUP" ]]; then
    cp "$PROGRESS_CLASS_BACKUP" "$HIT_COURSE/section1/All Classes/Unit 1, Day 2.md"
    rm -f "$PROGRESS_CLASS_BACKUP"
  fi
  # #596: what the page-authoring skill's examples planted, by the list they left.
  if [[ -f /tmp/verify_authoring_planted.txt ]]; then
    while IFS= read -r planted; do
      [[ -n "$planted" ]] && rm -f "$HIT_COURSE/$planted"
    done < /tmp/verify_authoring_planted.txt
    rm -f /tmp/verify_authoring_planted.txt
  fi
  cp "$HIT_CONFIG_BACKUP" "$HIT_COURSE/course_config.json"
  if [[ "$HIT_HAD_CONFIG_BACKUP" == "yes" ]]; then
    cp "$HIT_CONFIG_BACKUP_BACKUP" "$HIT_COURSE/course_config.backup.json"
  else
    rm -f "$HIT_COURSE/course_config.backup.json"
  fi
  rm -f "$HIT_CONFIG_BACKUP" "$HIT_CONFIG_BACKUP_BACKUP"
}
trap 'restore_hit_fixture; release_verify_lock' EXIT
printf 'I teach by plantoir-hit-sentinel-course-7f3a.\n' > "$HIT_COURSE/How I Teach.md"
printf 'I teach by plantoir-hit-sentinel-section-7f3a.\n' > "$HIT_COURSE/section1/HOW I TEACH.md"
printf 'A look-alike page: plantoir-hit-sentinel-lookalike-7f3a.\n' > "$HIT_COURSE/How I Teach 1.md"
python3 - "$HIT_COURSE/course_config.json" <<'PY'
import json, sys
path = sys.argv[1]
config = json.load(open(path, encoding="utf-8"))
config.setdefault("shared_files", []).append("How I Teach.md")
config.setdefault("per_section_files", []).append("HOW I TEACH.md")
json.dump(config, open(path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PY

# ---- #454: printable pages, planted for the same build ----
# A worksheet with one callout per answerCallouts shape, a numbered list, a
# hint, a self-check, an answer left open, maths, a diagram, code, a figure
# and a Curriculum connection between two questions, as the skeleton templates
# write one (#498: never printed); the SAME page without `printable:` (it must come out with no print
# markup at all); a page with its own PDF (a name with `&` and a space, so the
# web address is Quartz's slug and not a guess); and a page whose PDF is not
# there. Removed by restore_hit_fixture with the pages above.
cat > "$HIT_COURSE/Printable Fixture.md" <<'PRINTFIXTURE'
---
title: Printable Fixture
printable: true
tags:
  - reference
---
A worksheet planted by verify.sh (plantoir-print-sentinel-7f3a). Try each question before you open its answer.

## Question 1

Simplify $(x + 3)(x - 2)$.[^1]

> [!success]- Answer 1
> $x^2 + x - 6$

## Question 2

Factor $x^2 - 9$ completely.

> [!SOLUTION]-
> $(x - 3)(x + 3)$, a difference of squares.

%%curriculum-start%%
## Curriculum connection

%%
The skeleton templates' note to the teacher.
%%

![[B1.1]]

### Where it leads

Linked on purpose (plantoir-curriculum-sentinel-7f3a).
%%curriculum-end%%

## Practice

1. Expand $(2x + 1)^2$.
   > [!check]-
   >
   > $4x^2 + 4x + 1$
2. Expand $(x - 5)^2$.
3. Expand $(x + 4)(x - 4)$.
   > [!success]-
   >
   > $x^2 - 16$

> [!tip]- Need a hint? (click to expand)
> A difference of squares $a^2 - b^2$ factors as $(a - b)(a + b)$.

> [!question]- Self-check: which expansions gave a perfect square?
> Questions 1 and 2 of the practice list.

> [!success] Worked example (left open on purpose)
> $(x + 1)^2 = x^2 + 2x + 1$

> [!note]- Solution & Visual Check (click to expand)
> The parabola $y = x^2 - 9$ crosses the axis at $x = \pm 3$.

$$
x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
$$

```mermaid
flowchart LR
  A[Expand] --> B[Collect like terms] --> C[Factor]
```

```python
def area(width, height):
    return width * height
```

<figure class="pl-figure pl-test"><svg viewBox="0 0 200 100" width="400" height="200" xmlns="http://www.w3.org/2000/svg"><rect x="10" y="10" width="180" height="80" fill="none" stroke="black"/><text x="100" y="55" text-anchor="middle">plantoir figure</text></svg><figcaption>A figure an engine would draw.</figcaption></figure>

Before the drawn figures (plantoir-before-figures).

```tikz
% alt: A right triangle with legs 3 and 4
\begin{document}
\begin{tikzpicture}
\draw[thick] (0,0) -- (4,0) node[midway, below]{$4$} -- (4,3) node[midway, right]{$3$} -- cycle;
\end{tikzpicture}
\end{document}
```

```functionplot
---
bounds: [-4, 4, -2, 8]
alt: The parabola y = x^2
---
y = x^2
```

```tikz
% alt: A ladder 24 cm tall, taller than either paper (E1 review B1)
\begin{document}
\begin{tikzpicture}
\draw[thick] (0,0) -- (0,24) (1,0) -- (1,24);
\foreach \y in {1,...,23} \draw (0,\y) -- (1,\y) node[right]{\y};
\end{tikzpicture}
\end{document}
```

After the drawn figures (plantoir-after-figures).

## Question 3

Name each part of the expansion of $(x + 3)^2$ (plantoir-qstem-3).

1. The first term.
   > [!answer]-
   >
   > $x^2$ (plantoir-ans-3a)
2. The last term.
   > [!answer]-
   >
   > $9$ (plantoir-ans-3b)
3. The middle term.

> [!question] Question 4
> Explain why a difference of squares has no middle term (plantoir-qstem-4).

> [!example] A perfect square
> $(x + 3)^2 = x^2 + 6x + 9$ (plantoir-example-sentinel-7f3a).

## Question 5

Read the program below and say what it counts to (plantoir-qstem-5).

```python
n = 1  # CODE-001
n = 2  # CODE-002
n = 3  # CODE-003
n = 4  # CODE-004
n = 5  # CODE-005
n = 6  # CODE-006
n = 7  # CODE-007
n = 8  # CODE-008
n = 9  # CODE-009
n = 10  # CODE-010
n = 11  # CODE-011
n = 12  # CODE-012
n = 13  # CODE-013
n = 14  # CODE-014
n = 15  # CODE-015
n = 16  # CODE-016
n = 17  # CODE-017
n = 18  # CODE-018
n = 19  # CODE-019
n = 20  # CODE-020
n = 21  # CODE-021
n = 22  # CODE-022
n = 23  # CODE-023
n = 24  # CODE-024
n = 25  # CODE-025
n = 26  # CODE-026
n = 27  # CODE-027
n = 28  # CODE-028
n = 29  # CODE-029
n = 30  # CODE-030
n = 31  # CODE-031
n = 32  # CODE-032
n = 33  # CODE-033
n = 34  # CODE-034
n = 35  # CODE-035
n = 36  # CODE-036
n = 37  # CODE-037
n = 38  # CODE-038
n = 39  # CODE-039
n = 40  # CODE-040
n = 41  # CODE-041
n = 42  # CODE-042
n = 43  # CODE-043
n = 44  # CODE-044
n = 45  # CODE-045
n = 46  # CODE-046
n = 47  # CODE-047
n = 48  # CODE-048
n = 49  # CODE-049
n = 50  # CODE-050
n = 51  # CODE-051
n = 52  # CODE-052
n = 53  # CODE-053
n = 54  # CODE-054
n = 55  # CODE-055
n = 56  # CODE-056
n = 57  # CODE-057 and a comment long enough to wrap onto a second line on letter paper in portrait (plantoir-wrap-sentinel)
n = 58  # CODE-058
n = 59  # CODE-059
n = 60  # CODE-060
n = 61  # CODE-061
n = 62  # CODE-062
n = 63  # CODE-063
n = 64  # CODE-064
n = 65  # CODE-065
n = 66  # CODE-066
n = 67  # CODE-067
n = 68  # CODE-068
n = 69  # CODE-069
n = 70  # CODE-070
n = 71  # CODE-071
n = 72  # CODE-072
n = 73  # CODE-073
n = 74  # CODE-074
n = 75  # CODE-075
n = 76  # CODE-076
n = 77  # CODE-077
n = 78  # CODE-078
n = 79  # CODE-079
n = 80  # CODE-080
n = 81  # CODE-081
n = 82  # CODE-082
n = 83  # CODE-083
n = 84  # CODE-084
n = 85  # CODE-085
n = 86  # CODE-086
n = 87  # CODE-087
n = 88  # CODE-088
n = 89  # CODE-089
n = 90  # CODE-090
n = 91  # CODE-091
n = 92  # CODE-092
n = 93  # CODE-093
n = 94  # CODE-094
n = 95  # CODE-095
n = 96  # CODE-096
n = 97  # CODE-097
n = 98  # CODE-098
n = 99  # CODE-099
n = 100  # CODE-100
n = 101  # CODE-101
n = 102  # CODE-102
n = 103  # CODE-103
n = 104  # CODE-104
n = 105  # CODE-105
n = 106  # CODE-106
n = 107  # CODE-107
n = 108  # CODE-108
n = 109  # CODE-109
n = 110  # CODE-110
```

And a line too long for the paper, which wraps (plantoir-wrap-7f3a):

```python
print("WRAP-7f3a: a line of code much longer than a printed page is wide, in portrait or in landscape, so that it wraps onto a second row and then onto a third, whichever way the paper is turned")
```

> [!SOLUTION]-
>
> It counts to 110 (plantoir-ans-5), and its output looks like this (plantoir-before-answer-picture):
>
> ![[plantoir-hazard-wide.png]]
>
> The picture is above (plantoir-after-answer-picture).

Before the picture (plantoir-before-tall).

![[plantoir-hazard-tall.png]]

After the picture (plantoir-after-tall). Before the drawing (plantoir-before-viewbox).

![[plantoir-hazard-viewbox.svg]]

After the drawing (plantoir-after-viewbox). Before the diagram (plantoir-before-mermaid).

```mermaid
flowchart TD
  N1[MM-01] --> N2[MM-02]
  N2[MM-02] --> N3[MM-03]
  N3[MM-03] --> N4[MM-04]
  N4[MM-04] --> N5[MM-05]
  N5[MM-05] --> N6[MM-06]
  N6[MM-06] --> N7[MM-07]
  N7[MM-07] --> N8[MM-08]
  N8[MM-08] --> N9[MM-09]
  N9[MM-09] --> N10[MM-10]
  N10[MM-10] --> N11[MM-11]
  N11[MM-11] --> N12[MM-12]
  N12[MM-12] --> N13[MM-13]
  N13[MM-13] --> N14[MM-14]
  N14[MM-14] --> N15[MM-15]
  N15[MM-15] --> N16[MM-16]
  N16[MM-16] --> N17[MM-17]
  N17[MM-17] --> N18[MM-18]
  N18[MM-18] --> N19[MM-19]
  N19[MM-19] --> N20[MM-20]
  N20[MM-20] --> N21[MM-21]
  N21[MM-21] --> N22[MM-22]
  N22[MM-22] --> N23[MM-23]
  N23[MM-23] --> N24[MM-24]
  N24[MM-24] --> N25[MM-25]
  N25[MM-25] --> N26[MM-26]
  N26[MM-26] --> N27[MM-27]
  N27[MM-27] --> N28[MM-28]
  N28[MM-28] --> N29[MM-29]
  N29[MM-29] --> N30[MM-30]
```

After the diagram (plantoir-after-mermaid). Before the formulas (plantoir-before-katex).

$$
\begin{aligned}
y_{1} &= 1x + 1 \\
y_{2} &= 2x + 2 \\
y_{3} &= 3x + 3 \\
y_{4} &= 4x + 4 \\
y_{5} &= 5x + 5 \\
y_{6} &= 6x + 6 \\
y_{7} &= 7x + 7 \\
y_{8} &= 8x + 8 \\
y_{9} &= 9x + 9 \\
y_{10} &= 10x + 10 \\
y_{11} &= 11x + 11 \\
y_{12} &= 12x + 12 \\
y_{13} &= 13x + 13 \\
y_{14} &= 14x + 14 \\
y_{15} &= 15x + 15 \\
y_{16} &= 16x + 16 \\
y_{17} &= 17x + 17 \\
y_{18} &= 18x + 18 \\
y_{19} &= 19x + 19 \\
y_{20} &= 20x + 20
\end{aligned}
$$

After the formulas (plantoir-after-katex). Before the table (plantoir-before-table).

| Row | Square |
|---|---|
| TROW-01 | 1 |
| TROW-02 | 4 |
| TROW-03 | 9 |
| TROW-04 | 16 |
| TROW-05 | 25 |
| TROW-06 | 36 |
| TROW-07 | 49 |
| TROW-08 | 64 |
| TROW-09 | 81 |
| TROW-10 | 100 |
| TROW-11 | 121 |
| TROW-12 | 144 |
| TROW-13 | 169 |
| TROW-14 | 196 |
| TROW-15 | 225 |
| TROW-16 | 256 |
| TROW-17 | 289 |
| TROW-18 | 324 |
| TROW-19 | 361 |
| TROW-20 | 400 |
| TROW-21 | 441 |
| TROW-22 | 484 |
| TROW-23 | 529 |
| TROW-24 | 576 |
| TROW-25 | 625 |
| TROW-26 | 676 |
| TROW-27 | 729 |
| TROW-28 | 784 |
| TROW-29 | 841 |
| TROW-30 | 900 |
| TROW-31 | 961 |
| TROW-32 | 1024 |
| TROW-33 | 1089 |
| TROW-34 | 1156 |
| TROW-35 | 1225 |
| TROW-36 | 1296 |
| TROW-37 | 1369 |
| TROW-38 | 1444 |
| TROW-39 | 1521 |
| TROW-40 | 1600 |

After the table (plantoir-after-table). Before the wide formula (plantoir-before-wide).

$$
y = a_{1} + a_{2} + a_{3} + a_{4} + a_{5} + a_{6} + a_{7} + a_{8} + a_{9} + a_{10} + a_{11} + a_{12} + a_{13} + a_{14} + a_{15} + a_{16} + a_{17} + a_{18} + a_{19} + a_{20} + a_{21} + a_{22} + a_{23} + a_{24} + a_{25} + a_{26} + a_{27} + a_{28} + a_{29} + a_{30} + a_{31} + a_{32} + a_{33} + a_{34} + a_{35} + a_{36} + a_{37} + a_{38} + a_{39} + a_{40} + a_{41} + a_{42} + a_{43} + a_{44} + a_{45} + a_{46} + a_{47} + a_{48} + a_{49} + a_{50} + a_{51} + a_{52} + a_{53} + a_{54} + a_{55} + a_{56} + a_{57} + a_{58} + a_{59} + \text{plantoirwideend}
$$

After the wide formula (plantoir-after-wide). Before the scaled formula (plantoir-before-scaled).

$$
y = a_{1}x^{1} + a_{2}x^{2} + a_{3}x^{3} + a_{4}x^{4} + a_{5}x^{5} + a_{6}x^{6} + a_{7}x^{7} + a_{8}x^{8} + a_{9}x^{9} + a_{10}x^{10} + a_{11}x^{11} + a_{12}x^{12} + a_{13}x^{13} + \text{plantoirscaledend}
$$

After the scaled formula (plantoir-after-scaled). Before the timetable (plantoir-before-timetable).

| Period | Day 1 | Day 2 | Day 3 | Day 4 | Day 5 | Day 6 | Day 7 | Day 8 | Day 9 | Day 10 | Day 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Math | Math | Math | Math | Math | Math | Math | Math | Math | Math | CELLEND1 |
| 2 | Science | Science | Science | Science | Science | Science | Science | Science | Science | Science | CELLEND2 |

After the timetable (plantoir-after-timetable).

## Curriculum connections

![[B1.2]]

Last on the page, as the templates put it (plantoir-curriculum-sentinel-7f3a).

[^1]: Multiply each term (plantoir-footnote-sentinel-7f3a).
PRINTFIXTURE
sed -e '/^printable: true$/d' -e 's/^title: Printable Fixture$/title: Printable Not Opted/' \
    -e 's/plantoir-print-sentinel-7f3a/plantoir-notopted-sentinel-7f3a/' \
    "$HIT_COURSE/Printable Fixture.md" > "$HIT_COURSE/Printable Not Opted.md"
# #501: a long page that is NOT printable, for ⌘P (browser-checks/
# print_plain_page.mjs): 40 paragraphs, each starting with its own sentinel,
# under headings and with lists, long enough to run under the folder list
# that used to be drawn over the article on paper.
{
  printf -- '---\ntitle: Plain Long Page\n---\n'
  for number in $(seq 0 39); do
    para="$(printf 'plantoir-plain-para-%02d' "$number")"
    (( number % 10 == 0 )) && printf '\n## Part %d\n' $(( number / 10 + 1 ))
    if (( number % 10 == 8 )); then
      printf '\n- %s a list item about the slope of a line\n' "$para"
    else
      printf '\n%s The class works out the slope of a line through two given points, then checks it against a graph drawn on the board and writes down what the number means.\n' "$para"
    fi
  done
} > "$HIT_COURSE/Plain Long Page.md"
# #515: the sidebar's page dot (browser-checks/sidebar_page_marker.mjs). A
# page inside Discussions whose title wraps in the sidebar at a laptop's width,
# and a folder inside Discussions with a page of its own, so a folder row sits
# among page rows. The folder is called Tasks because the sidebar gives a
# chevron to a folder whose NAME is in `expandable`, at any depth, and Tasks
# already is: adding a new name to `expandable` instead would change every
# page's HTML (Explorer.tsx writes the list into data-expandable), and the
# #485 check in 6c compares a page from this build with one built after the
# plants are gone. It has its own index.md so its sidebar name is its title
# whichever way Quartz reads a folder's name, and a marker file, so
# restore_hit_fixture removes only a folder this run made: a Discussions/Tasks
# that is already there is the developer's, and is neither written into nor
# deleted (the check then fails, saying the folder is not its fixture). A third
# page's title starts with a word too wide for the sidebar, so the dot is
# checked level with a first line that is not the title's first word's alone.
# Removed by restore_hit_fixture.
printf -- '---\ntitle: Marker Fixture Page With A Title Long Enough To Wrap Onto A Second Line\n---\nA page planted by verify.sh for the sidebar check (plantoir-marker-sentinel-7f3a).\n' \
  > "$HIT_COURSE/Discussions/Marker Fixture Long.md"
printf -- '---\ntitle: Electroencephalographicallycounterrevolutionarily debate\n---\nA page planted by verify.sh for the sidebar check.\n' \
  > "$HIT_COURSE/Discussions/Marker Fixture Word.md"
if [[ -e "$HIT_COURSE/Discussions/Tasks" ]]; then
  fail "the course already has a Discussions/Tasks folder, so the sidebar check's fixture was not planted there (#515): move it aside and run again"
else
  mkdir "$HIT_COURSE/Discussions/Tasks"
  printf 'Planted by verify.sh (#515); restore_hit_fixture removes this folder only while this file is in it.\n' \
    > "$HIT_COURSE/Discussions/Tasks/.plantoir-verify-fixture"
  printf -- '---\ntitle: Tasks\n---\nA folder planted by verify.sh for the sidebar check.\n' \
    > "$HIT_COURSE/Discussions/Tasks/index.md"
  printf -- '---\ntitle: Marker Fixture Inner Page\n---\nA page inside the planted folder.\n' \
    > "$HIT_COURSE/Discussions/Tasks/Marker Fixture Inner Page.md"
fi
mkdir -p "$HIT_COURSE/Media"
# Pictures for the worksheet's hazards (#499): a tall portrait one that must be
# scaled onto a page, a wide one inside a folded answer, and an SVG with only a
# viewBox. Drawn with the standard library alone (no Pillow on the Mac).
python3 - "$HIT_COURSE/Media" <<'PY'
import struct, sys, zlib
def png(path, width, height):
    rows = b"".join(b"\x00" + bytes((40 + (y * 7) % 180, 90, 160)) * width for y in range(height))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                  + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))
png(sys.argv[1] + "/plantoir-hazard-tall.png", 400, 1800)
png(sys.argv[1] + "/plantoir-hazard-wide.png", 900, 300)
open(sys.argv[1] + "/plantoir-hazard-viewbox.svg", "w").write(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 400"><rect x="5" y="5" width="90" height="390" fill="none" stroke="black"/></svg>\n')
PY
python3 - "$HIT_COURSE/Media/plantoir-print-fixture & key.pdf" <<'PY'
import sys
pdf = (b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
       b"2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
       b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj\n"
       b"trailer<</Root 1 0 R>>\n%EOF\n")
open(sys.argv[1], "wb").write(pdf)
PY
printf -- '---\nprintable: true\nprintPdf: "[[plantoir-print-fixture & key.pdf]]"\n---\nA page that hands out its own PDF (plantoir-printpdf-sentinel-7f3a).\n\n> [!success]- Answer 1\n>\n> Off the worksheet.\n' \
  > "$HIT_COURSE/Printable PDF Fixture.md"
printf -- '---\nprintable: true\nprintPdf: missing-7f3a.pdf\n---\nA page whose PDF is not there (plantoir-badpdf-sentinel-7f3a).\n' \
  > "$HIT_COURSE/Printable Bad PDF.md"
# A page that cannot print whole (#499 fix review B1): a displayed formula of
# 60 lines and a table row of 90, each taller than a page and unsplittable
# without losing lines. The handout must REFUSE it, in every paper - a guard
# that skips split pieces printed both half-missing and called them complete.
python3 - "$HIT_COURSE/Printable Too Tall.md" <<'PY'
import sys
formula = " \\\\\n".join(f"y_{{{i}}} &= {i}x + {i}" for i in range(1, 61))
cell = "<br>".join(f"TALLROW-{i:02d}" for i in range(1, 91))
open(sys.argv[1], "w").write("---\nprintable: true\n---\nBefore the tall formula (plantoir-toolong-sentinel-7f3a).\n\n$$\n\\begin{aligned}\n"
    + formula + "\n\\end{aligned}\n$$\n\n| Row | Lines |\n|---|---|\n| 1 | " + cell + " |\n\n> [!answer]-\n>\n> Never printed.\n")
PY

# ---- #485 E1: diagrams and graphs, planted for the same build ----
# Every place a fence can sit (top level, a folded callout, a list item), the
# packages that matter (pgfplots, circuitikz), a drawing with no description,
# one TeX cannot draw (\foo), one taller than a page, the same drawing twice
# (its ids must not clash), three graphs (one with zoom off, one that cannot be
# drawn), and a graph on a page students cannot see, which must not make the
# site carry the graph engine. Removed by restore_hit_fixture.
cat > "$HIT_COURSE/Figures Fixture.md" <<'FIGURESFIXTURE'
---
title: Figures Fixture
---
Diagrams and graphs planted by verify.sh (plantoir-figures-sentinel-7f3a).

```tikz
% alt: Two similar triangles, ABC and a 1.5 times enlargement DEF (plantoir-alt-triangles)
\begin{document}
\begin{tikzpicture}
  \draw[thick] (0,0) node[below left]{$A$} -- (3,0) node[below right]{$B$} -- (1,2) node[above]{$C$} -- cycle;
  \draw[thick] (5,0) node[below left]{$D$} -- (9.5,0) node[below right]{$E$} -- (6.5,3) node[above]{$F$} -- cycle;
  \node at (1.5,-0.5) {$3$};
  \node at (7.25,-0.5) {$4.5$};
\end{tikzpicture}
\end{document}
```

> [!example]- A tree diagram
> ```tikz
> % alt: A tree of two coin tosses (plantoir-alt-tree)
> \begin{document}
> \begin{tikzpicture}[level distance=1.5cm, sibling distance=2cm]
>   \node {Start}
>     child { node {H} child { node {HH} } child { node {HT} } }
>     child { node {T} child { node {TH} } child { node {TT} } };
> \end{tikzpicture}
> \end{document}
> ```

1. Read the graph of a cubic.

   ```tikz
   % alt: A cubic drawn with pgfplots (plantoir-alt-pgfplots)
   \usepackage{pgfplots}
   \pgfplotsset{compat=1.16}
   \begin{document}
   \begin{tikzpicture}
   \begin{axis}[axis lines=middle, xlabel=$x$, ylabel=$y$]
   \addplot[domain=-2:2, samples=40, red] {x^3 - x};
   \end{axis}
   \end{tikzpicture}
   \end{document}
   ```

```tikz
% alt: A circuit with a battery and a resistor (plantoir-alt-circuit)
\usepackage{circuitikz}
\begin{document}
\begin{circuitikz}
\draw (0,0) to[battery1, l=$V$] (0,2) to[R, l=$R$] (3,2) -- (3,0) -- (0,0);
\end{circuitikz}
\end{document}
```

```tikz
\begin{document}
\begin{tikzpicture}
\draw (0,0) circle (1);
\node[text=red] at (0,0) {$O$};
\end{tikzpicture}
\end{document}
```

Before the broken diagram (plantoir-before-broken).

```tikz
% alt: A diagram that cannot be drawn
\begin{document}
\begin{tikzpicture}
\foo
\end{tikzpicture}
\end{document}
```

After the broken diagram (plantoir-after-broken). Before the tall diagram (plantoir-before-tall-figure).

```tikz
% alt: A tall tree, three levels down (plantoir-alt-tall)
\begin{document}
\begin{tikzpicture}[grow=down, level distance=4.5cm, sibling distance=1.2cm]
  \node {Root}
    child { node {A} child { node {A1} child { node {A1a} } } }
    child { node {B} child { node {B1} child { node {B1a} } } };
\end{tikzpicture}
\end{document}
```

After the tall diagram (plantoir-after-tall-figure).

```tikz
% alt: A cubic drawn with pgfplots (plantoir-alt-pgfplots)
\usepackage{pgfplots}
\pgfplotsset{compat=1.16}
\begin{document}
\begin{tikzpicture}
\begin{axis}[axis lines=middle, xlabel=$x$, ylabel=$y$]
\addplot[domain=-2:2, samples=40, red] {x^3 - x};
\end{axis}
\end{tikzpicture}
\end{document}
```

```functionplot
---
title: Two lines
xLabel: x
yLabel: y
bounds: [-5, 5, -5, 5]
alt: Two lines crossing at (1, 3) (plantoir-alt-lines)
---
y = 2x + 1
y = -x + 4
```

```functionplot
---
bounds: [-6, 6, -6, 6]
disableZoom: true
---
y = 1/(x - 2) + 1
```

```functionplot
y = ln(x)
```

- ```functionplot
  ---
  alt: A line opened on a bullet's own line (E1 review S1)
  ---
  y = x/2
  ```
FIGURESFIXTURE
printf -- '---\ntitle: Figures Hidden\npublish: false\n---\nA hidden graph (plantoir-figures-hidden-7f3a).\n\n```functionplot\ny = x^2\n```\n' \
  > "$HIT_COURSE/Figures Hidden.md"
# #502: a heading "Math" is id="math", which answered window.math, and a
# heading "Exports" is id="exports", which answered window.exports - the two
# names function-plot reads as its file runs (figureFences.pageIds). Drawn in
# the browser by browser-checks/graphs_draw.mjs, below. Removed by
# restore_hit_fixture.
printf -- '---\ntitle: Figures Math Heading\n---\nA graph under a heading named Math (plantoir-figures-math-7f3a).\n\n# Math\n\n```functionplot\n---\nalt: A parabola under a Math heading\n---\ny = x^2 - 3\n```\n' \
  > "$HIT_COURSE/Figures Math Heading.md"
printf -- '---\ntitle: Figures Exports Heading\n---\nA graph under a heading named Exports (plantoir-figures-exports-7f3a).\n\n# Exports\n\n```functionplot\ny = x^3 - 2x\n```\n' \
  > "$HIT_COURSE/Figures Exports Heading.md"

# ---- #455: runnable code, planted for the same build ----
# Runner Fixture: one fence per contracts/shared-rules.json ->
# codeRunnerBlocks.fences case that opts in (each prints its own case number),
# then a fence on two list markers' line (never runnable: pageShapes) and a
# runner after it (counted). Runner Not Opted: the same fences on a page that
# does not opt in; Runner Plain Twin: the same code in plain ```python
# fences - the two must come out alike. Runner Playground: three blocks for
# the browser check; Discussions/Runner Printable: a printable page one
# folder down with a runner and a formula (the print-after-a-page-change
# check, #455 review S1); Runner Hidden: a page students cannot see, which
# must not make the site carry the engine or earn a plantoir: error: line.
# Removed by restore_hit_fixture.
python3 - "$HIT_COURSE" <<'RUNNERPLANTS'
import json, sys
from pathlib import Path
course = Path(sys.argv[1])
rules = json.load(open("contracts/shared-rules.json", encoding="utf-8"))["codeRunnerBlocks"]
fences = []
for number, case in enumerate(rules["fences"]["cases"], start=1):
    if not case["optedIn"]:
        continue
    fences.append((f"{case['lang']} {case['meta']}".rstrip(), f'print("case {number}")'))
body = "Runnable code planted by verify.sh (plantoir-runner-sentinel-7f3a).\n\n"
for info, code in fences:
    body += f"```{info}\n{code}\n```\n\n"
nested = '- - ```python run\n    print("nested shape")\n    ```\n\n```python run\nprint("after the nested shape")\n```\n'
(course / "Runner Fixture.md").write_text("---\ntitle: Runner Fixture\ncodeRunner: yes\n---\n" + body + nested, encoding="utf-8")
(course / "Runner Not Opted.md").write_text("---\ntitle: Runner Not Opted\n---\n" + body, encoding="utf-8")
# The twin keeps every other word of the info string (a title, line
# highlighting), so the only difference is the runner's own tokens.
import re
twin = "Runnable code planted by verify.sh (plantoir-runner-sentinel-7f3a).\n\n"
for info, code in fences:
    # Words as the site's parser splits them: on space and tab only, so a
    # no-break space stays inside its word (codeRunnerBlocks.fences, N2).
    words = [w for w in re.findall(r'[^ \t"]*"[^"]*"[^ \t]*|[^ \t]+', info) if w not in ("run", "readonly", "stdin", "autorun")]
    twin += f"```{' '.join(words)}\n{code}\n```\n\n"
(course / "Runner Plain Twin.md").write_text("---\ntitle: Runner Plain Twin\n---\n" + twin, encoding="utf-8")
(course / "Runner Playground.md").write_text(
    "---\ntitle: Runner Playground\ncodeRunner: true\n---\nThree blocks to run (plantoir-runner-playground-7f3a).\n\n"
    "```python run\nprint(\"one\")\n```\n\n```python run\nprint(\"two\")\n```\n\n"
    "> [!example]- In a folded callout\n> ```python run\n> print(\"three\")\n> ```\n\n"
    # #585: a plain block, whose numbers the editor's gutter must match.
    "A plain block (plantoir-runner-static-7f3a), and `a != b` written inline:\n\n```python\nprint(\"static\")\n```\n", encoding="utf-8")
(course / "Discussions" / "Runner Printable.md").write_text(
    "---\ntitle: Runner Printable\nprintable: true\ncodeRunner: true\n---\n"
    "A printable page with code (plantoir-runner-printable-7f3a), and a formula $\\frac{a}{b} = c^2$.\n\n"
    "1. What does this print?\n\n```python run\nprint(\"printed\")\n```\n", encoding="utf-8")
(course / "Runner Autorun.md").write_text(
    "---\ntitle: Runner Autorun\ncodeRunner: true\n---\nTwo blocks that run by themselves (plantoir-runner-autorun-7f3a).\n\n"
    "```python run autorun\nimport time\ntime.sleep(4)\nprint(\"first\")\n```\n\n"
    "```python run autorun\nimport time\ntime.sleep(3)\nprint(\"second\")\n```\n", encoding="utf-8")
(course / "Runner Hidden.md").write_text(
    "---\ntitle: Runner Hidden\npublish: false\ncodeRunner: true\n---\nHidden (plantoir-runner-hidden-7f3a).\n\n"
    "```python run\nprint(\"hidden\")\n```\n", encoding="utf-8")
# #493: Swift Playground - the blocks the Swift browser check runs (a
# greeting that reads input, a loop that never ends, an index out of range,
# exit(3), a block that does not compile, and one that needs the full
# library), and Swift Hidden, a page students cannot see, whose block is
# compiled (the plan is generous) but never reaches the site.
gate = Path("swift-gate")
playground = "---\ntitle: Swift Playground\ncodeRunner: yes\n---\nSwift to run (plantoir-swift-playground-7f3a).\n\n"
playground += "```swift run\n" + (gate / "01-greeting.swift").read_text(encoding="utf-8") + "```\n\n"
playground += "```swift run\nprint(\"spinning\")\nvar n = 0\nwhile true { n &+= 1 }\n```\n\n"
playground += "```swift run\n" + (gate / "10-out-of-range.swift").read_text(encoding="utf-8") + "```\n\n"
playground += "```swift run\n#if canImport(WASILibc)\nimport WASILibc\n#endif\nprint(\"leaving with 3\")\nexit(3)\n```\n\n"
playground += "Some words before the block that does not compile.\n\n"
playground += "```swift run\nlet name = readLine() ?? \"\"\nprint(nmae)\n```\n\n"
playground += "```swift run stdin\n" + (gate / "05-arrays.swift").read_text(encoding="utf-8") + "```\n"
# #583: a prompt on the answer's line (terminator: ""), for live input.
playground += "\n```swift run\n" + (gate / "13-prompt.swift").read_text(encoding="utf-8") + "```\n"
(course / "Swift Playground.md").write_text(playground, encoding="utf-8")
(course / "Swift Hidden.md").write_text(
    "---\ntitle: Swift Hidden\npublish: false\ncodeRunner: true\n---\nHidden (plantoir-swift-hidden-7f3a).\n\n"
    "```swift run\nprint(\"hidden swift\")\n```\n", encoding="utf-8")
# #583: live input. Live Plain Link: a plain page linking to the Runner
# Playground (the site's own link across the isolation line, one way); Live
# Autorun: two autoruns, the first asks, then a link to Live Framed (across
# the line the other way), a plain page with a frame from this site, which
# must load; Live Box: code that reads input beside a frame - never isolated,
# so the box and the build's note line.
(course / "Live Plain Link.md").write_text(
    "---\ntitle: Live Plain Link\n---\nA plain page (plantoir-live-plain-7f3a) that links to [[Runner Playground]].\n", encoding="utf-8")
(course / "Live Framed.md").write_text(
    "---\ntitle: Live Framed\n---\nA plain page with a frame from this site (plantoir-live-framed-7f3a).\n\n"
    "<iframe class=\"plantoir-live-frame\" src=\"Help-Sessions\" title=\"Help Sessions\"></iframe>\n", encoding="utf-8")
(course / "Live Autorun.md").write_text(
    "---\ntitle: Live Autorun\ncodeRunner: true\n---\nTwo blocks that run by themselves, and the first asks (plantoir-live-autorun-7f3a). Then [[Live Framed]].\n\n"
    "```python run autorun\nname = input(\"Name? \")\nprint(\"Hi\", name)\n```\n\n"
    # Far enough down that the second autorun comes into view only when the
    # check scrolls to it - after the first is already waiting.
    + "".join(f"Filler paragraph {n} keeps the second block out of view.\n\n" for n in range(1, 61))
    + "```python run autorun\nprint(\"second\")\n```\n", encoding="utf-8")
(course / "Live Box.md").write_text(
    "---\ntitle: Live Box\ncodeRunner: true\n---\nCode that reads input beside a frame (plantoir-live-box-7f3a).\n\n"
    "<iframe src=\"Help-Sessions\" title=\"Help Sessions\"></iframe>\n\n```python run\nprint(input(\"Name? \"))\n```\n", encoding="utf-8")
RUNNERPLANTS

# ---- #505: an overall expectation's backlinks, planted for the same build ----
# Two pages in a shared folder (so the course's settings are not touched),
# connected the way a class page embeds expectations, each with a sentinel in
# its title. "Overall Backlinks Specific" embeds ONLY the specific expectation
# A2.1: the overall page A2 must list it, which is the aggregation itself (a
# direct-links-only panel lists it on A2.1 alone - measured: this check passed
# against the old component until this page was added). "Overall Backlinks
# Fixture" embeds BOTH A2.1 and A2: A2 must list it ONCE (one filter over A2
# and its specific expectations, not two lists). Removed by restore_hit_fixture.
printf -- '---\ntitle: Overall Fixture plantoir-overall-both-7f3a\n---\nA page planted by verify.sh that connects to an overall expectation and one of its specific expectations.\n\n![[A2.1]]\n\n![[A2. Applications, Careers, and Connections]]\n' \
  > "$HIT_COURSE/Discussions/Overall Backlinks Fixture.md"
printf -- '---\ntitle: Overall Specific plantoir-overall-specific-7f3a\n---\nA page planted by verify.sh that connects to one specific expectation only.\n\n![[A2.1]]\n' \
  > "$HIT_COURSE/Discussions/Overall Backlinks Specific.md"
# ---- #569: a % in an expectation's name, planted for the same build ----
# An overall expectation whose file name holds "%", and one specific
# expectation under it so the coverage map draws its chip. Before #569 the
# chip's href kept the raw "%" and Quartz stopped the whole build with "URI
# malformed" on the coverage map (measured on the #569 plan). Strand Z, so no
# real expectation's cell or chip moves. Removed by restore_hit_fixture.
printf -- '---\ntitle: Z1. Planted 100%% Overall\n---\nAn overall expectation planted by verify.sh (#569).\n' \
  > "$HIT_COURSE/Curriculum/Z1. Planted 100% Overall.md"
printf -- '---\ntitle: Z1.1\n---\nA specific expectation planted by verify.sh under Z1 (#569).\n' \
  > "$HIT_COURSE/Curriculum/Z1.1.md"
# ---- #563: self-check quizzes, planted for the same build ----
# Quiz Fixture: every contracts/shared-rules.json -> quizCallouts.recognise
# case in order, each after a "Case n" line (6k reads each quiz's kind or
# problem back, and the build's plantoir: error: lines); Quiz CRLF: the CR LF
# case on a page saved with CR LF (review S1); Quiz Lookalikes: [!question],
# a top-level [!answer] and [!explain], and quiz syntax shown in a fence -
# none of them a quiz; Quiz Printable: a printable page with a folded answer
# of its own and two quizzes (ruling Q8: neither quiz's answer nor its
# explanation in the handout); Quiz Hidden: a broken quiz students cannot
# see (reported nowhere); Quiz Source and Quiz Host: a quiz transcluded onto
# a page with its own (review S5); Quiz Playground: every kind for the
# browser check, with graphs, code to run and an image in choices and
# explanations. Removed by restore_hit_fixture.
python3 - "$HIT_COURSE" <<'QUIZPLANTS'
import json, struct, sys, zlib
from pathlib import Path
course = Path(sys.argv[1])
rules = json.load(open("contracts/shared-rules.json", encoding="utf-8"))["quizCallouts"]
F = "```"
body = "Self-check quizzes planted by verify.sh (plantoir-quiz-sentinel-7f3a).\n\n"
for number, case in enumerate(rules["recognise"]["cases"], start=1):
    if "\r" in case["markdown"]:
        continue
    body += f"Case {number}: {case['name']}.\n\n{case['markdown']}\n"
(course / "Quiz Fixture.md").write_text("---\ntitle: Quiz Fixture\n---\n" + body, encoding="utf-8")
crlf = [case for case in rules["recognise"]["cases"] if "\r" in case["markdown"]][0]
(course / "Quiz CRLF.md").write_bytes(("---\r\ntitle: Quiz CRLF\r\n---\r\nSaved with CR LF (plantoir-quiz-crlf-7f3a).\r\n\r\n"
                                       + crlf["markdown"]).encode("utf-8"))
(course / "Quiz Lookalikes.md").write_text(
    "---\ntitle: Quiz Lookalikes\n---\nCallouts that are not quizzes (quiz-lookalike-sentinel-7f3a).\n\n"
    "> [!question] Which is prime?\n> - [x] 5\n> - [ ] 6\n\n"
    "> [!answer]- Answer\n> lookalike-answer-7f3a\n\n"
    "> [!explain]- Why\n> lookalike-explain-7f3a\n\n"
    + F + "markdown\n> [!quiz] Shown, never run.\n> - [x] a\n> > [!answer]- Answer\n> > a\n" + F + "\n", encoding="utf-8")
(course / "Quiz Printable.md").write_text(
    "---\ntitle: Quiz Printable\nprintable: true\n---\nA printable page with quizzes (plantoir-quiz-printable-7f3a).\n\n"
    "## Question 1\n\nSimplify $(x + 3)(x - 2)$.\n\n> [!success]- Answer 1\n> $x^2 + x - 6$\n\n"
    "> [!quiz] Which is a factor of $x^2 - 9$?\n> - [x] $x - 3$\n> - [ ] $x + 9$\n>\n"
    "> > [!explain]- Why\n> > printable-explain-7f3a: a difference of squares.\n\n"
    "> [!quiz] Name the capital of Canada.\n> > [!answer]-\n> > printable-answer-7f3a | Ottawa\n", encoding="utf-8")
(course / "Quiz Twice.md").write_text(
    "---\ntitle: Quiz Twice\n---\nOne quiz shown twice (plantoir-quiz-twice-7f3a).\n\n![[Quiz Source]]\n\n![[Quiz Source]]\n",
    encoding="utf-8")
(course / "Quiz Code Shown.md").write_text(
    "---\ntitle: Quiz Code Shown\n---\nQuiz syntax shown as indented code, never a quiz (quiz-code-sentinel-7f3a).\n\n"
    "    > [!quiz] Shown as code.\n    > > [!answer]- Answer\n    > > a\n\n"
    "> [!note] How to write one\n>\n>     > [!quiz] Shown as code in a callout.\n>     > > [!answer]- Answer\n>     > > a\n\n"
    "- Step one: type this\n\n      > [!quiz] Shown as code under a list item.\n      > > [!answer]- Answer\n      > > a\n",
    encoding="utf-8")
(course / "Quiz Summary.md").write_text(
    "---\ntitle: Quiz Summary\n---\n> [!quiz] Fill `____` and `____`.\n> > [!answer]-\n> > summary-answer-7f3a\n> > b\n",
    encoding="utf-8")
# #588: a fill-in-the-blank question with ONE blank, on a page of its own so
# Quiz Playground's quizzes and score are not moved.
(course / "Quiz One Blank.md").write_text(
    "---\ntitle: Quiz One Blank\n---\nOne blank (plantoir-quiz-one-blank-7f3a).\n\n"
    "> [!quiz] The capital of France is `____`.\n> > [!answer]-\n> > Paris\n", encoding="utf-8")
(course / "Quiz Hidden.md").write_text(
    "---\ntitle: Quiz Hidden\npublish: false\n---\nHidden (plantoir-quiz-hidden-7f3a).\n\n> [!quiz] Broken.\n> - [ ] a\n> - [ ] b\n",
    encoding="utf-8")
(course / "Quiz Source.md").write_text(
    "---\ntitle: Quiz Source\n---\nA quiz to transclude (plantoir-quiz-source-7f3a).\n\n"
    "> [!quiz] Source question: pick the odd number.\n> - [x] 7\n> - [ ] 8\n", encoding="utf-8")
(course / "Quiz Host.md").write_text(
    "---\ntitle: Quiz Host\n---\nA page with its own quiz and another page's (plantoir-quiz-host-7f3a).\n\n"
    "> [!quiz] Host question: pick the even number.\n> - [ ] 7\n> - [x] 8\n\n![[Quiz Source]]\n", encoding="utf-8")
# A tiny image for a choice.
def png(width, height):
    raw = b"".join(b"\x00" + b"\x30\x80\xc0" * width for _ in range(height))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + \
        chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
(course / "Media").mkdir(exist_ok=True)
(course / "Media" / "plantoir-quiz-choice.png").write_bytes(png(40, 20))
(course / "Quiz Playground.md").write_text(
    "---\ntitle: Quiz Playground\ncodeRunner: true\n---\n"
    "> [!quiz] Simplify $2^3 \\cdot 2^4$.\n> > [!answer]- Answer\n> > $2^7$ | 2^7\n>\n> > [!explain]- Why\n> > playground-explain-7f3a: same base, add the exponents.\n\n"
    "Every kind of self-check question (plantoir-quiz-playground-7f3a).\n\n"
    "> [!quiz] Which graph shows $y = (x-3)^2 + 2$?\n> - [ ] Vertex at $(-3, 2)$\n> - [x] Vertex at $(3, 2)$\n> - [ ] Vertex at $(3, -2)$\n>\n"
    "> > [!explain]- Why\n> > $y = x^2$ shifts right 3 and up 2:\n> > " + F + "functionplot\n> > y = (x-3)^2 + 2\n> > y = x^2\n> > " + F + "\n\n"
    "> [!quiz] Which are prime?\n> - [x] 2\n> - [ ] 4\n> - [x] 5\n> - [ ] 9\n\n"
    "> [!quiz] Water boils at `____` °C at `____` pressure.\n> > [!answer]-\n> > 100 ± 1 | one hundred\n> > sea level | standard | atmospheric\n\n"
    "> [!quiz|shuffle] Which is a factor of $x^2 - 5x + 6$?\n> - [x] $x - 2$\n> - [ ] $x + 2$\n> - [ ] $x + 3$\n> - [ ] $x + 6$\n> - [ ] $x - 6$\n\n"
    "> [!quiz]- Which is the graph of $y = -x^2$?\n> - [ ] Graph A\n>   " + F + "functionplot\n>   ---\n>   alt: an upward parabola\n>   ---\n>   y = x^2\n>   " + F + "\n"
    "> - [x] Graph B\n>   " + F + "functionplot\n>   y = -x^2\n>   " + F + "\n\n"
    "> [!quiz] What does this print?\n> - [x] 5\n>   " + F + "python run\n>   print(2 + 3)\n>   " + F + "\n> - [ ] 6\n> - [ ] A picture\n>   ![a blue box](Media/plantoir-quiz-choice.png)\n>\n"
    "> > [!explain]- Why\n> > Run it yourself:\n> > " + F + "python run\n> > print(2 + 3)\n> > " + F + "\n\n"
    "> [!quiz] Solve $x^2 = 9$.\n> > [!answer]-\n> > ±3 | x = ±3\n\n"
    # Swift to run (#493) in a choice and in an explanation (#563 review S2).
    "> [!quiz] What does this Swift program print?\n> - [x] 6\n>   " + F + "swift run\n>   print(2 * 3)\n>   " + F + "\n"
    "> - [ ] 23\n>\n> > [!explain]- Why\n> > `*` multiplies. Run it:\n> > " + F + "swift run\n> > let n = 2\n> > print(n * 3)\n> > " + F + "\n",
    encoding="utf-8")
QUIZPLANTS
# ---- #519: task boxes students tick, planted for the same build ----
# Task Fixture: every contracts/shared-rules.json -> taskBoxes.itemText case
# in order, each after a "Case n" line (6l reads each box's id back), then a
# Checklist section of its own; Task CRLF: the CR LF case on a page saved with
# CR LF; Task Host: the Checklist transcluded twice, and an item of its own
# (a transcluded box keeps its source page's name, and two copies stay in
# step); Task Twin A and B: two pages alike in every element but their items'
# words, so Quartz's router reuses one's boxes for the other (review F3 - the
# browser check proves the reuse happened before it trusts what it reads);
# Task Printable: a printable page with a task list (what paper shows); Task
# Raw Box: a checkbox the page writes in HTML, which is no task item and is
# left alone (6l must not count it - review F5).
# Removed by restore_hit_fixture.
python3 - "$HIT_COURSE" <<'TASKPLANTS'
import json, sys
from pathlib import Path
course = Path(sys.argv[1])
rules = json.load(open("contracts/shared-rules.json", encoding="utf-8"))["taskBoxes"]
body = "Task boxes planted by verify.sh (plantoir-task-sentinel-7f3a).\n\n## Cases\n\n"
for number, case in enumerate(rules["itemText"]["cases"], start=1):
    if case.get("crlf"):
        continue
    body += f"Case {number}: {case['name']}.\n\n{case['markdown']}\n\n"
body += ("## Checklist\n\n- [ ] Sharpen your pencil\n- [x] Find your notebook\n"
         "- [ ] Read [[Task Host]] before class\n")
(course / "Task Fixture.md").write_text("---\ntitle: Task Fixture\n---\n" + body, encoding="utf-8")
crlf = [case for case in rules["itemText"]["cases"] if case.get("crlf")][0]
(course / "Task CRLF.md").write_bytes(("---\r\ntitle: Task CRLF\r\n---\r\nSaved with CR LF (plantoir-task-crlf-7f3a).\r\n\r\n"
                                       + crlf["markdown"]).encode("utf-8"))
(course / "Task Host.md").write_text(
    "---\ntitle: Task Host\n---\nAnother page's checklist, twice (plantoir-task-host-7f3a).\n\n"
    "- [ ] An item of the host's own\n\n![[Task Fixture#Checklist]]\n\n![[Task Fixture#Checklist]]\n", encoding="utf-8")
for twin in ("A", "B"):
    (course / f"Task Twin {twin}.md").write_text(
        f"---\ntitle: Task Twin {twin}\n---\nA twin page planted by verify.sh.\n\n"
        f"- [ ] Twin {twin} first item\n- [ ] Twin {twin} second item\n", encoding="utf-8")
(course / "Task Raw Box.md").write_text(
    "---\ntitle: Task Raw Box\n---\nA checkbox the page writes itself, not a task item (plantoir-task-raw-7f3a):\n\n"
    "<label><input type=\"checkbox\"> a box of the page's own</label>\n", encoding="utf-8")
(course / "Task Printable.md").write_text(
    "---\ntitle: Task Printable\nprintable: true\n---\nA printable checklist (plantoir-task-printable-7f3a).\n\n"
    "## Before the lab\n\n- [ ] Printable first item\n- [x] Printable second item\n- [ ] Printable third item\n",
    encoding="utf-8")
TASKPLANTS
# ---- #596: every example in the page-authoring skill, planted for the same build ----
# The skill's examples are read from the skill ITSELF, so an example edited
# there is the example built here: every ```markdown / ````markdown fence and
# every top-level ```mermaid one becomes a page, "Authoring Example NN" (an
# example that starts with its own settings block keeps it, its title prefixed
# so a class page's or Key Links' title cannot pass for the real thing), plus
# "Authoring Claims" for what the skill's prose claims about maths, money,
# links and callout kinds. Pages the examples link to and the Media files they
# show are planted only when the course has none of that name. Every path is
# listed in /tmp/verify_authoring_planted.txt, which restore_hit_fixture reads.
# 6n reads each back.
python3 - "$HIT_COURSE" support/agent_guidance/skills/plantoir-page-authoring/SKILL.md /tmp/verify_authoring_planted.txt <<'AUTHORPLANTS'
import re, struct, sys, zlib
from pathlib import Path
course, skill_path, record = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
lines = skill_path.read_text(encoding="utf-8").split("\n")
examples, index = [], 0
while index < len(lines):
    opening = re.match(r"^(`{3,})(markdown|mermaid)\s*$", lines[index])
    if not opening:
        index += 1
        continue
    fence, kind, body = opening.group(1), opening.group(2), []
    index += 1
    while index < len(lines) and lines[index] != fence:
        body.append(lines[index])
        index += 1
    index += 1
    text = "\n".join(body)
    examples.append("```mermaid\n" + text + "\n```" if kind == "mermaid" else text)
planted = []
def plant(relative, data):
    path = course / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, bytes):
        path.write_bytes(data)
    else:
        path.write_text(data, encoding="utf-8")
    planted.append(relative)
for number, text in enumerate(examples, start=1):
    name = f"Authoring Example {number:02d}"
    if text.startswith("---\n"):
        page = re.sub(r"^title: (.*)$", lambda m: f"title: {name} - {m.group(1)}", text, count=1, flags=re.M)
        if page == text:
            page = text.replace("---\n", f"---\ntitle: {name}\n", 1)
    else:
        page = f"---\ntitle: {name}\n---\n{text}"
    plant(f"{name}.md", page + "\n")
plant("Authoring Claims.md",
      "---\ntitle: Authoring Claims\n---\n"
      "> [!definition] Slope\n> plantoir-authoring-unknown-kind-7f3a\n\n"
      "Money: it costs $5 and $10 today (plantoir-authoring-money-7f3a).\n\n"
      "Escaped: it costs \\$5 and \\$10 today (plantoir-authoring-escaped-7f3a).\n\n"
      "Spaced: $ x + 1 $ (plantoir-authoring-spaced-7f3a).\n\n"
      "Markdown link: [practice](Slope Practice.md) (plantoir-authoring-mdlink-7f3a).\n")
existing = {path.stem.lower() for path in course.rglob("*.md")}
stubs = {"Slope": "The slope stub (plantoir-authoring-slope-7f3a).\n\n## Finding the slope from two points\n\nRise over run.\n"}
for name in ("Rate of Change", "Slope Warm-Up", "Slope Practice", "How This Class Works", "How Marks Work", "Getting Help"):
    stubs[name] = "A page the page-authoring skill's examples link to.\n"
for name, body in stubs.items():
    if name.lower() not in existing:
        plant(f"{name}.md", f"---\ntitle: {name}\n---\n{body}")
def png(width, height):
    raw = b"".join(b"\x00" + b"\x20\x60\xc0" * width for _ in range(height))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + \
        chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
if not (course / "Media" / "cell-diagram.png").exists():
    plant("Media/cell-diagram.png", png(40, 20))
if not (course / "Media" / "Unit 2 Review.pdf").exists():
    plant("Media/Unit 2 Review.pdf",
          b"%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj "
          b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n")
record.write_text("\n".join(planted) + "\n", encoding="utf-8")
print(f"   planted {len(examples)} examples from the page-authoring skill")
AUTHORPLANTS

# ---- #545: My Progress, planted for the same build ----
# Progress Fixture: four items under its success criteria (one the teacher
# wrote ticked, `[x]`, which counts as done until a student unticks it - Q5;
# one under a deeper `### Tests of success:`), one before any heading and one after the
# section - which do not count - linked from Unit 1, Day 2, whose file is
# put back by restore_hit_fixture. Other pages of the section may have
# success criteria too (a real course does), so 6m and the browser check
# assert on this page's own row and work every total out from the manifest.
PROGRESS_CLASS_BACKUP="$(mktemp -t plantoir-progress-class)"
cp "$HIT_COURSE/section1/All Classes/Unit 1, Day 2.md" "$PROGRESS_CLASS_BACKUP"
cat > "$HIT_COURSE/Progress Fixture.md" <<'PROGRESSFIXTURE'
---
title: Progress Fixture
---
A page planted for the My Progress check (plantoir-progress-sentinel-545).

- [ ] Not counted: before any heading

## Success criteria

- [ ] I can name a variable
- [ ] I can print a value
- [x] I can comment my code

### Tests of success:

- [ ] I can read an error message

## Practice

- [ ] Not counted: after the section
PROGRESSFIXTURE
printf '\n- [[Progress Fixture]]\n' >> "$HIT_COURSE/section1/All Classes/Unit 1, Day 2.md"

STAMP_FILE="$(mktemp -t cq4t-stamp)"
echo ""
echo "🚦 Running: ./preview.sh EXC2O 1 --image $DEV_TEST_IMAGE --full-rebuild --build-only"
echo "   (full rebuild ensures the Quartz scaffold comes from the dev-test image)"
echo ""
# Kept as a transcript too (`script` keeps the terminal the launcher needs and
# passes its exit status through), so 6h can read what the build SAID - the
# printPdfNotFound finding for the planted page whose PDF is missing (#454).
if script -q /tmp/verify_main_build.log ./preview.sh EXC2O 1 --image "$DEV_TEST_IMAGE" --full-rebuild --build-only; then
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
EXPECTED_BUILD_ROOT="${HOME%/}/Library/Application Support/Plantoir/builds/$(/bin/pwd -P | shasum -a 256 | cut -c1-8)"
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

# -------------------- 6h. The How I Teach page never reaches the site (#209) ----
# The pages planted before the build above, looked for by their WORDS across
# everything the site serves. Two halves that fail independently: the two
# reserved pages must be nowhere, and the look-alike MUST be there — a site
# that built nothing would pass the first half alone.
HIT_OK="true"
if [[ -d "$SITE_PUBLIC" ]]; then
  for sentinel in plantoir-hit-sentinel-course-7f3a plantoir-hit-sentinel-section-7f3a; do
    if grep -rIliq -- "$sentinel" "$SITE_PUBLIC"; then
      fail "A How I Teach page reached the built site: '$sentinel' is in $(grep -rIli -- "$sentinel" "$SITE_PUBLIC" | head -3 | tr '\n' ' ')"
      HIT_OK="false"
    fi
  done
  if ! grep -rIliq -- plantoir-hit-sentinel-lookalike-7f3a "$SITE_PUBLIC"; then
    fail "The look-alike page 'How I Teach 1' is missing from the built site — it is an ordinary page and must be published (without it the check above proves nothing)"
    HIT_OK="false"
  fi
else
  fail "No built site at $SITE_PUBLIC to check for How I Teach pages"
  HIT_OK="false"
fi
if python3 - "$HIT_COURSE/course_config.json" <<'PY'
import json, sys
config = json.load(open(sys.argv[1], encoding="utf-8"))
listed = [n for n in config.get("shared_files", []) + config.get("per_section_files", [])
          if n.lower() in ("how i teach.md",)]
sys.exit(1 if listed else 0)
PY
then :; else
  fail "The course's settings still list a How I Teach page after a build — preflight did not drop it"
  HIT_OK="false"
fi
for planted in "$HIT_COURSE/How I Teach.md" "$HIT_COURSE/section1/HOW I TEACH.md"; do
  if [[ ! -f "$planted" ]]; then
    fail "The build removed the teacher's own $planted — only the site's copy may ever be removed"
    HIT_OK="false"
  fi
done
[[ "$HIT_OK" == "true" ]] && pass "No How I Teach page reaches the built site, the look-alike does, and the teacher's own pages are untouched (#209)"

# ---- 6h, continued: an overall expectation's backlinks (#505) ----
# The two pages planted above, read from the built pages. The "When did we do
# this?" panel on the overall page A2 must name each exactly once - the page
# that links only A2.1 (aggregated) and the page that links A2 and A2.1
# (de-duplicated) - and the panel on A2.1 must name each once (unchanged).
# Counted inside the panel only, so a title shown anywhere else on the page
# cannot make it pass. Before #505 the A2 page had no panel at all.
if python3 - "$SITE_PUBLIC" <<'OVERALLCHECK'
import glob, sys
public = sys.argv[1]
sentinels = {"plantoir-overall-both-7f3a": "the page linking A2 and A2.1",
             "plantoir-overall-specific-7f3a": "the page linking only A2.1"}
heading = "When did we do this?"
problems = []
overall = glob.glob(public + "/Curriculum/A2.-*.html")
pages = {"the overall expectation A2": overall[0] if len(overall) == 1 else None,
         "the specific expectation A2.1": public + "/Curriculum/A2.1.html"}
for what, path in pages.items():
    if path is None:
        problems.append(f"{what}: expected one built page Curriculum/A2.-*.html, found {len(overall)}")
        continue
    try:
        html = open(path, encoding="utf-8").read()
    except OSError:
        problems.append(f"{what}: no built page at {path}")
        continue
    start = html.find('class="backlinks')
    if start < 0:
        problems.append(f'{what}: no "{heading}" panel on {path}')
        continue
    end = html.find("</ul>", start)
    panel = html[start:end if end > start else len(html)]
    if heading not in panel:
        problems.append(f'{what}: the panel on {path} has no "{heading}" heading')
    for sentinel, planted in sentinels.items():
        count = panel.count(sentinel)
        if count != 1:
            problems.append(f"{what}: {planted} is listed {count} time(s) in the panel on {path}, not once")
for problem in problems:
    print("   " + problem)
sys.exit(1 if problems else 0)
OVERALLCHECK
then
  pass "An overall expectation's page lists the pages of its specific expectations, a page linking both is listed once, and the specific expectation's page is unchanged (#505)"
else
  fail "An overall expectation's \"When did we do this?\" panel is wrong (#505) - see the lines above"
fi

# ---- 6h, continued: a % in an expectation's name (#569) ----
# The build above passed with the planted "Z1. Planted 100% Overall" page in
# the curriculum folder; before #569 it stopped there. The coverage map's chip
# must link Quartz's own slug, and that page must be in the site.
if [[ -f "$SITE_PUBLIC/Curriculum-Coverage.html" ]] \
   && grep -Fq 'Curriculum/Z1.-Planted-100-percent-Overall"' "$SITE_PUBLIC/Curriculum-Coverage.html" \
   && [[ -f "$SITE_PUBLIC/Curriculum/Z1.-Planted-100-percent-Overall.html" ]]; then
  pass "A % in an expectation's file name builds, and the coverage map links the page Quartz serves (#569)"
else
  fail "The coverage map's link to a page named with % is wrong, or the page is missing (#569): $SITE_PUBLIC/Curriculum-Coverage.html, $SITE_PUBLIC/Curriculum/Z1.-Planted-100-percent-Overall.html"
fi

# ---- 6h, continued: a folder page's table of contents (#520) ----
# EXC2O's own Curriculum/index.md says enableToc: true and has headings of its
# own; Quartz renders a folder's index with the folder-page layout, whose
# right column was empty, so it showed no table of contents. Counted inside
# the table of contents only: two entries or more.
if python3 - "$SITE_PUBLIC/Curriculum/index.html" <<'TOCCHECK'
import re, sys
try:
    html = open(sys.argv[1], encoding="utf-8").read()
except OSError as error:
    print(f"   no built page: {error}")
    sys.exit(1)
start = html.find('class="toc')
if start < 0:
    print(f"   no table of contents on {sys.argv[1]}")
    sys.exit(1)
end = html.find("</ul>", start)
# One <li class="depth-N"> per heading; Quartz adds an empty "overflow-end" item.
entries = len(re.findall(r'<li class="depth-', html[start:end if end > start else len(html)]))
print(f"   table of contents entries: {entries}")
sys.exit(0 if entries >= 2 else 1)
TOCCHECK
then
  pass "A curriculum folder's index page shows its table of contents (#520)"
else
  fail "A curriculum folder's index page shows no table of contents, or one with fewer than two entries (#520) - see the line above"
fi

# ---- 6h, continued: printable pages (#454) ----
# The pages planted with the How I Teach ones, read from the site the launcher
# just built. Checked here, before the plants are taken away below.
#
# THE COMPATIBILITY CHECK is the second one: the planted "Printable Not
# Opted" page is the worksheet with only `printable: true` taken out, and it
# must carry none of the print markup - its date line exactly the plain one
# every page had before #454, no meta-line wrapper, no print style, no button.
# Its PRINT is not unchanged since #501: the shared index.css carries one
# print block for every page that is not printable, checked here by its text
# and on paper by browser-checks/print_plain_page.mjs below.
if python3 - "$SITE_PUBLIC" "$HIT_COURSE" /tmp/verify_main_build.log <<'PY'
import hashlib, html, json, re, sys
from pathlib import Path
public, course, log = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
sys.path.insert(0, "scripts")
import contracts, print_settings, toolchain_paths
toolchain_paths.CONTRACTS_DIR = Path("contracts")
contracts.reset_cache()
problems = []
def page(name):
    path = public / name
    if not path.is_file():
        problems.append(f"{name} was not built")
        return ""
    return path.read_text(encoding="utf-8")

worksheet = page("Printable-Fixture.html")
match = re.search(r'<div class="plantoir-meta-line" data-plantoir-printable="true" data-settings="([^"]*)"', worksheet)
if not match:
    problems.append("the printable page has no Print button line")
else:
    settings = json.loads(html.unescape(match.group(1)))
    config = json.load(open(course / "course_config.json", encoding="utf-8"))
    expected = print_settings.compose(config, "EXC2O")
    if settings["corners"] != expected:
        problems.append(f"the printable page's corners {settings['corners']} are not {expected}")
for needle in ('class="plantoir-print-button"', 'data-mode="questionsOnly"', 'data-mode="answersOnly"',
               'data-mode="withAnswersAtTheEnd"', 'value="landscape"', 'Plantoir LM Roman',
               'id="plantoir-print-page"', "@top-left"):
    if needle not in worksheet:
        problems.append(f"the printable page lacks {needle}")

# #498: the Curriculum connection stays on the page on SCREEN - it is left off
# paper by the page's print code when the page loads, and the build adds no
# mark of its own (print_handout.mjs below checks the printing itself).
if worksheet and ('id="curriculum-connection"' not in worksheet or "plantoir-curriculum-sentinel-7f3a" not in worksheet):
    problems.append("the worksheet's Curriculum connection is not on the page on screen (#498)")
if "data-plantoir-curriculum" in worksheet:
    problems.append("the build marked the Curriculum connection itself; the page's print code does that, on printable pages only (#498)")

plain = page("Printable-Not-Opted.html")
for needle in ("plantoir-meta-line", "plantoir-print", "data-plantoir", "@page"):
    if needle in plain:
        problems.append(f"the page that did not opt in carries {needle!r}: pages that do not ask to print must be unchanged")
if plain and not re.search(r'</h1><p show-comma="[a-z]+" class="content-meta">', plain):
    problems.append("the page that did not opt in does not have the plain date line straight after its title")

# #501: its print changes only through the shared stylesheet - the one block
# (printablePages.everyOtherPage) that takes the sidebars away under ⌘P on
# every page that is not printable, as the site's minifier writes it.
every_other = contracts.section("shared-rules", "printablePages", "everyOtherPage")
minified = every_other["scope"] + " " + every_other["hidden"][0].replace(" > ", ">") + "{display:none!important"
stylesheet = public / "index.css"
if not stylesheet.is_file() or minified not in stylesheet.read_text(encoding="utf-8"):
    problems.append(f"index.css lacks the print block for pages that are not printable ({minified}, #501)")

pin = [p for p in json.load(open("contracts/toolchain.json"))["pins"] if p["pin"] == "pagedjs"][0]
engine = public / "static" / "pagedjs" / "paged.min.js"
if not engine.is_file() or hashlib.sha256(engine.read_bytes()).hexdigest() != pin["fileSha256"]:
    problems.append("the site does not carry the pinned print engine at static/pagedjs/paged.min.js")
for path in public.rglob("*"):
    if "pagedjs" in path.parts:
        continue  # the engine's own text names its home page; it is never fetched from there
    if path.suffix in (".html", ".js", ".css") and re.search(r"https?://[^\"' ]*pagedjs", path.read_text(encoding="utf-8", errors="ignore")):
        problems.append(f"{path.name} loads the print engine from the network")

handout = page("Printable-PDF-Fixture.html")
link = re.search(r'<a class="plantoir-print plantoir-print-pdf" href="([^"]+)" target="_blank"', handout)
if not link:
    problems.append("the page with its own PDF has no link to it")
else:
    served = (public / link.group(1)).resolve()
    source = course / "Media" / "plantoir-print-fixture & key.pdf"
    if not served.is_file() or served.read_bytes() != source.read_bytes():
        problems.append(f"the PDF link {link.group(1)} does not lead to the teacher's PDF")
if "plantoir-print-menu" in handout:
    problems.append("the page with its own PDF still offers the generated handout's menu")

missing = page("Printable-Bad-PDF.html")
if 'class="plantoir-print-button"' not in missing:
    problems.append("the page whose PDF is missing did not fall back to the generated handout")
said = log.read_text(encoding="utf-8", errors="ignore") if log.is_file() else ""
if not re.search(r'PLANTOIR_HEALTH: \{"name": "printPdfNotFound"[^\n]*Printable Bad PDF', said):
    problems.append("the build did not report the missing PDF as a folder problem naming the page")

for planted in (course / ".claude", course / ".agents"):
    if planted.exists():
        problems.append(f"the build wrote {planted} into the course; guidance belongs at the working folder's root")

for problem in problems:
    print("   " + problem)
sys.exit(1 if problems else 0)
PY
then
  pass "printable pages: the worksheet carries its corners and menu, a page that did not opt in carries no print markup at all (its print changes only through the shared stylesheet, #501), the engine is the pinned one served locally, a page's own PDF is linked byte for byte, and a missing PDF falls back and is reported (#454)"
else
  fail "printable pages: one of the checks above failed (#454)"
fi


# ---- 6i. Diagrams and graphs (#485 E1), as the build left them ----
# The planted Figures Fixture: every drawing is an SVG with a viewBox in the
# page; the one TeX cannot draw is the sentence a student reads, and a folder
# problem naming the page and the line of the teacher's file; the site
# carries exactly the faces its drawings name and the pinned function-plot,
# served by itself; the page's description is the words, not the lettering of
# its drawings; a hidden page's graph is nowhere.
cp "$SITE_PUBLIC/Help-Sessions.html" /tmp/verify_untouched_page.html 2>/dev/null || true
if python3 - "$SITE_PUBLIC" /tmp/verify_main_build.log "$HIT_COURSE/Figures Fixture.md" <<'FIGPY'
import hashlib, html, json, re, sys
from pathlib import Path
public, log, planted = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
problems = []
page_path = public / "Figures-Fixture.html"
page = page_path.read_text(encoding="utf-8") if page_path.is_file() else ""
if not page:
    problems.append("Figures-Fixture.html was not built")
figures = re.findall(r'<figure class="pl-figure pl-(tikz|functionplot)( pl-figure-failed)?"[^>]*>(.*?)</figure>', page, re.S)
fences = sum(1 for line in planted.read_text(encoding="utf-8").splitlines() if re.match(r"^[ >]*(?:(?:[-*+]|[0-9]+[.)])[ \t]+)?```(tikz|functionplot)\s*$", line))
if len(figures) != fences:
    problems.append(f"{len(figures)} figures on the page for {fences} fences")
drawn = [body for engine, failed, body in figures if engine == "tikz" and not failed]
if len(drawn) != 7 or any(not re.search(r'<svg[^>]*viewBox="', body) for body in drawn):
    problems.append(f"{len(drawn)} TikZ drawings on the page, not 7 each with a viewBox")
failed = [body for engine, failed, body in figures if failed]
if len(failed) != 2 or "This diagram couldn" not in failed[0] or "This graph couldn" not in failed[1]:
    problems.append("the two figures that cannot be drawn do not say so in the contract's words")
if not re.search(r'style="fill:\s*red;?"', page):
    problems.append("the red label kept no colour of its own (Quartz greys every svg text)")
if not any(engine == "functionplot" and not failed and "a bullet" in body and "pl-plot" in body for engine, failed, body in figures):
    problems.append("the graph opened on a bullet's own line was not placed to be drawn (E1 review S1)")
if page.count("static/tikz/fonts.css") != 1:
    problems.append(f"the faces are linked {page.count('static/tikz/fonts.css')} times, not once")
ids = re.findall(r'\bid="(pgf[^"]+)"', page)
if len(ids) != len(set(ids)):
    problems.append("two drawings on the page share an element id (review N5)")
description = re.search(r'<meta name="description" content="([^"]*)"', page)
if not description or html.unescape(description.group(1)) != "Diagrams and graphs planted by verify.sh (plantoir-figures-sentinel-7f3a).":
    problems.append(f"the page's description is not its words: {description and description.group(1)!r}")
said = log.read_text(encoding="utf-8", errors="ignore") if log.is_file() else ""
foo_line = 1 + [index for index, line in enumerate(planted.read_text(encoding="utf-8").splitlines()) if line.strip() == "\\foo"][0]
if f"plantoir: error: Figures Fixture.md: tikz block 6, line {foo_line}:" not in said:
    problems.append(f"no plantoir: error line names Figures Fixture.md, tikz block 6, line {foo_line}")
if not re.search(r'PLANTOIR_HEALTH: \{"name": "figuresCouldNotBeDrawn"[^\n]*Figures Fixture[^\n]*diagram 6, line ' + str(foo_line), said):
    problems.append("the build did not report the diagram it could not draw as a folder problem naming page and line")
if "plantoir: note: Figures Fixture.md: tikz block 5" not in said:
    problems.append("the drawing with no description was not noted")
if not re.search(r"Drew ([7-9]|[1-9][0-9]+) diagrams \(0 from before\)", said):
    problems.append("the first build (a full rebuild, which empties the cache) did not draw every diagram afresh")
named = set(re.findall(r'font-family="([a-z0-9]+)"', page))
tikz = public / "static" / "tikz"
carried = sorted(path.name for path in tikz.iterdir()) if tikz.is_dir() else []
if carried != sorted([f"{face}.ttf" for face in named] + ["LICENCE", "fonts.css"]):
    problems.append(f"static/tikz holds {carried}, not the faces the drawings name ({sorted(named)})")
pins = {pin["pin"]: pin for pin in json.load(open("contracts/toolchain.json"))["pins"]}
engine = public / "static" / "function-plot" / "function-plot.js"
if not engine.is_file() or hashlib.sha256(engine.read_bytes()).hexdigest() != pins["functionPlot"]["fileSha256"]:
    problems.append("the site does not carry the pinned function-plot at static/function-plot/")
for path in [page_path, engine] + [path for path in tikz.glob("*.css")]:
    text = path.read_text(encoding="utf-8", errors="ignore") if path.is_file() else ""
    for found in re.findall(r"https?://[^\s\"')]+", text):
        if "w3.org" in found or "plausible.io" in found:
            continue
        if path == page_path and not any(found in body for _, _, body in figures):
            continue
        problems.append(f"{path.name} names {found}: figures are served by the site itself")
if (public / "Figures-Hidden.html").exists() or any("plantoir-figures-hidden-7f3a" in p.read_text(encoding="utf-8", errors="ignore") for p in public.glob("*.html")):
    problems.append("the hidden page with a graph reached the site")
for problem in problems:
    print("   " + problem)
sys.exit(1 if problems else 0)
FIGPY
then
  pass "diagrams and graphs: every fence drawn as an SVG in the page or reported by page and line, the faces and function-plot carried by the site itself, descriptions free of lettering, a hidden graph nowhere (#485)"
else
  fail "diagrams and graphs: one of the checks above failed (#485)"
fi

# ---- 6j. Runnable code (#455) and the site's own KaTeX (#494), as the build left them ----
# The planted Runner Fixture's runnable blocks are exactly the contract's (in
# order, with their ids, flags, language and the teacher's code); the nested
# shape stays plain code; the page that does not opt in is untouched and
# comes out like its twin in plain fences; the site carries the pinned
# engine with the worker and nothing a CDN would have served, every word
# the page's code says is in the site's script, and every page links the
# site's own KaTeX.
if python3 - "$SITE_PUBLIC" /tmp/verify_main_build.log <<'RUNNERPY'
import hashlib, html, json, re, sys
from pathlib import Path
public, log = Path(sys.argv[1]), Path(sys.argv[2])
problems = []
rules = json.load(open("contracts/shared-rules.json", encoding="utf-8"))["codeRunnerBlocks"]
pins = {pin["pin"]: pin for pin in json.load(open("contracts/toolchain.json"))["pins"]}
def page(name):
    path = public / name
    return path.read_text(encoding="utf-8") if path.is_file() else ""
fixture = page("Runner-Fixture.html")
if not fixture:
    problems.append("Runner-Fixture.html was not built")
found = re.findall(r'<div class="plantoir-runner" data-runner-id="([^"]*)" data-runner-flags(?:="([^"]*)")? data-runner-language="([^"]*)" data-runner-runtime="([^"]*)" data-runner-engine="([^"]*)" data-original="([^"]*)"', fixture)
expected = []
rows = {row["fence"]: row for row in rules["languages"]}
counters = {}
for number, case in enumerate(rules["fences"]["cases"], start=1):
    if case["optedIn"] and case["runner"]:
        fence = case.get("fence", case["lang"])
        row = rows[fence]
        counters[fence] = counters.get(fence, 0) + 1
        expected.append((f"Runner-Fixture-{row['idPrefix']}-{counters[fence]}", " ".join(case["flags"]), fence, row["runtime"], row["engine"], f'print("case {number}")'))
expected.append((f"Runner-Fixture-py-{counters['python'] + 1}", "", "python", "pyodide", "pyodide", 'print("after the nested shape")'))
got = [(rid, flags or "", language, runtime, engine, html.unescape(original)) for rid, flags, language, runtime, engine, original in found]
if got != expected:
    problems.append(f"the fixture's runnable blocks are {got}, not the contract's {expected}")
if "nested shape" not in fixture or re.search(r'data-original="print\(&quot;nested shape', fixture):
    problems.append("the fence on two list markers' line was made runnable, or is missing")
not_opted, twin = page("Runner-Not-Opted.html"), page("Runner-Plain-Twin.html")
if 'class="plantoir-runner"' in not_opted or "data-runner-id" in not_opted:
    problems.append("the page that does not opt in has a runnable block")
figures = lambda text: re.findall(r"<figure data-rehype-pretty-code-figure.*?</figure>", text, re.S)
if not figures(not_opted) or figures(not_opted) != figures(twin):
    problems.append(f"the page that does not opt in does not come out like its twin in plain fences ({len(figures(not_opted))} and {len(figures(twin))} blocks)")
if (public / "Runner-Hidden.html").exists():
    problems.append("the hidden page with code reached the site")
said = log.read_text(encoding="utf-8", errors="ignore") if log.is_file() else ""
if re.search(r"plantoir: error: [^\n]*Runner", said):
    problems.append("the build named a runner page on a plantoir: error: line: " + re.search(r"plantoir: error: [^\n]*Runner[^\n]*", said).group(0))
# Quiz Playground (#563) runs Python and Swift inside its quizzes, so it is
# one more page for each engine.
if not re.search(r"This site carries what runs Swift for 3 pages\.", said):
    problems.append("the build did not say the site carries Swift for the three pages students can see with Swift (Runner Fixture, Swift Playground, Quiz Playground)")
if not re.search(r"This site carries what runs Python for 7 pages\.", said):
    problems.append("the build did not say the site carries Python for the seven pages students can see (not the hidden one; Quiz Playground is the fifth, #583's Live Autorun and Live Box the sixth and seventh)")
engine = public / "static" / "pyodide"
carried = sorted(path.name for path in engine.iterdir()) if engine.is_dir() else []
if carried != sorted(list(pins["pyodide"]["files"]) + ["README.txt", "plantoir-worker.js"]):
    problems.append(f"static/pyodide holds {carried}")
for name, digest in pins["pyodide"]["files"].items():
    if (engine / name).is_file() and hashlib.sha256((engine / name).read_bytes()).hexdigest() != digest:
        problems.append(f"static/pyodide/{name} does not match its pin")
if (engine / "plantoir-worker.js").read_bytes() != Path("support/gated/pyodide/plantoir-worker.js").read_bytes():
    problems.append("the site's worker is not support/gated/pyodide/plantoir-worker.js")
script = page("postscript.js")
for key, text in rules["words"].items():
    if key in ("note", "blockNotPrepared"):
        continue
    if text not in script and json.dumps(text)[1:-1] not in script:
        problems.append(f"the site's script does not carry words.{key}")
# Nothing from the CDN, anywhere: one string inside pyodide.mjs is allowed
# (a fallback the worker pins out), and nothing else.
for path in sorted(public.rglob("*")):
    if path.suffix not in (".html", ".js", ".mjs", ".css") or not path.is_file():
        continue
    text = path.read_text(encoding="utf-8", errors="ignore")
    hits = text.count("cdn.jsdelivr.net")
    allowed = 1 if path == engine / "pyodide.mjs" else 0
    if hits != allowed:
        problems.append(f"{path.relative_to(public)} names cdn.jsdelivr.net {hits} time(s)")
katex = public / "static" / "katex"
kfiles = sorted(str(path.relative_to(katex)) for path in katex.rglob("*") if path.is_file()) if katex.is_dir() else []
faces = [name for name in kfiles if name.startswith("fonts/")]
if len(faces) != 20 or any(not name.endswith(".woff2") for name in faces) or sorted(set(kfiles) - set(faces)) != ["LICENSE", "contrib/copy-tex.min.js", "katex.min.css"]:
    problems.append(f"static/katex holds {kfiles}")
for name, digest in pins["katex"]["files"].items():
    local = katex / name.replace("dist/", "", 1)
    if not local.is_file() or hashlib.sha256(local.read_bytes()).hexdigest() != digest:
        problems.append(f"static/katex/{name.replace('dist/', '', 1)} does not match the pin's {name}")
for name, depth in (("Help-Sessions.html", 0), ("Discussions/Runner-Printable.html", 1)):
    head = page(name)
    links = re.findall(r'<link rel="stylesheet" href="([^"]*katex\.min\.css)"', head)
    want = ("./" if depth == 0 else "../") + "static/katex/katex.min.css"
    if links != [want]:
        problems.append(f"{name} links KaTeX's stylesheet as {links}, not {want}")
if any("katex-error" in path.read_text(encoding="utf-8", errors="ignore") for path in public.rglob("*.html")):
    problems.append("a formula on the site failed to render (katex-error)")
for problem in problems:
    print("   " + problem)
sys.exit(1 if problems else 0)
RUNNERPY
then
  pass "runnable code: every block the contract says runs (Python and Swift) is wrapped with its id, flags and the teacher's code, the nested shape stays plain, a page that does not opt in is untouched, the hidden page counts for nothing, the site carries the pinned Python with its worker and its script carries every word; maths styled from the site's own KaTeX, and nothing on the site names a CDN but the one string the worker pins out (#455, #494)"
else
  fail "runnable code or the site's own KaTeX: one of the checks above failed (#455, #494)"
fi

# ---- 6j, continued: runnable Swift (#493), as the build left it ----
# The planted Swift Playground's blocks each carry their program's address
# (the key of the code the site read) or, for the one that does not compile,
# data-runner-unready; static/swift-wasm holds exactly the programs pages
# students can see use (not Swift Hidden's, though the plan compiled it);
# static/swift is the overlay alone; the build named the broken block at its
# line in the teacher's file with the compiler's first error, and said it as
# the swiftCouldNotBePrepared folder problem.
if python3 - "$SITE_PUBLIC" /tmp/verify_main_build.log "$HIT_COURSE" <<'SWIFTPY'
import html, json, re, sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, "scripts")
import swift_blocks
public, log, course = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
problems = []
rules = json.load(open("contracts/shared-rules.json", encoding="utf-8"))["codeRunnerBlocks"]
page = (public / "Swift-Playground.html").read_text(encoding="utf-8") if (public / "Swift-Playground.html").is_file() else ""
if not page:
    problems.append("Swift-Playground.html was not built")
# Attribute by attribute: a value may hold ">" (data-original is the code).
wrappers = re.findall(r'<div class="plantoir-runner"((?:\s+[\w-]+(?:="[^"]*")?)*)\s*>', page)
def attribute(text, name):
    found = re.search(name + r'="([^"]*)"', text)
    return html.unescape(found.group(1)) if found else None
source = (course / "Swift Playground.md").read_text(encoding="utf-8")
bodies = [block["body"] for block in swift_blocks.swift_fences(source, True)]
if len(wrappers) != 7 or len(bodies) != 7:
    problems.append(f"Swift Playground has {len(wrappers)} runnable blocks on the site and {len(bodies)} in the page, not 7 (#583 added a prompt on the answer's line)")
for index, (attributes, body) in enumerate(zip(wrappers, bodies), start=1):
    key = swift_blocks.key_of(body)
    if attribute(attributes, "data-runner-language") != "swift" or attribute(attributes, "data-runner-id") != f"Swift-Playground-swift-{index}":
        problems.append(f"Swift block {index} is not wrapped as Swift with its id: {attributes[:160]}")
    if index == 5:
        if attribute(attributes, "data-runner-unready") != "compileError" or attribute(attributes, "data-runner-wasm") is not None:
            problems.append(f"the block that does not compile is not marked compileError: {attributes[:200]}")
    elif attribute(attributes, "data-runner-wasm") != f"static/swift-wasm/{key}.wasm":
        problems.append(f"Swift block {index} does not name its program static/swift-wasm/{key}.wasm: {attribute(attributes, 'data-runner-wasm')}")
wanted = set()
for body in bodies[:4] + bodies[5:]:
    wanted.add(swift_blocks.key_of(body) + ".wasm")
# The self-check quizzes' playground runs Swift in a choice and in an
# explanation (#563), so its programs are on the site too.
quiz_playground = course / "Quiz Playground.md"
if quiz_playground.is_file():
    for block in swift_blocks.swift_fences(quiz_playground.read_text(encoding="utf-8"), True):
        wanted.add(swift_blocks.key_of(block["body"]) + ".wasm")
for number, case in enumerate(rules["fences"]["cases"], start=1):
    if case["optedIn"] and case["runner"] and case.get("fence", case["lang"]) == "swift":
        wanted.add(swift_blocks.key_of(f'print("case {number}")') + ".wasm")
carried = public / "static" / "swift-wasm"
got = set(path.name for path in carried.iterdir()) if carried.is_dir() else set()
if got != wanted:
    problems.append(f"static/swift-wasm holds {sorted(got)}, not exactly {sorted(wanted)}")
if (carried / (swift_blocks.key_of('print("hidden swift")') + ".wasm")).exists():
    problems.append("the hidden page's Swift program reached the site")
for path in sorted(carried.glob("*.wasm")) if carried.is_dir() else []:
    if path.read_bytes()[:4] != b"\0asm":
        problems.append(f"{path.name} is not a WebAssembly program")
engine = public / "static" / "swift"
overlay = Path("support/gated/swift")
if not engine.is_dir() or sorted(p.name for p in engine.iterdir()) != sorted(p.name for p in overlay.iterdir()):
    problems.append(f"static/swift holds {sorted(p.name for p in engine.iterdir()) if engine.is_dir() else 'nothing'}")
else:
    for item in overlay.iterdir():
        if (engine / item.name).read_bytes() != item.read_bytes():
            problems.append(f"static/swift/{item.name} is not support/gated/swift/{item.name}")
said = log.read_text(encoding="utf-8", errors="ignore") if log.is_file() else ""
broken_line = source.splitlines().index("print(nmae)") + 1
reason = rules["swift"]["reasons"]["compileError"].replace("{said}", "cannot find 'nmae' in scope")
line = f"plantoir: error: Swift Playground.md: swift block 5, line {broken_line}: {reason}"
if line not in said:
    problems.append(f"the build did not say: {line}")
if not re.search(r'"name": "swiftCouldNotBePrepared"[^\n]*Swift Playground', said):
    problems.append("the build did not report the broken Swift block as the swiftCouldNotBePrepared folder problem")
if re.search(r"plantoir: error: [^\n]*swift block", said.replace(line, "")):
    problems.append("the build named another Swift block on a plantoir: error: line: " + re.search(r"plantoir: error: [^\n]*swift block[^\n]*", said.replace(line, "")).group(0))
for problem in problems:
    print("   " + problem)
sys.exit(1 if problems else 0)
SWIFTPY
then
  pass "runnable Swift: each block names its program (or compileError), static/swift-wasm holds exactly the programs visible pages use, static/swift is the overlay, and the block that does not compile is named at its line in the teacher's file with the compiler's first error, as a folder problem too (#493)"
else
  fail "runnable Swift: one of the checks above failed (#493)"
fi

# ---- 6j, continued: live input (#583), as the build left it ----
# Which built pages a host would isolate, read from the REAL built HTML (with
# Quartz's own head) by both halves of the rule: the publish's
# (isolation_headers.py) and the preview's (support/quartz/cli/
# plantoirIsolation.mjs, the headers the preview's server would send). The
# Live Box page (code that reads input beside a frame) keeps the box and is
# named on a note line; the router's patch reached the site's script.
if python3 - "$SITE_PUBLIC" <<'LIVEPY'
import json, subprocess, sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, "scripts")
import contracts, toolchain_paths
toolchain_paths.CONTRACTS_DIR = Path("contracts")
contracts.reset_cache()
import isolation_headers
public = Path(sys.argv[1])
problems = []
verdicts = {item["file"]: item for item in isolation_headers.scan_site(public)}
want = {"Runner-Playground.html": ("live", False), "Live-Autorun.html": ("live", True), "Swift-Playground.html": ("live", True),
        "Discussions/Runner-Printable.html": ("live", False), "Live-Box.html": ("frame", True)}
for name, (verdict, reads) in want.items():
    got = verdicts.get(name)
    if got is None or got["verdict"] != verdict or got["readsInput"] != reads:
        problems.append(f"{name}: the publish's rule says {got}, not {verdict} (reads input: {reads})")
for name in ("Help-Sessions.html", "Live-Framed.html", "Live-Plain-Link.html", "Runner-Not-Opted.html"):
    if name in verdicts:
        problems.append(f"{name} has no code that can ask, yet the publish's rule says {verdicts[name]}")
outcome = {"live": [], "notLive": [verdicts["Live-Box.html"]] if "Live-Box.html" in verdicts else [], "capped": []}
notes = isolation_headers.note_lines(public, outcome)
if notes != [f"plantoir: note: Live Box.md: " + contracts.section("shared-rules", "codeRunnerBlocks", "words")["notLiveBecause"].replace("{what}", contracts.section("shared-rules", "codeRunnerBlocks", "words")["notLiveFrame"])]:
    problems.append(f"the note line for Live Box is {notes}")
script = """
import { headersFor, PAGE_HEADERS, ENGINE_HEADERS } from "./support/quartz/cli/plantoirIsolation.mjs"
const pub = process.argv[1]
const cases = [["/Runner-Playground", PAGE_HEADERS], ["/Live-Autorun", PAGE_HEADERS], ["/Swift-Playground", PAGE_HEADERS],
  ["/Live-Box", {}], ["/Live-Framed", {}], ["/Help-Sessions", {}], ["/", {}],
  ["/static/pyodide/pyodide.mjs", ENGINE_HEADERS], ["/static/swift/plantoir-swift-worker.js", ENGINE_HEADERS], ["/index.css", {}]]
const wrong = []
for (const [address, want] of cases) {
  const got = headersFor(pub, address)
  if (JSON.stringify(got) !== JSON.stringify(want)) wrong.push(address + " " + JSON.stringify(got))
}
console.log(JSON.stringify(wrong))
"""
said = subprocess.run(["node", "--input-type=module", "-e", script, str(public)], capture_output=True, text=True)
try:
    wrong = json.loads(said.stdout.strip().splitlines()[-1])
except Exception:
    wrong = [f"the preview's rule did not run: {said.stderr.strip()[:300]}"]
for item in wrong:
    problems.append(f"the preview's headers: {item}")
postscript = (public / "postscript.js").read_text(encoding="utf-8", errors="ignore") if (public / "postscript.js").is_file() else ""
if "cross-origin-embedder-policy" not in postscript:
    problems.append("the site's script does not carry the router's isolation check (PLANTOIR-ISOLATION-NAV)")
for problem in problems:
    print("   " + problem)
sys.exit(1 if problems else 0)
LIVEPY
then
  pass "live input: the publish's rule and the preview's agree on the built pages - code that can ask is isolated (Python, Swift, a printable page), a page with a frame keeps the box and is named on a note line, plain pages get nothing, the engine folders get their own header - and the site's router carries the isolation check (#583)"
else
  fail "live input: the built pages are not isolated as codeRunnerBlocks.isolation says (#583)"
fi

# ---- 6k. Self-check quizzes (#563), as the build left them ----
# The site's side: every quiz on the planted Quiz Fixture is the kind - or
# the problem - contracts/shared-rules.json -> quizCallouts.recognise says,
# in order, with its correct choices or answer lines, and the CR LF page too
# (S1). The folder check's side: one plantoir: error: line per problem, with
# the quiz's place and its line in the teacher's file, one quizzesNotReady
# finding, and no line saying the two read a quiz differently. The
# look-alikes are no quiz; no tick reaches a quiz page; no planted answer or
# explanation is in the search index, the feed, the sitemap or a summary
# (Q5, S3); every word the site shows is in its script; the hidden page is
# named nowhere; a transcluded quiz keeps its own page's name (S5).
if python3 - "$SITE_PUBLIC" /tmp/verify_main_build.log <<'QUIZPY'
import html, json, re, sys
from pathlib import Path
public, log = Path(sys.argv[1]), Path(sys.argv[2])
rules = json.load(open("contracts/shared-rules.json", encoding="utf-8"))["quizCallouts"]
problems = []
said = log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""
def page(name):
    path = public / name
    return path.read_text(encoding="utf-8") if path.is_file() else ""
def quizzes_in(text):
    found = []
    for attributes in re.findall(r'<blockquote class="[^"]*\bplantoir-quiz\b[^"]*"([^>]*)>', text):
        get = lambda name: (re.search(name + r'="([^"]*)"', attributes) or [None, None])[1]
        found.append({"n": get("data-quiz-n"), "kind": get("data-quiz-kind"), "problem": get("data-quiz-problem"),
                      "data": json.loads(html.unescape(get("data-quiz") or "{}")), "source": get("data-quiz-source")})
    return found
# The fixture, case by case, as the plant laid it out.
fixture_lines = Path("courses/EXC2O/Quiz Fixture.md").read_text(encoding="utf-8").split("\n")
expected, lines_said = [], []
top = 0
for number, case in enumerate(rules["recognise"]["cases"], start=1):
    if "\r" in case["markdown"]:
        continue
    start = fixture_lines.index(f"Case {number}: {case['name']}.") + 3  # its markdown's first line, 1-based
    for quiz in case["quizzes"]:
        n = None
        if quiz.get("problem") != "notAtTopLevel":
            top += 1
            n = top
        if "problem" in quiz:
            expected.append(("notReady", quiz["problem"], {}))
            reason = rules["words"]["problems"][quiz["problem"]]
            for key, value in quiz.get("fill", {}).items():
                reason = reason.replace("{" + key + "}", str(value))
            where = f"quiz {n}, line {start + quiz['line'] - 1}" if n is not None else f"line {start + quiz['line'] - 1}"
            lines_said.append(f"plantoir: error: Quiz Fixture.md: {where}: {reason}")
        else:
            data = {"correct": quiz["correct"]} if quiz["kind"] in ("single", "multiple") else {"answers": quiz["answers"]}
            expected.append((quiz["kind"], None, data))
got = [(quiz["kind"], quiz["problem"], quiz["data"] if quiz["kind"] != "notReady" else {}) for quiz in quizzes_in(page("Quiz-Fixture.html"))]
if got != expected:
    problems.append(f"Quiz Fixture's quizzes are not the contract's: got {got}, expected {expected}")
for line in lines_said:
    if line not in said:
        problems.append("the build did not say: " + line)
counted = len(re.findall(r"plantoir: error: Quiz Fixture\.md: ", said))
if counted != len(lines_said):
    problems.append(f"the build said {counted} plantoir: error: lines for Quiz Fixture, expected {len(lines_said)}")
if rules["words"]["problems"]["readDifferently"] in said:
    problems.append("the site and the folder check read a quiz differently: " + re.search(r"plantoir: error: [^\n]*" + re.escape(rules["words"]["problems"]["readDifferently"][:30]), said).group(0))
markers = [line for line in said.splitlines() if "PLANTOIR_HEALTH:" in line and '"quizzesNotReady"' in line]
if len(markers) != 1 or f'"sentence": "{len(lines_said)} self-check questions' not in markers[0]:
    problems.append(f"expected one quizzesNotReady finding for {len(lines_said)} questions, got {markers}")
crlf = quizzes_in(page("Quiz-CRLF.html"))
if [(quiz["kind"], quiz["data"]) for quiz in crlf] != [("short", {"answers": ["$2^7$"]})]:
    problems.append(f"the page saved with CR LF read as {crlf}")
shown = page("Quiz-Code-Shown.html")
if not shown or "plantoir-quiz\"" in shown or "data-quiz" in shown:
    problems.append("Quiz Code Shown is missing or was made a quiz")
code = re.sub(r"<span[^>]*>|</span>", "", shown).replace("&gt;", ">")
if len(re.findall(r"<code>> \[!quiz\] Shown as code[^\n]*\n> > \[!answer\]- Answer\n> > a\n</code>", code)) != 3:
    problems.append("quiz syntax shown as indented code was changed (a line added to the code)")
if "Quiz Code Shown" in "\n".join(line for line in said.splitlines() if "plantoir: error:" in line):
    problems.append("quiz syntax shown as indented code was named as a folder problem")
summary = re.findall(r'<meta name="description" content="([^"]*)"', page("Quiz-Summary.html"))
if summary != ["Fill … and …."]:
    problems.append(f"a summary that opens with blanks reads {summary}, expected 'Fill … and ….'")
lookalikes = page("Quiz-Lookalikes.html")
if not lookalikes or "plantoir-quiz" in lookalikes or "data-quiz" in lookalikes:
    problems.append("Quiz Lookalikes is missing or was made a quiz")
from html.parser import HTMLParser
class TickInsideAQuiz(HTMLParser):
    """A ticked box anywhere inside a quiz's blockquote (the answer key)."""
    def __init__(self):
        super().__init__()
        self.stack, self.ticked = [], 0
    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "blockquote":
            inside = bool(self.stack and self.stack[-1]) or "plantoir-quiz" in (attributes.get("class") or "").split()
            self.stack.append(inside)
        elif tag == "input" and "checked" in attributes and self.stack and self.stack[-1]:
            self.ticked += 1
    def handle_endtag(self, tag):
        if tag == "blockquote" and self.stack:
            self.stack.pop()
for name in ("Quiz-Fixture.html", "Quiz-Playground.html", "Quiz-Printable.html", "Quiz-CRLF.html", "Quiz-Host.html"):
    reader = TickInsideAQuiz()
    reader.feed(page(name))
    if reader.ticked:
        problems.append(f"{name} carries {reader.ticked} ticked box(es) inside a quiz (the answer key)")
host = quizzes_in(page("Quiz-Host.html"))
if [(quiz["n"], quiz["source"]) for quiz in host] != [("1", "Quiz-Host"), ("1", "Quiz-Source")]:
    problems.append(f"the transcluded quiz did not keep its own page's name: {host}")
# Answers and explanations: only on their own pages, never in a summary.
for path in public.rglob("*"):
    if not path.is_file() or path.suffix not in (".html", ".json", ".xml", ".txt"):
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    for secret in ("playground-explain-7f3a", "printable-answer-7f3a", "printable-explain-7f3a", "summary-answer-7f3a"):
        if secret in text and path.name not in ("Quiz-Playground.html", "Quiz-Printable.html", "Quiz-Summary.html"):
            problems.append(f"{secret} is in {path.relative_to(public)}")
playground = page("Quiz-Playground.html")
for summary in re.findall(r'<meta (?:name="description"|property="og:description") content="([^"]*)"', playground):
    if "2^7" in summary or "playground-explain" in summary:
        problems.append("Quiz Playground's summary gives its answer away: " + summary)
index = json.loads(page("static/contentIndex.json") or "{}")
if "2^7" in index.get("Quiz-Playground", {}).get("content", "x2^7"):
    problems.append("the search index holds Quiz Playground's answer")
if "lookalike-answer-7f3a" not in index.get("Quiz-Lookalikes", {}).get("content", ""):
    problems.append("a top-level [!answer] outside a quiz was taken out of the search index")
script = page("postscript.js")
client = Path("support/quartz/components/scripts/quiz.inline.ts").read_text(encoding="utf-8")
for key in sorted(set(re.findall(r'\bword\("([A-Za-z]+)"', client))):
    value = rules["words"]["site"][key]
    if value not in script and json.dumps(value)[1:-1] not in script:
        problems.append(f"the site's script does not carry words.site.{key}")
if (public / "Quiz-Hidden.html").exists() or "Quiz Hidden" in "\n".join(line for line in said.splitlines() if "plantoir: error:" in line):
    problems.append("the hidden quiz page was built or named")
for problem in problems:
    print("   " + problem)
sys.exit(1 if problems else 0)
QUIZPY
then
  pass "self-check quizzes: every quiz the contract names is read alike by the site and the folder check, each problem said with its line, the look-alikes and the hidden page left alone, no tick and no answer on the site but where a student asks for it (#563)"
else
  fail "self-check quizzes: one of the checks above failed (#563)"
fi

# ---- 6l. Task boxes students tick (#519), as the build left them ----
# Every task box outside a quiz, on every page of the site, lost `disabled`,
# carries plantoir-task, the page it was written on and an id, and sits first
# in a plantoir-task-label; Task Fixture's and Task CRLF's ids are the
# contract's itemText ids in order (so the real build - Quartz's text
# transform, a callout's inserted line, a page saved with CR LF - stamps what
# the contract says); Task Host's transcluded copies carry Task-Fixture; every
# box inside a quiz (a not-ready quiz's choices) is still disabled and
# unstamped; the script and the styles are in every page's postscript.js and
# index.css.
if python3 - "$SITE_PUBLIC" <<'TASKPY'
import json, sys
from html.parser import HTMLParser
from pathlib import Path
public = Path(sys.argv[1])
rules = json.load(open("contracts/shared-rules.json", encoding="utf-8"))["taskBoxes"]
problems = []
class Boxes(HTMLParser):
    """Each checkbox in a task item: its attributes, whether a quiz holds it,
    and whether it opens a plantoir-task-label."""
    def __init__(self):
        super().__init__()
        self.quiz_depth, self.stack, self.boxes, self.last_start = 0, [], [], None
    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        classes = (attributes.get("class") or "").split()
        if tag == "input" and attributes.get("type") == "checkbox":
            in_task_item = any(item == "li-task" for item in self.stack[-2:])
            first_in_label = self.last_start is not None and self.last_start[0] == "label" \
                and "plantoir-task-label" in self.last_start[1]
            self.boxes.append({"attributes": attributes, "in_quiz": self.quiz_depth > 0,
                               "first_in_label": first_in_label, "task_item": in_task_item or first_in_label})
        if tag not in ("input", "img", "br", "hr", "meta", "link", "wbr", "source"):
            marker = "li-task" if tag == "li" and "task-list-item" in classes else tag
            quiz = tag == "blockquote" and "plantoir-quiz" in classes
            self.stack.append(marker)
            if quiz or (self.quiz_depth > 0):
                self.quiz_depth += 1
        self.last_start = (tag, classes)
    def handle_endtag(self, tag):
        if tag in ("input", "img", "br", "hr", "meta", "link", "wbr", "source"):
            return
        if self.stack:
            self.stack.pop()
            if self.quiz_depth > 0:
                self.quiz_depth -= 1
        self.last_start = None
def boxes_in(path):
    reader = Boxes()
    reader.feed(path.read_text(encoding="utf-8", errors="replace"))
    return reader.boxes
tickable, kept, pages = 0, 0, 0  # boxes outside quizzes, inside them, pages holding either
for path in sorted(public.rglob("*.html")):
    found = boxes_in(path)
    if found:
        pages += 1
    for box in found:
        attributes = box["attributes"]
        if not box["task_item"]:
            continue  # a checkbox a page wrote itself is not a task item (review F5)
        stamped = "plantoir-task" in (attributes.get("class") or "").split()
        if box["in_quiz"]:
            if attributes.get("class") and "plantoir-quiz-input" in attributes["class"]:
                continue
            kept += 1
            if stamped or "data-task-item" in attributes or "disabled" not in attributes:
                problems.append(f"{path.relative_to(public)}: a box inside a quiz was changed: {attributes}")
            continue
        tickable += 1
        if not stamped or "disabled" in attributes or not attributes.get("data-task-page") \
                or len(attributes.get("data-task-item") or "") != 8 or not box["first_in_label"]:
            problems.append(f"{path.relative_to(public)}: a task box outside a quiz was not made tickable: {attributes}")
def ids_on(name):
    path = public / name
    return [box["attributes"].get("data-task-item") for box in boxes_in(path)] if path.is_file() else None
def pages_on(name):
    path = public / name
    return [box["attributes"].get("data-task-page") for box in boxes_in(path)] if path.is_file() else None
expected = []
for case in rules["itemText"]["cases"]:
    if not case.get("crlf"):
        expected += [item["id"] for item in case["items"]]
fixture = ids_on("Task-Fixture.html")
if fixture is None or fixture[:len(expected)] != expected or len(fixture) != len(expected) + 3:
    problems.append(f"Task Fixture's ids are not the contract's: got {fixture}, expected {expected} and the Checklist's three")
crlf = [case for case in rules["itemText"]["cases"] if case.get("crlf")][0]
if ids_on("Task-CRLF.html") != [item["id"] for item in crlf["items"]]:
    problems.append(f"the page saved with CR LF reads {ids_on('Task-CRLF.html')}")
if set(pages_on("Task-Fixture.html") or ["none"]) != {"Task-Fixture"}:
    problems.append(f"Task Fixture's boxes name {set(pages_on('Task-Fixture.html') or [])}")
host = pages_on("Task-Host.html")
if host != ["Task-Host"] + ["Task-Fixture"] * 6:
    problems.append(f"the transcluded boxes did not keep their source page's name: {host}")
if (ids_on("Task-Host.html") or [None])[1:4] != (fixture or [None, None, None])[-3:]:
    problems.append("a transcluded box's id is not its source's")
raw = boxes_in(public / "Task-Raw-Box.html") if (public / "Task-Raw-Box.html").is_file() else []
if len(raw) != 1 or raw[0]["task_item"] or "plantoir-task" in (raw[0]["attributes"].get("class") or ""):
    problems.append(f"Task Raw Box's own checkbox was read as a task item or changed: {raw}")
if kept == 0:
    problems.append("no box inside a quiz was found to check (the not-ready quizzes on Quiz Fixture have some)")
script = (public / "postscript.js").read_text(encoding="utf-8") if (public / "postscript.js").is_file() else ""
style = (public / "index.css").read_text(encoding="utf-8") if (public / "index.css").is_file() else ""
if "plantoir:task:" not in script:
    problems.append("the site's script does not carry the task boxes'")
if "plantoir-task-label" not in style:
    problems.append("the site's styles do not carry the task boxes'")
for problem in problems[:20]:
    print("   " + problem)
print(f"   {tickable} task boxes outside quizzes on {pages} pages; {kept} inside quizzes")
sys.exit(1 if problems else 0)
TASKPY
then
  pass "task boxes: every box outside a quiz on every page is tickable, labelled and stamped with its page and the contract's id (a callout, a rewritten link and CR LF included), a transcluded box keeps its source page, and a quiz's boxes are left as they were (#519)"
else
  fail "task boxes: one of the checks above failed (#519)"
fi

# ---- 6m. My Progress (#545), as the build left it ----
# The page and the manifest are there; Progress Fixture's row is in the
# manifest under Unit 1, Day 2 in the Unit 1 table with exactly its four
# counted items, the contract's ids of their words, the teacher's [x] ticked;
# the page draws no date line (no content-meta: Q6); the two items
# outside the section are not; Key Links' first bullet links the page, once;
# the page has no Backlinks list; the sidebar's pin carries the page's slug
# and All Classes; and the build said so on its PLANTOIR_MY_PROGRESS: line.
if python3 - "$SITE_PUBLIC" <<'PROGRESSPY'
import json, re, sys
from pathlib import Path
sys.path.insert(0, "scripts")
site = Path(sys.argv[1])
problems = []
def fnv1a(text):
    value = 0x811c9dc5
    data = text.encode("utf-16-le")
    for index in range(0, len(data), 2):
        value ^= data[index] | (data[index + 1] << 8)
        value = (value * 0x01000193) & 0xffffffff
    return format(value, "08x")
rules_words = json.load(open("contracts/shared-rules.json", encoding="utf-8"))["myProgress"]["words"]
manifest_path = site / "progress-manifest.json"
page_path = site / "My-Progress.html"
if not manifest_path.is_file() or not page_path.is_file():
    problems.append("My-Progress.html or progress-manifest.json is missing")
else:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    rows = []
    for unit in manifest["units"]:
        for known in unit["classes"]:
            for page in known["pages"]:
                rows.append((unit["label"], known["label"], page))
    for page in manifest["other"]["pages"]:
        rows.append((manifest["other"]["label"], None, page))
    mine = [row for row in rows if row[2]["title"] == "Progress Fixture"]
    # #603: each item also carries its words, read off the built page's
    # label, and its success-criteria heading's anchor.
    want = [{"id": fnv1a(text), "checked": False, "text": text, "anchor": "success-criteria"} for text in
            ("I can name a variable", "I can print a value", "I can comment my code", "I can read an error message")]
    want[2]["checked"] = True
    if len(mine) != 1:
        problems.append(f"Progress Fixture is in the manifest {len(mine)} times")
    else:
        unit, label, page = mine[0]
        if (unit, label, page["slug"]) != ("Unit 1", "Unit 1, Day 2", "Progress-Fixture"):
            problems.append(f"Progress Fixture is under {unit} / {label} at {page['slug']}")
        if page["items"] != want:
            problems.append(f"Progress Fixture counts {page['items']}, expected {want}")
    html = page_path.read_text(encoding="utf-8")
    if "data-plantoir-progress" not in html:
        problems.append("My-Progress.html has no placeholder for the page's script")
    if 'class="backlinks"' in html:
        problems.append("My-Progress.html carries a Backlinks list")
    if "content-meta" in html:
        problems.append("My-Progress.html shows a date line")
    if 'name="description" content="' + rules_words["description"] + '"' not in html:
        problems.append("My-Progress.html's meta description is not words.description")
key_links = (site / "Key-Links.html").read_text(encoding="utf-8")
article = key_links.split("<article", 1)[-1].split("</article>", 1)[0]
links = re.findall(r'<li><a href="([^"]*)"', article)
if not links or not links[0].endswith("My-Progress"):
    problems.append(f"Key Links' first bullet is {links[:1]}, not My Progress")
if sum(1 for link in re.findall(r'href="([^"]*)"', article) if link.endswith("My-Progress")) != 1:
    problems.append("Key Links does not link My Progress exactly once")
script = (site / "postscript.js").read_text(encoding="utf-8")
if '{slug:"My-Progress",after:["All-Classes"]}' not in script:
    problems.append("the sidebar's pin does not carry the page's slug and All Classes")
if "progress-manifest.json" not in script:
    problems.append("the page's script is not in postscript.js")
log = Path("/tmp/verify_main_build.log").read_text(encoding="utf-8", errors="replace")
if 'PLANTOIR_MY_PROGRESS: {"course": "EXC2O", "section": 1, "built": true' not in log:
    problems.append("the build printed no PLANTOIR_MY_PROGRESS: line saying it made the page")
for problem in problems:
    print("   " + problem)
sys.exit(1 if problems else 0)
PROGRESSPY
then
  pass "My Progress: the page and the manifest built, Progress Fixture's four counted items under Unit 1, Day 2 with the contract's ids and the teacher's [x], Key Links' first bullet, no date line and no Backlinks list, the sidebar's pin, and the build's marker line (#545)"
else
  fail "My Progress: one of the checks above failed (#545)"
fi

# ---- 6n. Every example in the page-authoring skill, as the build left it (#596) ----
# Each example the skill gives (planted above as "Authoring Example NN") is
# read back from the built site as the feature the skill says it is: every
# example must match exactly ONE claim below and every claim exactly one
# example, so an example added to the skill without a claim here fails, as
# does a claim whose example was edited away. "Authoring Claims" carries what
# the prose says: two prices in a paragraph are read as maths and `\$` is
# not, a spaced `$ x $` is typeset, a [words](Page Name.md) link is not a
# link, and an unknown callout kind is still a callout with its own title.
if python3 - "$SITE_PUBLIC" support/agent_guidance/skills/plantoir-page-authoring/SKILL.md <<'AUTHORPY'
import re, sys
from pathlib import Path
public, skill_path = Path(sys.argv[1]), Path(sys.argv[2])
lines = skill_path.read_text(encoding="utf-8").split("\n")
examples, index = [], 0
while index < len(lines):
    opening = re.match(r"^(`{3,})(markdown|mermaid)\s*$", lines[index])
    if not opening:
        index += 1
        continue
    fence, kind, body = opening.group(1), opening.group(2), []
    index += 1
    while index < len(lines) and lines[index] != fence:
        body.append(lines[index])
        index += 1
    index += 1
    text = "\n".join(body)
    examples.append("```mermaid\n" + text + "\n```" if kind == "mermaid" else text)
def article(page):
    path = public / f"{page}.html"
    if not path.is_file():
        return None
    html = path.read_text(encoding="utf-8", errors="replace")
    found = re.search(r"<article[^>]*>(.*?)</article>", html, re.S)
    return found.group(1) if found else ""
def tasks(html):
    return len(re.findall(r'<input type="checkbox"[^>]*class="plantoir-task"', html))
def has_file(href):
    return (public / href.lstrip("./")).is_file()
# (a text only that example holds, what it must build as, the check)
claims = [
    ("title: Slope as a Rate of Change", "settings: the title, tags and maths",
     lambda a, p: "Slope as a Rate of Change" in p["full"] and 'class="katex"' in a and "tags/unit-2" in p["full"]),
    ("==highlighted==", "text: bold, italic, struck, highlighted, arrows, keys",
     lambda a, p: all(s in a for s in ("<strong>bold</strong>", "<em>italic</em>", "<del>", 'class="text-highlight"', "→", "⇒", "<kbd>Ctrl</kbd>"))),
    ("> [!warning] Where people usually go wrong", "callouts: a titled warning and an untitled tip",
     lambda a, p: 'data-callout="warning"' in a and "Where people usually go wrong" in a and re.search(r'data-callout="tip".*?<p>Tip</p>', a, re.S)),
    ("> [!success]- Worked answer", "foldable callouts: one folded shut, one open",
     lambda a, p: re.search(r'class="callout success is-collapsible is-collapsed"', a) and re.search(r'class="callout example is-collapsible"(?! is-collapsed)', a)),
    ("graph LR", "a Mermaid flowchart",
     lambda a, p: '<code class="mermaid"' in a and "Read the problem" in a),
    ("pie title How a class period is spent", "a Mermaid pie chart",
     lambda a, p: '<code class="mermaid"' in a and "pie title" in a),
    ("| Representation | Shows best | Hides |", "a table with maths in a cell",
     lambda a, p: "<table>" in a and re.search(r"<td>Equation <span class=\"katex\"", a)),
    ("Chemistry works too", "inline, display and chemistry maths",
     lambda a, p: 'class="katex-display"' in a and "\\ce" not in re.sub(r"<annotation.*?</annotation>", "", a, flags=re.S) and "katex-error" not in a),
    ("def slope(x1, y1, x2, y2):", "a coloured code block with line numbers, and code in a sentence",
     lambda a, p: 'data-language="python"' in a and a.count("data-line") >= 4 and "<code>print()</code>" in a
     and "font-variant-ligatures" in (public / "index.css").read_text(encoding="utf-8")),
    ("- [ ] Estimate before calculating", "a checklist students tick, one box ticked to start",
     lambda a, p: tasks(a) == 3 and len(re.findall(r'<input type="checkbox" checked class="plantoir-task"', a)) == 1),
    ("## Success criteria", "a page with three success criteria (one ticked) and a checklist under another heading",
     lambda a, p: 'id="success-criteria"' in a and 'id="practice"' in a and tasks(a) == 4
     and len(re.findall(r'<input type="checkbox" checked class="plantoir-task"', a)) == 1 and 'class="katex"' in a),
    ("See [[Slope]] before class.", "links: a page, other words, a heading, a website",
     lambda a, p: 'href="./Slope"' in a and ">what slope means<" in a and 'href="./Slope#finding-the-slope-from-two-points"' in a and 'class="external"' in a),
    ("![[Slope]]", "one page shown inside another, whole and by a heading",
     lambda a, p: a.count('class="transclude"') == 2 and "plantoir-authoring-slope-7f3a" in a and "Rise over run" in a),
    ("[^1]: From *al-jabr*", "a footnote listed at the bottom",
     lambda a, p: "data-footnote-ref" in a and 'class="footnotes"' in a and "al-jabr" in a),
    ("title: Practice - Two-Step Equations", "tags: shown on the page and listed on each tag's page",
     lambda a, p: 'class="internal tag-link"' in p["full"] and (public / "tags" / "unit-2.html").is_file()
     and p["slug"] in (public / "tags" / "unit-2.html").read_text(encoding="utf-8")),
    ("![[cell-diagram.png]]", "pictures and PDFs from Media",
     lambda a, p: len(re.findall(r'<img src="\./Media/cell-diagram\.png"', a)) == 3 and 'width="300"' in a
     and 'alt="A plant cell with the nucleus labelled"' in a and '<iframe src="./Media/Unit-2-Review.pdf" class="pdf">' in a
     and 'href="./Media/Unit-2-Review.pdf"' in a and has_file("Media/cell-diagram.png") and has_file("Media/Unit-2-Review.pdf")),
    ("![](https://www.youtube.com/watch?v=", "YouTube, Vimeo, GeoGebra and PhET players",
     lambda a, p: 'src="https://www.youtube.com/embed/' in a and '<iframe src="https://player.vimeo.com/video/' in a
     and '<iframe src="https://www.geogebra.org/' in a and '<iframe src="https://phet.colorado.edu/' in a),
    ("%% Tomorrow:", "a note only the teacher sees",
     lambda a, p: "Students see only this sentence." in a and "Tomorrow" not in p["full"]),
    ("title: Unit 3 Test Review", "publish: false keeps the page off the site",
     lambda a, p: a is None),
    ("title: Concepts", "a folder's front page with its list",
     lambda a, p: "The clean statement of each idea" in a and 'href="./Rate-of-Change"' in a),
    ("title: Unit 2, Day 3", "a class page: an agenda and a checklist",
     lambda a, p: 'id="agenda"' in a and "Slope-Practice" in a and tasks(a) == 1),
    ("title: Key Links", "Key Links: a list of links",
     lambda a, p: a.count('class="internal') >= 3 and "How Marks Work" in a),
]
problems, used = [], set()
for number, text in enumerate(examples, start=1):
    slug = f"Authoring-Example-{number:02d}"
    matching = [claim for claim in claims if claim[0] in text]
    if len(matching) != 1:
        problems.append(f"example {number} matches {len(matching)} claims here (it must match one): {text[:60]!r}")
        continue
    marker, what, check = matching[0]
    if marker in used:
        problems.append(f"two examples match the claim {marker!r}")
    used.add(marker)
    body = article(slug)
    full = (public / f"{slug}.html").read_text(encoding="utf-8", errors="replace") if body is not None else ""
    if body is None and marker != "title: Unit 3 Test Review":
        problems.append(f"example {number} ({what}): {slug}.html was not built")
        continue
    try:
        ok = check(body, {"full": full, "slug": slug})
    except Exception as error:  # a check that cannot read the page is a failure, said
        ok, what = False, f"{what} ({error})"
    if not ok:
        problems.append(f"example {number} did not build as {what}")
for marker, what, _ in claims:
    if marker not in used:
        problems.append(f"no example in the skill holds {marker!r} ({what})")
claims_page = article("Authoring-Claims") or ""
prose = {
    "two prices in a paragraph are typeset as maths": re.search(r"Money: it costs <span class=\"katex\"", claims_page),
    "\\$ keeps a price a price": "Escaped: it costs $5 and $10 today" in claims_page,
    "a spaced $ x + 1 $ is typeset on the site": re.search(r"Spaced: <span class=\"katex\"", claims_page),
    "[words](Page Name.md) is not a link": "[practice](Slope Practice.md)" in claims_page,
    "an unknown kind is a callout titled as written": re.search(r'data-callout="definition".*?<p>Slope', claims_page, re.S),
}
for said, held in prose.items():
    if not held:
        problems.append(f"the skill says {said}, and the built Authoring Claims page does not show it")
for problem in problems[:30]:
    print("   " + problem)
print(f"   {len(examples)} examples, {len(claims)} claims")
sys.exit(1 if problems else 0)
AUTHORPY
then
  pass "page-authoring skill: every example builds as the feature it claims - settings, text, callouts and folding, Mermaid, tables, maths, code, checklists, success criteria, links, embedded pages, footnotes, tags, Media pictures and PDFs, YouTube/Vimeo/GeoGebra/PhET, comments, publish: false, a folder's front page, a class page, Key Links - and what its prose says about prices, spaced maths, Markdown links and callout kinds holds (#596)"
else
  fail "page-authoring skill: an example did not build as the feature it claims, or an example has no claim (#596)"
fi

# ---- 6h, continued: the sidebar's page dot, by its text (#515) ----
# The rule is in the one index.css every page links, as the site's minifier
# writes it, and the page rows it relies on are still Quartz's: a page row's
# template is <li><a>, a folder row's is not. The rows themselves are drawn in
# the browser, so whether each one has its dot is checked there, below
# (browser-checks/sidebar_page_marker.mjs).
if python3 - "$SITE_PUBLIC" <<'MARKERPY'
import sys
from pathlib import Path
public = Path(sys.argv[1])
problems = []
stylesheet = public / "index.css"
css = stylesheet.read_text(encoding="utf-8") if stylesheet.is_file() else ""
for needle in (".explorer .explorer-content .folder-outer>ul>li:has(>a){",
               ".explorer .explorer-content .folder-outer>ul>li:has(>a):before{"):
    if needle not in css:
        problems.append(f"index.css lacks {needle}")
page = public / "Discussions" / "Marker-Fixture-Long.html"
text = page.read_text(encoding="utf-8") if page.is_file() else ""
if not text:
    problems.append("Discussions/Marker-Fixture-Long.html was not built")
if text and '<template id="template-file"><li><a href="#"></a></li></template>' not in text:
    problems.append("the sidebar's page-row template is no longer <li><a>: the dot's selector no longer means a page row")
if text and '<template id="template-folder"><li><div class="folder-container">' not in text:
    problems.append("the sidebar's folder-row template no longer starts <li><div class=\"folder-container\">: a folder row might take the dot")
for problem in problems:
    print("   " + problem)
sys.exit(1 if problems else 0)
MARKERPY
then
  pass "the sidebar's page dot is in the site's one stylesheet, and the sidebar's row templates are still the ones it tells apart (#515)"
else
  fail "the sidebar's page dot is missing from index.css, or the sidebar's row templates changed under it (#515)"
fi

# ---- #594: no page-view counter in the built site ----
# Quartz's default config loaded plausible.io's script on every page and
# sent each student's page view there; nobody set it up. The real build of
# the fixture site must carry it nowhere: no page and no script names it.
PLAUSIBLE_HITS="$(grep -rl --include='*.html' --include='*.js' --include='*.mjs' 'plausible\.io' "$SITE_PUBLIC" 2>/dev/null | head -5 || true)"
if [[ -n "$(find "$SITE_PUBLIC" -name 'postscript.js' -print -quit 2>/dev/null)" && -z "$PLAUSIBLE_HITS" ]]; then
  pass "the built site sends no page views anywhere: no page and no script in it names plausible.io, Quartz's default counter (#594)"
else
  fail "the built site still loads Quartz's page-view counter, or has no postscript.js to read (#594): ${PLAUSIBLE_HITS:-no postscript.js}"
fi

# ---- 6h, continued: the handout as a browser prints it (#454 review B1) ----
# Opened from Plantoir's preview, Print starts at the first page load. In a
# LIGHT page nothing used to wait for Quartz to draw the diagrams, so the
# planted worksheet printed its Mermaid diagram as source text. This prints it
# that way in headless Chrome for Testing and checks the diagram was drawn -
# in each of the three modes - and that the worksheet's Curriculum connection
# is printed in none of them nor under ⌘P (print media), while the page that
# did not opt in still prints its own under ⌘P (#498).
# It needs a browser on this Mac, so it runs when one is found (PLANTOIR_CHROME,
# or the copy documentation/06 F7 installs) and says SKIPPED otherwise.
PRINT_CHROME="${PLANTOIR_CHROME:-}"
if [[ -z "$PRINT_CHROME" ]]; then
  for candidate in "$HOME"/Library/Caches/Plantoir-dev/browsers/chrome/*/chrome-mac-*/"Google Chrome for Testing.app"/Contents/MacOS/"Google Chrome for Testing"; do
    [[ -x "$candidate" ]] && PRINT_CHROME="$candidate"
  done
fi
# Node 22's own WebSocket is what the check speaks to Chrome with; an older
# Node has none, so it is a SKIP there, not a failure.
if [[ -n "$PRINT_CHROME" && -x "$PRINT_CHROME" ]] \
   && node -e 'process.exit(typeof WebSocket === "function" ? 0 : 1)' >/dev/null 2>&1; then
  PRINT_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
  ( cd "$SITE_PUBLIC" && exec python3 -m http.server "$PRINT_PORT" --bind 127.0.0.1 ) >/dev/null 2>&1 &
  PRINT_SERVER_PID=$!
  if node browser-checks/print_handout.mjs "$PRINT_CHROME" "http://127.0.0.1:$PRINT_PORT/Printable-Fixture.html" \
       "http://127.0.0.1:$PRINT_PORT/Printable-Not-Opted.html" \
       "http://127.0.0.1:$PRINT_PORT/Printable-Too-Tall.html" >/tmp/verify_print_handout.log 2>&1; then
    pass "printable pages: each way of printing on portrait and landscape paper, printed to PDF and read back - the print layout ran and laid out every piece, nothing cut off; every question, answer, table row and the words around every picture, drawing, diagram and formula on paper; 110 lines of code each with its own number in a hairline box; page labels on every page where a printer reaches; Latin Modern; no boxes but the worked example's (#499); the diagram DRAWN (#454); no Curriculum connection in any handout or under ⌘P (#498); the menu prints nothing until a choice and remembers the paper; ⌘P leaves orientation to the browser's dialog (browser-checks/print_handout.mjs)"
  else
    fail "printable pages: a handout or ⌘P lost something, printed something it should not, or did not look as it should on paper (browser-checks/print_handout.mjs, #454, #498, #499)"
    cat /tmp/verify_print_handout.log
  fi
  # #501: ⌘P on a long page that is NOT printable, read back by its ink.
  if node browser-checks/print_plain_page.mjs "$PRINT_CHROME" "http://127.0.0.1:$PRINT_PORT/Plain-Long-Page.html" \
       >/tmp/verify_print_plain_page.log 2>&1; then
    pass "⌘P on a page that is not printable: a 40-paragraph page loaded in a laptop-sized window, printed on portrait and landscape letter paper - no sidebar's words on paper, every paragraph whole in the text, ink under every paragraph's first word, nothing past the paper's edge (#501, browser-checks/print_plain_page.mjs)"
  else
    fail "⌘P on a page that is not printable lost words under the sidebars or ran off the paper (browser-checks/print_plain_page.mjs, #501)"
    cat /tmp/verify_print_plain_page.log
  fi
  # #502: graphs drawn on a page whose own ids answered the names
  # function-plot reads, and on the next page the site's own page change
  # reaches from it.
  if node browser-checks/graphs_draw.mjs "$PRINT_CHROME" "http://127.0.0.1:$PRINT_PORT/Figures-Math-Heading.html" \
       "http://127.0.0.1:$PRINT_PORT/Figures-Fixture.html" \
       "http://127.0.0.1:$PRINT_PORT/Figures-Exports-Heading.html" >/tmp/verify_graphs_draw.log 2>&1; then
    pass "graphs on a page with a heading named Math, then on the Figures Fixture reached by the site's own page change from it, then on a page with a heading named Exports: every curve drawn, and the page's ids given back (#502, figureFences.pageIds, browser-checks/graphs_draw.mjs)"
  else
    fail "graphs were not drawn on a page whose own ids answer the names the graph engine reads, or on a page visited after it (browser-checks/graphs_draw.mjs, #502)"
    cat /tmp/verify_graphs_draw.log
  fi
  # #594: the Mermaid diagram on the Printable Fixture drawn under the very
  # policy a Netlify publish would send. The site is cloned, the publish's
  # own two _headers writers run on the clone in deploy.py's order, and the
  # check serves the clone with the policy line it reads from that file. The
  # engine comes from cdnjs, so with no network it is a SKIP, never a pass.
  MERMAID_SITE="$(mktemp -d /tmp/plantoir-verify-mermaid.XXXXXX)"
  cp -Rc "$SITE_PUBLIC/." "$MERMAID_SITE/" 2>/dev/null || cp -R "$SITE_PUBLIC/." "$MERMAID_SITE/"
  rm -f "$MERMAID_SITE/_headers"
  (cd scripts && python3 -c 'import sys; from pathlib import Path; import isolation_headers, netlify_badge; site = Path(sys.argv[1]); isolation_headers.publish_headers(site, "netlify", printer=lambda line: None); netlify_badge.write_netlify_headers_file(site)' "$MERMAID_SITE") >/tmp/verify_mermaid_draws.log 2>&1 || true
  MERMAID_STATUS=0
  node browser-checks/mermaid_draws.mjs "$PRINT_CHROME" "$MERMAID_SITE" /Printable-Fixture.html >>/tmp/verify_mermaid_draws.log 2>&1 || MERMAID_STATUS=$?
  if [[ "$MERMAID_STATUS" == "0" ]]; then
    pass "Mermaid diagrams drawn under the policy a Netlify publish sends to keep its ad badge off, read from the _headers the publish writes: the engine imported from cdnjs, no request refused by the policy - $(grep '^OK: ' /tmp/verify_mermaid_draws.log | head -1 | sed 's/^OK: //') (#594, browser-checks/mermaid_draws.mjs)"
  elif [[ "$MERMAID_STATUS" == "3" ]]; then
    skip "Mermaid diagrams under the Netlify ad-badge policy (#594): $(grep '^SKIPPED: ' /tmp/verify_mermaid_draws.log | head -1 | sed 's/^SKIPPED: //') - the diagram engine comes from cdnjs (browser-checks/mermaid_draws.mjs)"
  else
    fail "Mermaid diagrams were not drawn under the policy a Netlify publish sends, or the policy refused a request (browser-checks/mermaid_draws.mjs, #594)"
    cat /tmp/verify_mermaid_draws.log
  fi
  rm -rf "$MERMAID_SITE"
  # #515: the sidebar's page dot, on the rows the browser draws.
  if node browser-checks/sidebar_page_marker.mjs "$PRINT_CHROME" "http://127.0.0.1:$PRINT_PORT/Discussions/Marker-Fixture-Long.html" \
       "http://127.0.0.1:$PRINT_PORT/Discussions/index.html" "Discussions" "Tasks" \
       "Marker Fixture Page With A Title Long Enough To Wrap Onto A Second Line" >/tmp/verify_sidebar_page_marker.log 2>&1; then
    pass "the sidebar's page dot: every page row in an open folder and a folder inside it has its dot, no folder row and no page at the top level does, a wrapped title's second line starts under its first letter, every dot is level with its title's first line (a too-wide first word included), the current page and a hovered link keep Quartz's colours, in light and dark, on a folder page, and every dot at least 3:1 under forced colours - $(head -1 /tmp/verify_sidebar_page_marker.log | sed 's/^OK: //') against the sidebar (#515, browser-checks/sidebar_page_marker.mjs)"
  else
    fail "the sidebar's page dot is missing from a page row, on a folder row, too faint, or the wrapped title does not hang (browser-checks/sidebar_page_marker.mjs, #515)"
    cat /tmp/verify_sidebar_page_marker.log
  fi
  # #494: maths offline from the site's own KaTeX, and (#455 review S1)
  # print after a change of page keeps the stylesheets.
  if node browser-checks/maths_offline.mjs "$PRINT_CHROME" "http://127.0.0.1:$PRINT_PORT/Printable-Fixture.html" \
       "http://127.0.0.1:$PRINT_PORT/Runner-Playground.html" \
       "http://127.0.0.1:$PRINT_PORT/Discussions/Runner-Printable.html" >/tmp/verify_maths_offline.log 2>&1; then
    pass "maths with every other website refused: set in KaTeX's own faces from the site, nothing asked of a CDN; and a page printed after the site's own page change from a page one folder up keeps KaTeX's and the site's stylesheets (#494, #455 review S1, browser-checks/maths_offline.mjs)"
  else
    fail "maths did not render from the site's own KaTeX offline, or print after a page change lost its stylesheets (browser-checks/maths_offline.mjs, #494)"
    cat /tmp/verify_maths_offline.log
  fi
  kill "$PRINT_SERVER_PID" 2>/dev/null || true
  # #455: runnable code as a student runs it, against a server the check
  # starts itself so it can also play the hosts that break it.
  if node browser-checks/code_runner.mjs "$PRINT_CHROME" "$SITE_PUBLIC" /Runner-Playground.html /Discussions/Runner-Printable.html /Runner-Autorun.html \
       >/tmp/verify_code_runner.log 2>&1; then
    pass "runnable code in a browser: nothing of the engine fetched on load; Run prints, a traceback names the editor's line, input() echoes and ends in EOFError, Stop ends a loop and Run works again, one program at a time, each Run from a reset interpreter, too much output stopped and one huge print cut at the cap; a queued autorun started by hand runs once; edits kept, printed and Reset, a teacher's change sets them aside once; five page changes leave one thread; live input on an isolated page (#583: the field focused at Run, the prompt before it, the transcript byte for byte the box's, Ctrl-D and the end button, a two-line paste, IME and Escape, Stop and another block while it waits, echoes counted, an autorun that asks takes no focus and holds the queue, whole loads across the isolation line both ways, the handout's KaTeX), and the box's line where the page is not isolated; the editor's colours and line numbers (#585: Shiki's own lines untouched, the tokenizer's typed, the copy in step through undo, an input method, a saved edit, Reset and scrolling, 0 pixels off the typed letters, the frame's focus ring, one gutter style, no ligatures, an edited block printed coloured and numbered); a missing worker, a wrong .wasm type and a CSP without wasm each end in the contract's words - $(head -1 /tmp/verify_code_runner.log | sed 's/^OK: //') (#455, browser-checks/code_runner.mjs)"
  else
    fail "runnable code did not run in a browser as the contract says (browser-checks/code_runner.mjs, #455)"
    cat /tmp/verify_code_runner.log
  fi
  if node browser-checks/swift_runner.mjs "$PRINT_CHROME" "$SITE_PUBLIC" /Swift-Playground.html \
       >/tmp/verify_swift_runner.log 2>&1; then
    pass "runnable Swift in a browser: nothing fetched on load; read-only with its note; Run with input echoes it after each prompt, changed input changes the output, Stop ends a loop and Run works again, an index out of range shows its Fatal error line and the crash words, exit(3) its exit code, a block that did not compile says it is not ready; live input on an isolated page with the box's transcript, Embedded, full library and a prompt on the answer's line, Ctrl-D as nil, Stop while it waits (#583) - $(head -1 /tmp/verify_swift_runner.log | sed 's/^OK: //') (#493, browser-checks/swift_runner.mjs)"
  else
    fail "runnable Swift did not run in a browser as the contract says (browser-checks/swift_runner.mjs, #493)"
    cat /tmp/verify_swift_runner.log
  fi
  # #563: the self-check quizzes as a student answers them, against a server
  # the check starts itself.
  if node browser-checks/quiz_check.mjs "$PRINT_CHROME" "$SITE_PUBLIC" >/tmp/verify_quiz_check.log 2>&1; then
    pass "self-check quizzes in a browser: every kind wrong then right in the contract's words, the explanation's text shown and its graph drawn, Show answer with KaTeX, nothing asked of any website while answering, the shuffle and its print order, keyboard folds and inert folded content, the score kept, cleared and storage refused, five page changes clean, a transcluded quiz on its own, code in a choice and an explanation asking live with Return ticking, checking and folding nothing (#583), and paper and the handout questions only - $(head -1 /tmp/verify_quiz_check.log | sed 's/^OK: //') (#563, browser-checks/quiz_check.mjs)"
  else
    fail "self-check quizzes did not answer in a browser as the contract says (browser-checks/quiz_check.mjs, #563)"
    cat /tmp/verify_quiz_check.log
  fi
  # #519: task boxes ticked in a browser, by mouse and keyboard, and on paper.
  if node browser-checks/task_boxes.mjs "$PRINT_CHROME" "$SITE_PUBLIC" >/tmp/verify_task_boxes.log 2>&1; then
    pass "task boxes in a browser: the Markdown's state until a box is changed and nothing written on load, the contract's key written and kept across a reload, the words, a link inside them, Tab and Space, a transcluded copy setting its source's tick in step, five page changes and one listener, a page the router built from the last one's elements showing its own ticks, a tick under old words ignored, a not-ready quiz left alone, storage refused, and ink for a tick on paper in both themes - $(head -1 /tmp/verify_task_boxes.log | sed 's/^OK: //') (#519, browser-checks/task_boxes.mjs)"
  else
    fail "task boxes did not tick in a browser as the contract says (browser-checks/task_boxes.mjs, #519)"
    cat /tmp/verify_task_boxes.log
  fi
  # #545: My Progress in a browser - Progress Fixture's own row, by name.
  if node browser-checks/my_progress.mjs "$PRINT_CHROME" "$SITE_PUBLIC" >/tmp/verify_my_progress.log 2>&1; then
    pass "My Progress in a browser: second in the sidebar, first in Key Links, two ticks counted under the right class, kept across a reload, an untick seen after Back, the fixture's row at 1 / 4 on a fresh profile (the teacher's [x]), every total the manifest's, read-only - $(head -1 /tmp/verify_my_progress.log | sed 's/^OK: //') (#545, browser-checks/my_progress.mjs)"
  else
    fail "My Progress did not count a student's ticks in a browser as the contract says (browser-checks/my_progress.mjs, #545)"
    cat /tmp/verify_my_progress.log
  fi
else
  RESULTS+=("⏭️  SKIPPED  the handout, and ⌘P on a page that is not printable, as a browser prints them, graphs drawn under a heading named Math (#502), Mermaid diagrams under the Netlify ad-badge policy (#594), the sidebar's page dot (#515), maths offline and print after a page change (#494), runnable code in a browser (#455), self-check quizzes in a browser (#563), task boxes in a browser (#519), and My Progress in a browser (#545): no Chrome for Testing, or no Node 22 or later, on this Mac (set PLANTOIR_CHROME; documentation/06-quartz-customizations.md F7)")
  echo "⏭️  SKIPPED  the handout, and ⌘P on a page that is not printable, as a browser prints them, graphs drawn under a heading named Math (#502), Mermaid diagrams under the Netlify ad-badge policy (#594), the sidebar's page dot (#515), maths offline and print after a page change (#494), runnable code in a browser (#455), self-check quizzes in a browser (#563), task boxes in a browser (#519), and My Progress in a browser (#545): no Chrome for Testing, or no Node 22 or later, on this Mac"
fi
# Two builds of one page are not byte-identical even in Quartz alone: the
# sidebar's list gets a random id every build (`id="ubcjug"` in `<ul
# class="explorer-ul overflow">`), so does a table of contents (`<ul id="…"
# class="overflow">`), and generated Curriculum and tag pages carry the build
# time (E1 review N3). This sets the sidebar's id aside and compares pages
# that have NEITHER of the other two - Figures Fixture and Help Sessions.
same_page_but_for_quartz_ids() {
  python3 - "$1" "$2" <<'SAMEPY'
import re, sys
def read(path):
    try:
        return re.sub(r'(class="explorer-ul overflow" id=")[^"]*"', r'\1"', open(path, encoding="utf-8").read())
    except OSError:
        return None
one, other = read(sys.argv[1]), read(sys.argv[2])
sys.exit(0 if one is not None and one == other else 1)
SAMEPY
}

# ---- 6i, continued: a second build draws nothing (#485 E1) ----
# The cache: the same figures, built again without --full-rebuild, are all
# found from before, the drawing engine is never started, and the page comes
# out byte for byte the same.
cp "$SITE_PUBLIC/Figures-Fixture.html" /tmp/verify_figures_first.html 2>/dev/null || true
cp "$SITE_PUBLIC/Swift-Playground.html" /tmp/verify_swift_first.html 2>/dev/null || true
if ./preview.sh EXC2O 1 --image "$DEV_TEST_IMAGE" --build-only >/tmp/verify_figures_second.log 2>&1 \
   && grep -Eq "Drew 0 diagrams \([1-9][0-9]* from before\)" /tmp/verify_figures_second.log \
   && same_page_but_for_quartz_ids "$SITE_PUBLIC/Figures-Fixture.html" /tmp/verify_figures_first.html; then
  pass "diagrams and graphs: a second build finds every figure from before, draws none, and the page is byte-identical (#485)"
else
  fail "diagrams and graphs: a second build drew again or changed the page (#485)"
  grep -n "Drew\|plantoir:" /tmp/verify_figures_second.log | head -5
fi
# Runnable Swift (#493 acceptance 10): the same build compiled nothing - the
# launcher found every block in the cache - the site has the same programs as
# the first build said (read from it, not a number written here: the quiz
# playground's two programs, #563, made a written "8 of 9" wrong), and the
# Swift page came out the same.
SWIFT_READY_FIRST="$(grep -Eo "[0-9]+ of [0-9]+ Swift programs on this site ready to run" /tmp/verify_main_build.log | tail -1)"
if ! grep -q "Swift program.* ready to run…" /tmp/verify_figures_second.log \
   && [[ -n "$SWIFT_READY_FIRST" ]] && grep -q "$SWIFT_READY_FIRST" /tmp/verify_figures_second.log \
   && same_page_but_for_quartz_ids "$SITE_PUBLIC/Swift-Playground.html" /tmp/verify_swift_first.html; then
  pass "runnable Swift: a second build compiles nothing and the Swift page is byte-identical (#493)"
else
  fail "runnable Swift: a second build compiled again or changed the Swift page (#493)"
  grep -n "Swift" /tmp/verify_figures_second.log | head -5
fi
restore_hit_fixture
trap release_verify_lock EXIT

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
  # ---- First: an OPEN preview is not killed to remake it (GitHub #94) ----
  # The launcher is about to remake this workspace (no builds mount). Before
  # #94 it stopped it without looking, ending whatever ran inside. Here a
  # pretend preview of section 2 runs inside it, and a pretend preview.sh for
  # section 2 runs on this Mac — the launcher that keeps a preview OPEN; a
  # preview without one is an orphan and is (correctly) remade over. `exec -a`
  # renames `sleep` so the process tables read exactly what a real preview
  # puts there (measured in this image: `docker top` shows
  # "python3 /opt/scripts/build_site.py … --section=2 --port 8082 300").
  # The run must refuse after the preview wait, say which preview, and leave
  # the workspace and the pretend preview exactly as they were.
  _old_id="$(docker inspect -f '{{.Id}}' "$CONTAINER_NAME" 2>/dev/null)"
  docker exec -d "$CONTAINER_NAME" bash -c \
    'exec -a "python3 /opt/scripts/build_site.py --host-os mac --course=EXC2O --section=2 --port 8082" sleep 300' \
    >/dev/null 2>&1
  bash -c 'exec -a "/bin/bash ./preview.sh EXC2O 2" sleep 300' &
  _pretend_launcher=$!
  sleep 1
  _refusal_started=$(date +%s)
  if ./preview.sh EXC2O 1 --image "$DEV_TEST_IMAGE" --build-only >/tmp/verify_in_use.log 2>&1; then
    fail "a remake went ahead while a preview from the folder was open (#94)"
  else
    pass "a remake refuses while a preview from the folder is open (#94)"
  fi
  _refusal_took=$(( $(date +%s) - _refusal_started ))
  _open_line="$(python3 -c 'import json,sys; s=json.load(open("contracts/app-rules.json"))["previewPorts"]["whenTheWorkspaceIsInUse"]["sentences"]["whenAPreviewIsOpen"][0]; print(s.replace("{course}","EXC2O").replace("{section}","2"))')"
  if grep -Fq -- "$_open_line" /tmp/verify_in_use.log; then
    pass "and says which preview is open, in the contract's words"
  else
    fail "the refusal did not say which preview was open"
    tail -15 /tmp/verify_in_use.log
  fi
  if [[ "$(docker inspect -f '{{.Id}}' "$CONTAINER_NAME" 2>/dev/null)" == "$_old_id" ]] \
     && docker top "$CONTAINER_NAME" 2>/dev/null | grep -Fq -- "--course=EXC2O --section=2"; then
    pass "and the workspace, and the preview in it, were left exactly as they were"
  else
    fail "the workspace was stopped or remade while a preview was open in it"
  fi
  if [[ "$_refusal_took" -ge 20 ]]; then
    pass "and it gave the preview ${_refusal_took} s to close before refusing"
  else
    fail "it refused after ${_refusal_took} s, before the preview wait was up"
  fi
  # End both pretend processes, and make sure they HAVE ended: the run below
  # is the remake this section exists to check, and it would otherwise meet
  # the same open preview and refuse.
  kill "$_pretend_launcher" >/dev/null 2>&1 || true
  wait "$_pretend_launcher" 2>/dev/null || true
  docker exec "$CONTAINER_NAME" python3 -c '
import os, signal
for entry in os.listdir("/proc"):
    if not entry.isdigit() or entry == str(os.getpid()):
        continue
    try:
        line = open("/proc/%s/cmdline" % entry, "rb").read().replace(b"\x00", b" ").decode("utf-8", "replace")
    except OSError:
        continue
    if "--course=EXC2O --section=2" in line:
        os.kill(int(entry), signal.SIGKILL)
' >/dev/null 2>&1 || true
  sleep 1
  if docker top "$CONTAINER_NAME" 2>/dev/null | grep -Fq -- "--course=EXC2O --section=2"; then
    fail "the pretend preview could not be ended, so the remake below is not a fair test"
  else
    pass "the pretend preview has ended, so the remake below has nothing in its way"
  fi
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
  # The printable pages planted for 6h are gone, so this build has none: the
  # print engine must have been taken out of the site again (#454 - a course
  # that does not print carries none of it).
  if [[ -f "$SITE_INDEX" && ! -e "$SITE_PUBLIC/static/pagedjs" ]]; then
    pass "and with no printable page left, the site no longer carries the print engine (#454)"
  else
    fail "the site still carries static/pagedjs with no printable page in it (#454)"
  fi
  # And no figures either (#485 E1): neither engine's folder, nothing drawn,
  # and a page that never had a figure byte for byte what the first build
  # made - the guarantee for every site without figures.
  if [[ -f "$SITE_INDEX" && ! -e "$SITE_PUBLIC/static/function-plot" && ! -e "$SITE_PUBLIC/static/tikz" ]] \
     && ! grep -q "Drew [0-9]* diagram" /tmp/verify_old_container.log \
     && ! grep -q "pl-figure" "$SITE_PUBLIC/Help-Sessions.html" \
     && same_page_but_for_quartz_ids "$SITE_PUBLIC/Help-Sessions.html" /tmp/verify_untouched_page.html; then
    pass "and with no figure left, the site carries neither figure engine, nothing is drawn, and a page without figures is byte-identical (#485)"
  else
    fail "a site with no figures still carries static/function-plot or static/tikz, drew something, or changed a page without figures (#485)"
  fi
  # And no runnable code (#455): the engine is taken out again, while the
  # site's own KaTeX stays - every site carries it (#494).
  if [[ -f "$SITE_INDEX" && ! -e "$SITE_PUBLIC/static/pyodide" && -f "$SITE_PUBLIC/static/katex/katex.min.css" ]]; then
    pass "and with no runnable code left, the site no longer carries Python, and still carries its own KaTeX (#455, #494)"
  else
    fail "a site with no runnable code still carries static/pyodide, or lost static/katex (#455, #494)"
  fi
  # And no quiz left (#563): the folder check says nothing, and no page is a
  # quiz.
  if [[ -f "$SITE_INDEX" ]] && ! grep -q "quizzesNotReady\|plantoir: error: Quiz" /tmp/verify_old_container.log \
     && ! grep -rlq "plantoir-quiz\"" "$SITE_PUBLIC" --include="*.html"; then
    pass "and with no quiz left, the folder check finds nothing and no page holds a quiz (#563)"
  else
    fail "a site with no quiz still reports a quiz problem or holds a quiz (#563)"
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
# that its website builder "is already running" (worded "already running with
# correct mount" until #382), never call `docker run`, and pass
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
VERIFY_COLON_ID="$(cd "$VERIFY_COLON_DIR" && /bin/pwd -P | shasum -a 256 | cut -c1-8)"
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
# And PUBLISH it, from inside the colon folder, to a folder whose name has a
# colon too, given the way a teacher might type it: relative (GitHub issue
# #227). rsync reads a colon before the first slash as another COMPUTER; the
# launcher used to say "Published" over an empty folder here. The folder
# publish needs no container, so this runs before the one above is removed
# only because that is the tidier order. PUBLISHED_FOLDER= is compared with
# the working folder as `/bin/pwd -P` spells it, which is how the launcher
# spells it.
VERIFY_COLON_PUBLISHED="$(cd "$VERIFY_COLON_DIR" && /bin/pwd -P)/out 26:27/section1"
if (cd "$VERIFY_COLON_DIR" && ./deploy.sh EXC2O 1 --to-folder "out 26:27" --non-interactive --image "$DEV_TEST_IMAGE") \
     >/tmp/verify_colon_folder_publish.log 2>&1; then
  pass "a folder publish from it, to a relative folder with a colon, finished"
else
  fail "a folder publish from it, to a relative folder with a colon, did not finish"
  tail -20 /tmp/verify_colon_folder_publish.log
fi
COLON_BUILT_PAGES="$(find "$VERIFY_COLON_BUILDS/EXC2O/section1/public" -name '*.html' 2>/dev/null | wc -l | tr -d ' ')"
COLON_PUBLISHED_PAGES="$(find "$VERIFY_COLON_DIR/out 26:27/section1" -name '*.html' 2>/dev/null | wc -l | tr -d ' ')"
if [[ -f "$VERIFY_COLON_DIR/out 26:27/section1/index.html" && "$COLON_PUBLISHED_PAGES" == "$COLON_BUILT_PAGES" ]]; then
  pass "and every page (${COLON_PUBLISHED_PAGES} of ${COLON_BUILT_PAGES}) is in that folder, inside the working folder"
else
  fail "the published folder holds ${COLON_PUBLISHED_PAGES:-0} of ${COLON_BUILT_PAGES:-0} pages"
fi
if grep -Fxq "PUBLISHED_FOLDER=${VERIFY_COLON_PUBLISHED}" /tmp/verify_colon_folder_publish.log; then
  pass "and the launcher named that folder by its full path"
else
  fail "the launcher did not name ${VERIFY_COLON_PUBLISHED} as the published folder"
  grep '^PUBLISHED_FOLDER=' /tmp/verify_colon_folder_publish.log || true
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
VERIFY_LOCK_ID="$(cd "$VERIFY_LOCK_DIR" && /bin/pwd -P | shasum -a 256 | cut -c1-8)"
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
