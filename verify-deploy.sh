#!/usr/bin/env bash
#
# verify-deploy.sh — every destination, and every primary+secondary pairing,
# published for real and then fetched back.
#
# WHY THIS IS SEPARATE FROM verify.sh
# ===================================
# `verify.sh` is the gate: it must be runnable at any moment, on any machine,
# without credentials and without touching anything outside this repository.
# This one cannot be. It needs a Netlify token, a Cloudflare token and a
# Cloudflare account ID, it needs the network, and it CREATES REAL SITES on
# real accounts. So it is opt-in, run deliberately, and never wired into the
# gate. Run it when the publishing path changes — and publishing has now
# broken twice in ways nothing else caught.
#
# WHAT IT IS GUARDING AGAINST, SPECIFICALLY
# =========================================
# Both of these shipped, and neither was caught by a unit test or by verify.sh:
#
#   * A preview build reaching a published site. Serve mode bakes a live-reload
#     client into every page; on a published site that script makes a student's
#     browser ask permission to "access other apps and services on this
#     device". `deploy.py` refuses it — but only for Netlify and Cloudflare,
#     because publishing to a FOLDER never enters the container. Measured
#     2026-09-05 at 230 of 244 files.
#   * A publish that reported success and copied NOTHING, because the container
#     writes through a bind mount whose contents the host cannot see yet.
#
# Both are invisible to any check that does not publish and then LOOK at what
# came out. That is this script's whole job: it fetches every published site
# back and reads it.
#
# WHAT IT DOES NOT COVER, AND WHY THAT IS HONEST
# ==============================================
# `additional_deploy_targets` is not handled by `deploy.sh` at all — the APP
# loops over the destinations and calls the launcher once per destination.
# So this script exercises the pairings the way the app does, by running the
# same sequence of launcher calls, which is a real test of the launcher half.
# That the APP produces exactly those argument lists is a separate question,
# already pinned by `contracts/app-rules.json` → `deployArguments` and run by
# both suites. Between the two, the pairing is covered end to end; neither
# half covers it alone, and this comment exists so nobody assumes otherwise.
#
# USAGE
#   ./verify-deploy.sh                     # uses the defaults below
#   ./verify-deploy.sh <folder> <CODE> <N>
#
# It uses ONE course throughout, on purpose: a Netlify site and a Cloudflare
# project are created once and reused, rather than littering the accounts with
# one per case. The names are printed at the end so they can be deleted.

set -u

