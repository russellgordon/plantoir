#!/bin/bash
# Built websites live outside the working folder, and the launchers are what
# put them there for a teacher at the command line and for a publish
# scheduled with launchd — neither of which has an app.
#
# This runs the REAL block out of the three launchers (extracted between the
# BUILD OUTPUT BLOCK markers) against the states an EXISTING teacher's folder
# can be in on the day they upgrade. The states are the point: this piece
# ships to people who already have built sites, published sections, running
# containers and folders synced to a second Mac, and every one of those has
# to survive.
#
# Pure shell, no Docker and no network. Run it directly, or let verify.sh:
#
#     bash scripts/test_build_output_link.sh
#
# The one thing it deliberately does NOT check is the container mount; that
# needs a real container and verify.sh drives it end to end.
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
  awk '/^# >>> BUILD OUTPUT BLOCK >>>/{inside=1} inside{print} /^# <<< BUILD OUTPUT BLOCK <<</{inside=0}' "$1"
}

# ---- The three launchers must carry the SAME block --------------------
echo "The block is the same in all three launchers"
FIRST="$(extract_block "$REPO/setup.sh")"
if [ -z "$FIRST" ]; then
  fail "setup.sh has no BUILD OUTPUT BLOCK markers"
  exit 1
fi
for launcher in preview.sh deploy.sh; do
  if [ "$FIRST" = "$(extract_block "$REPO/$launcher")" ]; then
    pass "$launcher matches setup.sh"
  else
    fail "$launcher's block has drifted from setup.sh's"
  fi
done

# ---- Load it, pointed at a home folder of our own ---------------------
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
HOME="$SANDBOX/home"
mkdir -p "$HOME"
WORKDIR_ID="testfolder"
# shellcheck disable=SC1090
source /dev/stdin <<<"$FIRST"

BUILDS="$HOME/Library/Application Support/Plantoir/builds/$WORKDIR_ID"

# Sets WORKING_FOLDER and moves into it. Not echoed, because $(…) runs in a
# subshell and the `cd` would not survive it — which is exactly the bug the
# first version of this file had.
WORKING_FOLDER=""
new_working_folder() {
  WORKING_FOLDER="$SANDBOX/work-$RANDOM$RANDOM"
  mkdir -p "$WORKING_FOLDER/courses"
  cd "$WORKING_FOLDER" || exit 1
  rm -rf "$BUILDS"
}

make_course_with_a_built_site() {
  mkdir -p "courses/$1/.merged_output/section1/public"
  echo "$2" > "courses/$1/.merged_output/section1/public/index.html"
}

built_page() {
  cat "courses/$1/.merged_output/section1/public/index.html" 2>/dev/null || echo "MISSING"
}

# ---- The teacher upgrading with a built site in the old place ---------
echo
echo "A teacher upgrading with a built website already in their folder"
new_working_folder
make_course_with_a_built_site ICS3U "<html>built last week</html>"
mkdir -p "courses/ICS3U/.netlify_sites"
echo '{"site_id":"abc"}' > "courses/ICS3U/.netlify_sites/section1.json"
link_course_build_output ICS3U >/dev/null

check "the built website still reads at the same path" "<html>built last week</html>" "$(built_page ICS3U)"
if [ -L "courses/ICS3U/.merged_output" ]; then
  pass "what is left in the course folder is a link"
else
  fail "what is left in the course folder is a link"
fi
check "the site marker is untouched — losing it would publish a brand-new site" \
  '{"site_id":"abc"}' "$(cat courses/ICS3U/.netlify_sites/section1.json)"
if [ -z "$(find "courses/ICS3U" -name index.html -type f 2>/dev/null)" ]; then
  pass "the working folder no longer carries the built files"
else
  fail "the working folder no longer carries the built files"
fi

# ---- Running it again -------------------------------------------------
echo
echo "Running it again, as every build and every folder-open does"
echo "keep me" > "$BUILDS/ICS3U/section1/public/extra.html"
link_course_build_output ICS3U >/dev/null
check "nothing is disturbed" "keep me" "$(cat "$BUILDS/ICS3U/section1/public/extra.html" 2>/dev/null)"

# ---- A course folder synced from a second Mac -------------------------
echo
echo "A course folder synced from a second Mac, where the link names another home"
new_working_folder
mkdir -p courses/ICS3U
ln -s "/Users/somebody-else/Library/Application Support/Plantoir/builds/xxxx/ICS3U" \
  "courses/ICS3U/.merged_output"
link_course_build_output ICS3U >/dev/null
check "the link is re-pointed at this Mac's builds folder" \
  "$BUILDS/ICS3U" "$(readlink courses/ICS3U/.merged_output)"
if [ -d "courses/ICS3U/.merged_output" ]; then
  pass "and it resolves to a folder the build can write into"
else
  fail "and it resolves to a folder the build can write into"
fi

# ---- A course restored from a backup ----------------------------------
echo
echo "A course restored from a backup: the link went with the old contents"
new_working_folder
mkdir -p "$BUILDS/ICS3U/section1/public"
echo "<html>last month</html>" > "$BUILDS/ICS3U/section1/public/index.html"
mkdir -p courses/ICS3U
link_course_build_output ICS3U >/dev/null
check "the old build is NOT adopted — it would publish as up to date" \
  "MISSING" "$(built_page ICS3U)"

# ---- A folder nothing may be written into -----------------------------
echo
echo "A folder that cannot be written into falls back to the old behaviour"
new_working_folder
mkdir -p courses/ICS3U
chmod 500 courses/ICS3U
link_course_build_output ICS3U >/dev/null
STATUS=$?
chmod 700 courses/ICS3U
check "the launcher carries on rather than stopping the run" "0" "$STATUS"
if [ ! -e "courses/ICS3U/.merged_output" ]; then
  pass "and leaves the course exactly as it was, for the build to write into"
else
  fail "and leaves the course exactly as it was, for the build to write into"
fi

# ---- The folder marker ------------------------------------------------
echo
echo "The builds folder says which working folder it serves"
new_working_folder
mkdir -p courses/ICS3U
link_course_build_output ICS3U >/dev/null
check "so an abandoned one can be recognised later" \
  "$(pwd -P)" "$(cat "$BUILDS/working-folder.txt" 2>/dev/null)"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "✅ $CHECKS checks passed."
  exit 0
fi
echo "❌ $FAILURES of $CHECKS checks failed."
exit 1
