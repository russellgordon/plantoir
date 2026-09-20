#!/bin/bash
# The workspace is given its folders by NAME, and a teacher's folder can be
# called anything macOS lets them call it — including "Comm Tech 26:27", which
# is what the disk holds after somebody types "Comm Tech 26/27" in Finder.
#
# This runs the REAL block out of the three launchers (extracted between the
# CONTAINER MOUNT BLOCK markers) against the names that broke, and checks that
# all three launchers actually ASK for their folders through it — a correct
# helper that nothing calls would look exactly like a fix.
#
# Pure shell, no Docker and no network. Run it directly, or let verify.sh:
#
#     bash scripts/test_container_mount.sh
#
# What it deliberately does NOT check is that the daemon accepts what the
# helper produces. Only a real container can say that, and verify.sh's
# section 6e builds a real site from a real folder called ".plantoir-verify-26:27".
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0
CHECKS=0

pass() { CHECKS=$((CHECKS + 1)); echo "  ✅ $1"; }
fail() { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); echo "  ❌ $1"; }

check() {
  # check "<what>" <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1 — expected [$2], got [$3]"
  fi
}

extract_block() {
  awk '/^# >>> CONTAINER MOUNT BLOCK >>>/{inside=1} inside{print} /^# <<< CONTAINER MOUNT BLOCK <<</{inside=0}' "$1"
}

extract_container_function() {
  awk '/^run_container_with_mount\(\) \{/{inside=1} inside{print} inside && /^\}/{inside=0}' "$1"
}

# ---- The three launchers must carry the SAME block --------------------
echo "The block is the same in all three launchers"
FIRST="$(extract_block "$REPO/setup.sh")"
if [ -z "$FIRST" ]; then
  fail "setup.sh has no CONTAINER MOUNT BLOCK markers"
  exit 1
fi
for launcher in preview.sh deploy.sh; do
  if [ "$FIRST" = "$(extract_block "$REPO/$launcher")" ]; then
    pass "$launcher matches setup.sh"
  else
    fail "$launcher's block has drifted from setup.sh's"
  fi
done

# ---- And all three must USE it ----------------------------------------
# The whole function is NOT compared across the three: they are not identical
# today and never have been — deploy.sh carries one extra line
# (`ensure_image_present`) because it can be the first launcher a folder ever
# runs. What is pinned is the shape that matters.
echo
echo "All three launchers ask for their folders through the block"
for launcher in setup.sh preview.sh deploy.sh; do
  BODY="$(extract_container_function "$REPO/$launcher")"
  if [ -z "$BODY" ]; then
    fail "$launcher has no run_container_with_mount()"
    continue
  fi
  MOUNTS="$(printf '%s\n' "$BODY" | grep -c -- '--mount "\$(bind_mount_argument ')"
  check "$launcher asks for both folders through the helper" "2" "$MOUNTS"
  if printf '%s\n' "$BODY" | grep -q -- '-v "\$'; then
    fail "$launcher still names a folder with -v, which splits on ':'"
  else
    pass "$launcher names no folder with -v"
  fi
  SENTENCES="$(printf '%s\n' "$BODY" | grep -c 'say_this_folder_could_not_be_opened')"
  check "$launcher says the sentence when the folder is gone AND when the workspace is refused" \
    "2" "$SENTENCES"
  # The last two lines of the function, in order. Piece A adds a check after
  # the container is created, and a ragged tail here is what makes that a
  # conflict rather than an addition.
  check "$launcher ends the function with the failure branch closed" \
    "  fi
}" "$(printf '%s\n' "$BODY" | tail -2)"
done

# ---- Load the block and put names through it --------------------------
# shellcheck disable=SC1090
source /dev/stdin <<<"$FIRST"

echo
echo "The mount argument, for the names a teacher's folder can have"
TARGET="/teaching/courses"

check "an ordinary name" \
  'type=bind,"source=/Users/t/Desktop/plain 26-27/courses","target=/teaching/courses"' \
  "$(bind_mount_argument "/Users/t/Desktop/plain 26-27/courses" "$TARGET")"