WORKING_FOLDER="${1:-$HOME/Desktop/plantoir-overnight}"
COURSE="${2:-ADA1O}"
SECTION="${3:-1}"
WORK=/tmp/plantoir-deploy-verify
FOLDER_TARGET="$WORK/published"

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
no()   { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
skip() { echo "  ⏭️  $1"; SKIP=$((SKIP+1)); }
hdr()  { echo; echo "──────── $1"; }

CONFIG="$WORKING_FOLDER/courses/$COURSE/course_config.json"
PUBLIC_DIR="$WORKING_FOLDER/courses/$COURSE/.merged_output/section$SECTION/public"

mkdir -p "$WORK"

# ---------------------------------------------------------------- preflight
hdr "Preflight — refuse clearly rather than half-running"
[ -f "$CONFIG" ] || { echo "  ❌ No course at $CONFIG"; exit 1; }
ok "course found: $COURSE section $SECTION in $WORKING_FOLDER"

HAVE_NETLIFY=false; HAVE_CLOUDFLARE=false
security find-generic-password -s "containerized-quartz-netlify" -w >/dev/null 2>&1 \
  && { HAVE_NETLIFY=true; ok "Netlify token present"; } \
  || skip "no Netlify token — Netlify cases will be skipped, not failed"
if security find-generic-password -s "containerized-quartz-cloudflare" -w >/dev/null 2>&1 \
   && security find-generic-password -s "containerized-quartz-cloudflare-account" -w >/dev/null 2>&1; then
  HAVE_CLOUDFLARE=true; ok "Cloudflare token and account ID present"
else
  skip "no Cloudflare credentials — Cloudflare cases will be skipped, not failed"
fi
CF_ACCOUNT=$(security find-generic-password -s "containerized-quartz-cloudflare-account" -w 2>/dev/null || echo "")

# --------------------------------------------------------------- helpers
# Every deploy is driven through expect, because a first publish to Netlify
# asks for a surname and a site name. Answering by prompt TEXT is what the app
# does; a blind feed of newlines cannot tell one prompt from another and was
# tried first, and failed.
run_deploy() {  # run_deploy <logfile> <args...>
  local log="$1"; shift
  expect -c "
    set timeout 900
    cd {$WORKING_FOLDER}
    log_file -a {$log}
    spawn ./deploy.sh $*
    expect {
      -re {last name.*: }        { send \"Testing\r\"; exp_continue }
      -re {Netlify site name.*]} { send \"\r\"; exp_continue }
      -re {Enter Netlify site name} { send \"\r\"; exp_continue }
      -re {different Netlify site name} { send \"\r\"; exp_continue }
      -re {\\(y/n\\): }          { send \"y\r\"; exp_continue }
      eof {}
    }
    catch wait result
    exit [lindex \$result 3]
  " >>"$log" 2>&1
  return $?
}

set_destination() {  # set_destination <primary> [folderpath] [additional-json]
  python3 - "$CONFIG" "$1" "${2:-}" "${3:-}" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
d["deploy_target"] = sys.argv[2]
if sys.argv[3]:
    d["deploy_folder_path"] = sys.argv[3]
else:
    d.pop("deploy_folder_path", None)
if sys.argv[4]:
    d["additional_deploy_targets"] = json.loads(sys.argv[4])
else:
    d.pop("additional_deploy_targets", None)
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
}

# A published site is only verified by FETCHING IT BACK. Reading the launcher's
# own output would only prove the launcher is happy with itself.
# A brand-new Netlify site does not answer the instant the upload returns —
# measured 2026-09-05: 404 immediately after creation, 200 by the next case a
# minute later. That is the host propagating, not a fault, so this polls rather
# than failing on the first try. It reports how long it waited, because a
# propagation time that starts creeping up is worth seeing.
check_url() {  # check_url <label> <url>
  local code waited=0
  for _ in $(seq 1 40); do
    code=$(curl -s -o "$WORK/fetched.html" -w "%{http_code}" --max-time 20 "$2" 2>/dev/null)
    [ "$code" = "200" ] && break
    sleep 5; waited=$((waited+5))
  done
  if [ "$code" = "200" ]; then
    if [ "$waited" -gt 0 ]; then
      ok "$1 is live and answering after ${waited}s ($2)"
    else
      ok "$1 is live and answering ($2)"
    fi
    if grep -q "ws://localhost" "$WORK/fetched.html"; then
      no "$1 SERVED THE LIVE-RELOAD CLIENT — a preview build reached students"
    else
      ok "$1 carries no live-reload client"
    fi
  else
    no "$1 answered HTTP $code ($2)"
  fi
}

check_folder() {  # check_folder <label> <dir>
  local n
  n=$(find "$2" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ] && [ -f "$2/index.html" ]; then
    ok "$1 received $n files including a front page"
  else
    no "$1 received $n files (front page present: $([ -f "$2/index.html" ] && echo yes || echo no))"
  fi
  if grep -rl "ws://localhost" "$2" >/dev/null 2>&1; then
    no "$1 CONTAINS THE LIVE-RELOAD CLIENT — a preview build was published"
  else
    ok "$1 carries no live-reload client"
  fi
}

url_from_log() {  # url_from_log <logfile>
  grep -aoE "https://[a-zA-Z0-9._-]+\.(netlify\.app|pages\.dev)" "$1" | tail -1
}

# ------------------------------------------------------- the preview itself
hdr "Preview — serve mode, which is what a teacher actually uses"
( cd "$WORKING_FOLDER" && nohup ./preview.sh "$COURSE" "$SECTION" >"$WORK/preview.log" 2>&1 & )
PREVIEW_PORT=""
for _ in $(seq 1 120); do
  PREVIEW_PORT=$(grep -aoE "Preview will be available at: http://localhost:[0-9]+" "$WORK/preview.log" 2>/dev/null | tail -1 | grep -oE "[0-9]+$")
  [ -n "$PREVIEW_PORT" ] && break
  sleep 5
done
if [ -n "$PREVIEW_PORT" ]; then
  for _ in $(seq 1 60); do
    curl -s -o /dev/null --max-time 3 -w "%{http_code}" "http://localhost:$PREVIEW_PORT/" 2>/dev/null | grep -q 200 && break
    sleep 3
  done
  CODE=$(curl -s -o "$WORK/preview.html" -w "%{http_code}" --max-time 10 "http://localhost:$PREVIEW_PORT/" 2>/dev/null)
  [ "$CODE" = "200" ] && ok "preview serves its front page (HTTP 200 on :$PREVIEW_PORT)" \
                      || no "preview answered HTTP $CODE"
  grep -q "ws://localhost" "$WORK/preview.html" \
    && ok "the preview carries the live-reload client, as a preview should" \
    || no "the preview has no live-reload client — serve mode may not be running"
else
  no "the preview never announced an address"
fi
pkill -f "preview.sh $COURSE" 2>/dev/null; sleep 3

# The state this leaves behind is deliberate and is the next test's input, and
# it is a harder state than it looks. `pkill` on the launcher does NOT stop the
# preview: the Python and the node server both live inside the container, and
# the Python's sync watcher goes on mirroring the SERVE build to the host every
# second. So this case exercises two things at once — publishing from a preview
# build, and publishing while a preview is still writing. The second was found
# on 2026-09-05 and was losing the race every time: the rebuild landed and the
# preview overwrote it within a second.
hdr "Publishing straight after a preview must not ship the live-reload client"
if grep -q "ws://localhost" "$PUBLIC_DIR/index.html" 2>/dev/null; then
  ok "the built site is a preview build, which is the state being tested"
else
  skip "the built site is not a preview build; this case is not being exercised"
fi
rm -rf "$FOLDER_TARGET"; mkdir -p "$FOLDER_TARGET"
set_destination "local_folder" "$FOLDER_TARGET" ""
: >"$WORK/deploy-after-preview.log"
run_deploy "$WORK/deploy-after-preview.log" "$COURSE" "$SECTION" --to-folder "$FOLDER_TARGET"
grep -aq "built by a preview" "$WORK/deploy-after-preview.log" \
  && ok "the launcher noticed and rebuilt for publishing" \
  || no "the launcher did not notice it was publishing a preview build"
grep -aq "Killed existing process" "$WORK/deploy-after-preview.log" \
  && ok "the rebuild stopped the preview that was still serving, so it could not overwrite" \
  || skip "no preview was still serving to stop"
check_folder "folder (after a preview)" "$FOLDER_TARGET/section$SECTION"

# ------------------------------------------------------ each destination alone
hdr "Destination 1 of 3 — a folder on this Mac"
rm -rf "$FOLDER_TARGET"; mkdir -p "$FOLDER_TARGET"
set_destination "local_folder" "$FOLDER_TARGET" ""
: >"$WORK/deploy-folder.log"
run_deploy "$WORK/deploy-folder.log" "$COURSE" "$SECTION" --to-folder "$FOLDER_TARGET" \
  && ok "publish to a folder exited 0" || no "publish to a folder failed"
check_folder "folder" "$FOLDER_TARGET/section$SECTION"

hdr "Destination 2 of 3 — Netlify"
if [ "$HAVE_NETLIFY" = true ]; then
  set_destination "netlify" "" ""
  : >"$WORK/deploy-netlify.log"
  run_deploy "$WORK/deploy-netlify.log" "$COURSE" "$SECTION" \
    && ok "publish to Netlify exited 0" || no "publish to Netlify failed"
  NETLIFY_URL=$(url_from_log "$WORK/deploy-netlify.log")
  [ -n "$NETLIFY_URL" ] && check_url "Netlify" "$NETLIFY_URL" || no "no Netlify address in the output"
else
  skip "Netlify (no token)"
fi

hdr "Destination 3 of 3 — Cloudflare Pages"
if [ "$HAVE_CLOUDFLARE" = true ]; then
  set_destination "cloudflare_pages" "" ""
  : >"$WORK/deploy-cloudflare.log"
  run_deploy "$WORK/deploy-cloudflare.log" "$COURSE" "$SECTION" --target cloudflare --account "$CF_ACCOUNT" \
    && ok "publish to Cloudflare exited 0" || no "publish to Cloudflare failed"
  CF_URL=$(url_from_log "$WORK/deploy-cloudflare.log")
  [ -n "$CF_URL" ] && check_url "Cloudflare Pages" "$CF_URL" || no "no Cloudflare address in the output"
else
  skip "Cloudflare (no credentials)"
fi

# --------------------------------------------------------- the three pairings
# Run as the app runs them: the primary first, then each additional, one
# launcher call apiece. Both destinations are then fetched back — a pairing
# where the second leg silently did nothing is the failure worth catching.
hdr "Pairing 1 of 3 — Netlify primary, Cloudflare also"
if [ "$HAVE_NETLIFY" = true ] && [ "$HAVE_CLOUDFLARE" = true ]; then
  set_destination "netlify" "" '[{"type":"cloudflare_pages"}]'
  : >"$WORK/pair-nc.log"
  run_deploy "$WORK/pair-nc.log" "$COURSE" "$SECTION" && ok "leg 1 (Netlify) exited 0" || no "leg 1 (Netlify) failed"
  N_URL=$(url_from_log "$WORK/pair-nc.log")
  : >"$WORK/pair-nc2.log"
  run_deploy "$WORK/pair-nc2.log" "$COURSE" "$SECTION" --target cloudflare --account "$CF_ACCOUNT" \
    && ok "leg 2 (Cloudflare) exited 0" || no "leg 2 (Cloudflare) failed"
  C_URL=$(url_from_log "$WORK/pair-nc2.log")
  [ -n "$N_URL" ] && check_url "Netlify (of the pair)" "$N_URL" || no "no Netlify address"
  [ -n "$C_URL" ] && check_url "Cloudflare (of the pair)" "$C_URL" || no "no Cloudflare address"
else
  skip "Netlify + Cloudflare (credentials missing)"
fi

hdr "Pairing 2 of 3 — Netlify primary, a folder also"
if [ "$HAVE_NETLIFY" = true ]; then
  rm -rf "$FOLDER_TARGET"; mkdir -p "$FOLDER_TARGET"
  set_destination "netlify" "$FOLDER_TARGET" "[{\"type\":\"local_folder\",\"path\":\"$FOLDER_TARGET\"}]"
  : >"$WORK/pair-nf.log"
  run_deploy "$WORK/pair-nf.log" "$COURSE" "$SECTION" && ok "leg 1 (Netlify) exited 0" || no "leg 1 (Netlify) failed"
  N_URL=$(url_from_log "$WORK/pair-nf.log")
  : >"$WORK/pair-nf2.log"
  run_deploy "$WORK/pair-nf2.log" "$COURSE" "$SECTION" --to-folder "$FOLDER_TARGET" \
    && ok "leg 2 (folder) exited 0" || no "leg 2 (folder) failed"
  [ -n "$N_URL" ] && check_url "Netlify (of the pair)" "$N_URL" || no "no Netlify address"
  check_folder "folder (of the pair)" "$FOLDER_TARGET/section$SECTION"
else
  skip "Netlify + folder (no Netlify token)"
fi

hdr "Pairing 3 of 3 — Cloudflare primary, a folder also"
if [ "$HAVE_CLOUDFLARE" = true ]; then
  rm -rf "$FOLDER_TARGET"; mkdir -p "$FOLDER_TARGET"
  set_destination "cloudflare_pages" "$FOLDER_TARGET" "[{\"type\":\"local_folder\",\"path\":\"$FOLDER_TARGET\"}]"
  : >"$WORK/pair-cf.log"
  run_deploy "$WORK/pair-cf.log" "$COURSE" "$SECTION" --target cloudflare --account "$CF_ACCOUNT" \
    && ok "leg 1 (Cloudflare) exited 0" || no "leg 1 (Cloudflare) failed"
  C_URL=$(url_from_log "$WORK/pair-cf.log")
  : >"$WORK/pair-cf2.log"
  run_deploy "$WORK/pair-cf2.log" "$COURSE" "$SECTION" --to-folder "$FOLDER_TARGET" \
    && ok "leg 2 (folder) exited 0" || no "leg 2 (folder) failed"
  [ -n "$C_URL" ] && check_url "Cloudflare (of the pair)" "$C_URL" || no "no Cloudflare address"
  check_folder "folder (of the pair)" "$FOLDER_TARGET/section$SECTION"
else
  skip "Cloudflare + folder (no credentials)"
fi

# ------------------------------------------ the machinery this branch added
hdr "A section with no front page refuses to publish, and ships nothing stale"
STASH="$WORK/index.md.stashed"
if [ -f "$WORKING_FOLDER/courses/$COURSE/section$SECTION/index.md" ]; then
  MARK="verify-deploy-$(date +%s)"
  echo "<!-- $MARK -->" >> "$PUBLIC_DIR/index.html" 2>/dev/null
  mv "$WORKING_FOLDER/courses/$COURSE/section$SECTION/index.md" "$STASH"
  ( cd "$WORKING_FOLDER" && ./preview.sh "$COURSE" "$SECTION" --build-only >"$WORK/build-nofront.log" 2>&1 )
  BUILD_RC=$?
  [ "$BUILD_RC" -ne 0 ] && ok "the build failed rather than claiming success" \
                        || no "the build exited 0 with no front page"
  grep -aq "no front page, so no website was produced" "$WORK/build-nofront.log" \
    && ok "it said why, in the words the failure explainer matches" \
    || no "the reason sentence is missing"
  [ -d "$PUBLIC_DIR" ] && no "the previous build's site is still there — a publish would ship it" \
                       || ok "the previous build's site was cleared"
  rm -rf "$FOLDER_TARGET"; mkdir -p "$FOLDER_TARGET"
  : >"$WORK/deploy-nofront.log"
  run_deploy "$WORK/deploy-nofront.log" "$COURSE" "$SECTION" --to-folder "$FOLDER_TARGET"
  if grep -rq "$MARK" "$FOLDER_TARGET" 2>/dev/null; then
    no "THE STALE SITE WAS PUBLISHED"
  else
    ok "no stale page reached the destination"
  fi
  mv "$STASH" "$WORKING_FOLDER/courses/$COURSE/section$SECTION/index.md"
  ( cd "$WORKING_FOLDER" && ./preview.sh "$COURSE" "$SECTION" --build-only >"$WORK/build-restored.log" 2>&1 ) \
    && ok "restoring the front page makes it publishable again" \
    || no "still not publishable after restoring the front page"
else
  skip "no section index.md to remove"
fi

hdr "Result"
echo "  $PASS passed, $FAIL failed, $SKIP skipped"
echo
echo "  Sites this created (delete them when you are done):"
[ -n "${NETLIFY_URL:-}${N_URL:-}" ] && echo "    Netlify:    ${NETLIFY_URL:-$N_URL}"
[ -n "${CF_URL:-}${C_URL:-}" ]      && echo "    Cloudflare: ${CF_URL:-$C_URL}"
echo "    Folder:     $FOLDER_TARGET"
echo "  Logs: $WORK"
[ "$FAIL" -eq 0 ] || exit 1