# The name from the report this piece comes from. With -v, the argument below
# would have been read as four fields and "/teaching/courses" as the mode.
check "the colon Finder writes when a teacher types 26/27" \
  'type=bind,"source=/Users/t/Desktop/Comm Tech 26:27/courses","target=/teaching/courses"' \
  "$(bind_mount_argument "/Users/t/Desktop/Comm Tech 26:27/courses" "$TARGET")"

# A comma is what an UNQUOTED --mount would have died on: the fields are one
# CSV record, so a bare comma starts a field that is not a key=value pair.
check "a comma" \
  'type=bind,"source=/Users/t/Comm Tech 26,27/courses","target=/teaching/courses"' \
  "$(bind_mount_argument "/Users/t/Comm Tech 26,27/courses" "$TARGET")"

# RFC 4180: a quote inside a quoted field is written twice. Getting this wrong
# is not a near miss — it ends the field early and the daemon refuses.
check "a double quote, doubled" \
  'type=bind,"source=/Users/t/Say ""hi"" 26/courses","target=/teaching/courses"' \
  "$(bind_mount_argument '/Users/t/Say "hi" 26/courses' "$TARGET")"

check "a quote AND a comma AND a colon together" \
  'type=bind,"source=/Users/t/Both ""q"", and 26:27/courses","target=/teaching/courses"' \
  "$(bind_mount_argument '/Users/t/Both "q", and 26:27/courses' "$TARGET")"

# CSV has no backslash escape, so a trailing backslash passes through as
# itself. Measured against the daemon: it mounts.
check "a trailing backslash is left alone" \
  'type=bind,"source=/Users/t/ends with backslash\","target=/teaching/courses"' \
  "$(bind_mount_argument '/Users/t/ends with backslash\' "$TARGET")"

check "an equals sign, which is a field separator everywhere else" \
  'type=bind,"source=/Users/t/eq=sign 26/courses","target=/teaching/courses"' \
  "$(bind_mount_argument "/Users/t/eq=sign 26/courses" "$TARGET")"

# A folder whose NAME is shaped like the argument itself. Measured: the real
# folder is mounted and /etc is not.
check "a name shaped like the argument cannot add fields to it" \
  'type=bind,"source=/Users/t/type=bind,source=/etc 26/courses","target=/teaching/courses"' \
  "$(bind_mount_argument "/Users/t/type=bind,source=/etc 26/courses" "$TARGET")"

check "the second mount, whose target is a path of its own" \
  'type=bind,"source=/Users/t/Library/Application Support/Plantoir/builds/ab12cd34","target=/Users/t/Library/Application Support/Plantoir/builds/ab12cd34"' \
  "$(bind_mount_argument "/Users/t/Library/Application Support/Plantoir/builds/ab12cd34" \
     "/Users/t/Library/Application Support/Plantoir/builds/ab12cd34")"

# ---- The sentence is the app's sentence -------------------------------
# Never typed here: the words come from the contract, and the app's
# FailureExplainer returns the same ones for the same trouble. A copy typed
# into a test is the copy that keeps passing after the words change.
echo
echo "A teacher who cannot be given a workspace hears what the app would say"
EXPECTED_SENTENCE="$(python3 -c "
import json, sys
rules = json.load(open(sys.argv[1]))
for case in rules['failureExplanations']['cases']:
    if 'bind source path does not exist' in case['output']:
        print(case['expect'])
        break
" "$REPO/contracts/app-rules.json")"
SAID="$(say_this_folder_could_not_be_opened | sed 's/^❌ //' | sed 's/^ *//' | tr '\n' ' ' | sed 's/ *$//')"
if [ -z "$EXPECTED_SENTENCE" ]; then
  fail "the contract explains nothing for a workspace that could not be made"
else
  check "word for word as contracts/app-rules.json has it" "$EXPECTED_SENTENCE" "$SAID"
fi

# Rule 1: the words a teacher reads never name the machinery.
BANNED=""
for word in container Docker docker mount bind daemon volume image; do
  if say_this_folder_could_not_be_opened | grep -qi -- "$word"; then
    BANNED="$BANNED $word"
  fi
done
if [ -z "$BANNED" ]; then
  pass "and says nothing about the machinery"
else
  fail "the sentence names the machinery:$BANNED"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "✅ $CHECKS checks passed."
  exit 0
fi
echo "❌ $FAILURES of $CHECKS checks failed."
exit 1
