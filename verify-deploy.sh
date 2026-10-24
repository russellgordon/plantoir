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
#   ./verify-deploy.sh --self-test         # checks this script's own wait for
#                                          # Cloudflare, offline, in ~40 s (#665)
#
# It uses ONE course throughout, on purpose: a Netlify site and a Cloudflare
# project are created once and reused, rather than littering the accounts with
# one per case. The names are printed at the end so they can be deleted.

set -u

SELF_TEST=false
if [ "${1:-}" = "--self-test" ]; then SELF_TEST=true; shift; fi

WORKING_FOLDER="${1:-$HOME/Desktop/plantoir-overnight}"
COURSE="${2:-ADA1O}"
SECTION="${3:-1}"
WORK=/tmp/plantoir-deploy-verify-$$
FOLDER_TARGET="$WORK/published"

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
no()   { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
skip() { echo "  ⏭️  $1"; SKIP=$((SKIP+1)); }
hdr()  { echo; echo "──────── $1"; }

CONFIG="$WORKING_FOLDER/courses/$COURSE/course_config.json"
PUBLIC_DIR="$WORKING_FOLDER/courses/$COURSE/.merged_output/section$SECTION/public"
MEASURED=()

# ------------------------------------- Cloudflare's production address (#665)
# `wrangler pages deploy` returns when the upload is accepted, not when
# <project>.pages.dev serves it. Every Cloudflare leg used to be judged the
# moment the launcher returned, and at Windows' 1.8.5 cut one leg was judged
# against the PREVIOUS deployment: eight checks failed, and two minutes later
# all of them passed. So each leg now waits, for at most CF_WAIT seconds, for
# production to serve what this leg uploaded - and not getting there is a
# FAILURE that says so, after which the run judges what production does serve.
# Never a skip, never an exit.
#
# What "what this leg uploaded" means is the subtle half. The built site holds
# nothing unique per build, so a front page byte for byte equal to the upload
# (Windows' test, kept as half of this one) cannot tell this deployment from
# the last one whenever only the static files or headers moved - which is the
# change this harness exists to catch, and the shape of the 1.8.5 failures.
# So the borrowed page of runnable code carries a mark made fresh for every
# run (RUN_MARK, written into it below), and production must serve BOTH the
# front page and that page byte for byte as uploaded. The previous run's
# deployment cannot carry this run's mark.
#
# The env overrides exist for --self-test, which runs the wait against a stub
# on 127.0.0.1 in seconds; a real run leaves them alone.
CF_POLL="${VERIFY_DEPLOY_CF_POLL:-5}"
CF_WAIT="${VERIFY_DEPLOY_CF_WAIT:-120}"
RUN_MARK="plantoir-verify-deploy-run-$(date -u +%Y%m%dT%H%M%SZ)-$$"

# Called the moment a Cloudflare leg returns, because in a pairing the next
# leg can rebuild the section before production is judged. Keeps a copy of
# what was uploaded, and when the upload returned.
snapshot_cloudflare_upload() {  # snapshot_cloudflare_upload <label> <logfile> <snapshot dir>
  local label="$1" log="$2" dir="$3" built
  rm -rf "$dir"; mkdir -p "$dir"
  date +%s >"$dir/uploaded-at"
  # The log is a terminal transcript, so its lines end in \r\n (measured on
  # a real run's log); without the tr the suffix below never matches.
  built=$(tr -d '\r' <"$log" 2>/dev/null | sed -n 's/^.*Deploying from local build: //p' | tail -1)
  case "$built" in
    */courses/"$COURSE"/.merged_output/section"$SECTION"/public|courses/"$COURSE"/.merged_output/section"$SECTION"/public) ;;
    *) no "$label — the leg did not say it uploaded this section's build, so what production should serve is unknown"
       return 1 ;;
  esac
  if ! cp "$PUBLIC_DIR/index.html" "$dir/front.html" 2>/dev/null \
     || ! cp "$PUBLIC_DIR/Runner-Deploy-Check.html" "$dir/runner.html" 2>/dev/null; then
    no "$label — the uploaded build has no front page or no page of runnable code to compare production with"
    return 1
  fi
  if ! grep -qF -- "$RUN_MARK" "$dir/runner.html"; then
    no "$label — the uploaded page of runnable code does not carry this run's mark, so this deployment could not be told from the last"
    return 1
  fi
  return 0
}

# Polls production's front page and page of runnable code until both are the
# snapshot's bytes. A 404 or no answer is "not yet" (a brand-new project's
# first publish). Fetching the deployment's own <hash>.<project>.pages.dev was
# rejected: Windows measured it resolving LATER than production on a first
# publish, and it is not the address a teacher hands out.
wait_for_cloudflare_production() {  # wait_for_cloudflare_production <label> <production url> <snapshot dir>
  local label="$1" base="${2%/}" dir="$3" start waited since_upload uploaded
  start=$(date +%s)
  uploaded=$(cat "$dir/uploaded-at" 2>/dev/null || echo "$start")
  while :; do
    rm -f "$dir/fetched-front.html" "$dir/fetched-runner.html"
    curl -sL --max-time 20 -H 'Cache-Control: no-cache' -o "$dir/fetched-front.html" "$base/" 2>/dev/null
    curl -sL --max-time 20 -H 'Cache-Control: no-cache' -o "$dir/fetched-runner.html" "$base/Runner-Deploy-Check" 2>/dev/null
    waited=$(( $(date +%s) - start ))
    if cmp -s "$dir/front.html" "$dir/fetched-front.html" && cmp -s "$dir/runner.html" "$dir/fetched-runner.html"; then
      since_upload=$(( $(date +%s) - uploaded ))
      ok "$label — production serves this deployment's front page and page of runnable code (after $waited s)"
      MEASURED+=("$label: production served this deployment after $waited s of waiting, $since_upload s after its upload returned")
      return 0
    fi
    [ "$waited" -ge "$CF_WAIT" ] && break
    sleep "$CF_POLL"
  done
  no "$label — production did not serve this deployment within $CF_WAIT s; judging what it does serve"
  MEASURED+=("$label: production had not switched to this deployment after $CF_WAIT s")
  return 1
}

# ----------------------------------------------------------------- self-test
# The wait above, proved against a stub server on 127.0.0.1 that serves the
# OLD bytes for the first K requests to a path and the NEW after: no
# credentials, no Docker, nothing borrowed from any folder. Runs before the
# trap and the work folder exist, so it touches nothing a real run uses.
run_self_test() {
  local out rc started elapsed n
  ST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/plantoir-deploy-selftest.XXXXXX") || exit 1
  STUB_PID=""
  trap '[ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null; rm -rf "$ST_DIR"' EXIT
  CF_POLL=1; CF_WAIT=8
  COURSE=ADA1O; SECTION=1
  RUN_MARK="plantoir-verify-deploy-run-selftest-$$"
  PUBLIC_DIR="$ST_DIR/folder/courses/ADA1O/.merged_output/section1/public"
  mkdir -p "$ST_DIR/site" "$PUBLIC_DIR"
  printf '<html><body>front page</body></html>\n' >"$ST_DIR/site/old-front.html"
  printf '<html><body>front page, rebuilt</body></html>\n' >"$ST_DIR/site/new-front.html"
  printf '<html><body>runnable code, run plantoir-verify-deploy-run-before</body></html>\n' >"$ST_DIR/site/old-runner.html"
  printf '<html><body>runnable code, run %s</body></html>\n' "$RUN_MARK" >"$ST_DIR/site/new-runner.html"
  mkdir -p "$ST_DIR/snap"
  cp "$ST_DIR/site/new-front.html" "$ST_DIR/snap/front.html"
  cp "$ST_DIR/site/new-runner.html" "$ST_DIR/snap/runner.html"
  cat >"$ST_DIR/stub.py" <<'STUB'
import http.server, os, pathlib, sys
portfile, folder, front_mode, runner_mode = sys.argv[1:5]
folder = pathlib.Path(folder)
routes = {"/": ("front", front_mode), "/Runner-Deploy-Check": ("runner", runner_mode)}
counts = {}
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path not in routes:
            self.send_error(404)
            return
        name, mode = routes[path]
        seen = counts.get(path, 0)
        counts[path] = seen + 1
        kind, _, limit = mode.partition(":")
        status, body = 200, (folder / f"new-{name}.html").read_bytes()
        if kind != "new" and (limit == "inf" or seen < int(limit)):
            if kind == "404":
                status, body = 404, b"not here yet\n"
            else:
                body = (folder / f"old-{name}.html").read_bytes()
        self.send_response(status)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
pathlib.Path(portfile + ".part").write_text(str(server.server_port))
os.replace(portfile + ".part", portfile)
server.serve_forever()
STUB
  st_start() {  # st_start <front mode> <runner mode>: old:K, old:inf, 404:K or new
    rm -f "$ST_DIR/port"
    python3 -I "$ST_DIR/stub.py" "$ST_DIR/port" "$ST_DIR/site" "$1" "$2" &
    STUB_PID=$!
    for _ in $(seq 1 100); do [ -s "$ST_DIR/port" ] && break; sleep 0.1; done
    ST_URL="http://127.0.0.1:$(cat "$ST_DIR/port" 2>/dev/null)"
  }
  st_stop() { [ -n "$STUB_PID" ] && { kill "$STUB_PID" 2>/dev/null; wait "$STUB_PID" 2>/dev/null; }; STUB_PID=""; }
  st_is() {  # st_is <path> <expected file>: does the stub serve that file now?
    curl -s --max-time 5 -o "$ST_DIR/judged.html" "$ST_URL$1" 2>/dev/null
    cmp -s "$ST_DIR/judged.html" "$2"
  }
  after_seconds() { printf '%s\n' "$1" | sed -n 's/.*(after \([0-9][0-9]*\) s).*/\1/p' | head -1; }

  hdr "Self-test — the wait for Cloudflare's production address (#665)"

  st_start old:3 old:3
  st_is / "$ST_DIR/site/old-front.html" \
    && ok "control: fetched at once, the stub serves the OLD front page (the race, reproduced)" \
    || no "control: the stub did not serve the old front page first, so it proves nothing"
  st_stop

  st_start old:3 old:3
  out=$(wait_for_cloudflare_production "case" "$ST_URL" "$ST_DIR/snap"); rc=$?
  n=$(after_seconds "$out")
  if [ "$rc" -eq 0 ] && [ -n "$n" ] && [ "$n" -ge 2 ] \
     && st_is / "$ST_DIR/site/new-front.html" && st_is /Runner-Deploy-Check "$ST_DIR/site/new-runner.html"; then
    ok "production switches after 3 requests: the wait passes (after ${n} s) and what is judged next is the NEW deployment"
  else
    no "production switches after 3 requests: rc $rc, said: ${out:-nothing}"
  fi
  st_stop

  st_start old:inf old:inf
  started=$(date +%s)
  out=$(wait_for_cloudflare_production "case" "$ST_URL" "$ST_DIR/snap"); rc=$?
  elapsed=$(( $(date +%s) - started ))
  n=$(printf '%s\n' "$out" | grep -c '❌')
  if [ "$rc" -ne 0 ] && [ "$n" -eq 1 ] && printf '%s' "$out" | grep -q "within 8 s; judging what it does serve" \
     && [ "$elapsed" -ge 8 ] && [ "$elapsed" -le 15 ]; then
    ok "production never switches: exactly one failure, at the cap (${elapsed} s), and the run goes on"
  else
    no "production never switches: rc $rc, $n failure(s), ${elapsed} s, said: ${out:-nothing}"
  fi
  st_stop

  st_start 404:2 404:2
  out=$(wait_for_cloudflare_production "case" "$ST_URL" "$ST_DIR/snap"); rc=$?
  [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '✅' \
    && ok "a brand-new project answers 404 at first: that is 'not yet', and the wait passes when it answers" \
    || no "a brand-new project answers 404 at first: rc $rc, said: ${out:-nothing}"
  st_stop

  st_start new old:3
  out=$(wait_for_cloudflare_production "case" "$ST_URL" "$ST_DIR/snap"); rc=$?
  n=$(after_seconds "$out")
  if [ "$rc" -eq 0 ] && [ -n "$n" ] && [ "$n" -ge 2 ] && st_is /Runner-Deploy-Check "$ST_DIR/site/new-runner.html"; then
    ok "only the static files moved (same front page): the wait holds until the page of runnable code switches (after ${n} s)"
  else
    no "only the static files moved (same front page): rc $rc, said: ${out:-nothing}"
  fi
  st_stop

  printf 'spawn ./deploy.sh ADA1O 1\r\n Deploying from local build: /teaching/courses/ADA1O/.merged_output/section1/public\r\n Live URL: https://example.pages.dev\r\n' >"$ST_DIR/crlf.log"
  cp "$ST_DIR/site/new-front.html" "$PUBLIC_DIR/index.html"
  cp "$ST_DIR/site/new-runner.html" "$PUBLIC_DIR/Runner-Deploy-Check.html"
  out=$(snapshot_cloudflare_upload "case" "$ST_DIR/crlf.log" "$ST_DIR/snap-crlf"); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] && cmp -s "$ST_DIR/snap-crlf/runner.html" "$PUBLIC_DIR/Runner-Deploy-Check.html" \
    && ok "a terminal transcript's \\r\\n line names this section's build: the upload is kept to compare with" \
    || no "a terminal transcript's \\r\\n line: rc $rc, said: ${out:-nothing}"

  printf ' Deploying from local build: /teaching/courses/ADA1O/.merged_output/section2/public\r\n' >"$ST_DIR/other.log"
  out=$(snapshot_cloudflare_upload "case" "$ST_DIR/other.log" "$ST_DIR/snap-other"); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf '%s\n' "$out" | grep -c '❌')" -eq 1 ] \
    && ok "a leg that uploaded another section's build is one failure, not a wait against the wrong bytes" \
    || no "a leg that uploaded another section's build: rc $rc, said: ${out:-nothing}"

  cp "$ST_DIR/site/old-runner.html" "$PUBLIC_DIR/Runner-Deploy-Check.html"
  out=$(snapshot_cloudflare_upload "case" "$ST_DIR/crlf.log" "$ST_DIR/snap-unmarked"); rc=$?
  [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "does not carry this run's mark" \
    && ok "an upload whose page of runnable code lacks this run's mark is a failure, since the wait could not tell it from the last" \
    || no "an upload without this run's mark: rc $rc, said: ${out:-nothing}"

  hdr "Result"
  echo "  $PASS passed, $FAIL failed, $SKIP skipped"
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
}
if [ "$SELF_TEST" = true ]; then
  run_self_test
fi

mkdir -p "$WORK"

# Everything this script borrows is put back on ANY exit — including Ctrl-C and
# a crash. It moves a section's `index.md` aside to test the refusal, and it
# rewrites the course's destination on every case; without this, an interrupted
# run leaves a course with no front page and pointing at whichever destination
# happened to be last. The default target is a scratch folder, but the working
# folder is an argument, so this could be a real course.
ORIGINAL_CONFIG="$WORK/course_config.original.json"
STASHED_INDEX="$WORK/index.md.stashed"
# A page with runnable code and a formula (#455, #494), borrowed into the
# section so every destination carries the Python engine and the site's own
# KaTeX; removed on any exit.
RUNNER_PAGE="$WORKING_FOLDER/courses/$COURSE/section$SECTION/Runner Deploy Check.md"
restore_what_was_borrowed() {
  if [ -f "$RUNNER_PAGE" ]; then
    rm -f "$RUNNER_PAGE" && echo "  ↩︎  took the borrowed page of runnable code away"
  fi
  if [ -f "$STASHED_INDEX" ]; then
    mv -f "$STASHED_INDEX" "$WORKING_FOLDER/courses/$COURSE/section$SECTION/index.md" 2>/dev/null \
      && echo "  ↩︎  put the section's front page back"
  fi
  if [ -f "$ORIGINAL_CONFIG" ]; then
    cp -f "$ORIGINAL_CONFIG" "$CONFIG" 2>/dev/null \
      && echo "  ↩︎  put the course's destination settings back"
  fi
  pkill -f "preview.sh $COURSE" 2>/dev/null
}
trap restore_what_was_borrowed EXIT INT TERM

# ---------------------------------------------------------------- preflight
hdr "Preflight — refuse clearly rather than half-running"
# The teacher's own folder is never a test folder: this run rewrites its
# recipe, its destinations and its sites.
CANONICAL_FOLDER=$(cd "$WORKING_FOLDER" 2>/dev/null && /bin/pwd -P)
CLASS_WEBSITES=$(cd "$HOME/Desktop/Class Websites" 2>/dev/null && /bin/pwd -P)
if [ -n "$CANONICAL_FOLDER" ] && [ "$CANONICAL_FOLDER" = "$CLASS_WEBSITES" ]; then
  echo "  ❌ $WORKING_FOLDER is the teaching folder (Class Websites); run this against a test folder"
  exit 1
fi
[ -f "$CONFIG" ] || { echo "  ❌ No course at $CONFIG"; exit 1; }
ok "course found: $COURSE section $SECTION in $WORKING_FOLDER"
cp "$CONFIG" "$ORIGINAL_CONFIG"
ok "the course's own settings saved, and restored on any exit"

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

# ------------------------------------- the recipe the launchers run (#665)
# The checks read THIS checkout's contracts/ (check_engine_folder), but the
# launchers run the folder's own .sh files and .toolchain/, which only the app
# refreshes - and the image tag hashes .toolchain/, so a stale mirror is a
# stale IMAGE that looks perfectly healthy. Measured 2026-10-23 on
# ~/Desktop/plantoir-overnight against origin/dev: 27 differences under
# scripts/, 20 under support/, 6 under contracts/, plus .toolchain/Dockerfile,
# .toolchain/preview.sh and the folder's preview.sh. At the 1.8.7 cut it cost
# three failures against a product that was fine.
#
# MIRRORED rather than refused, as Windows does (#630): mirroring is what the
# app does to a folder it touches, and a refusal would only hand the runner
# the remedy every time. From the WORKING TREE, which is what the checks read;
# `git archive HEAD` was rejected because it recreates the mismatch whenever
# the tree has changes. The folder list is READ from contracts/toolchain.json
# -> recipeFolders, never a fifth hand-kept copy. Python's caches are never
# copied: preview.sh's toolchain_hash does not prune __pycache__, so one
# copied cache would be a new image tag. A cache already in the folder is left
# alone (openrsync keeps an excluded file on --delete; measured). -p and -a
# keep modification dates, so the app's size-and-date check finds nothing to
# redo. The mirror STAYS: the folder is a test folder, and the app re-mirrors
# its own bundled copy whenever it next touches it.
REPO="$(cd "$(dirname "$0")" && pwd)"
RECIPE_LAUNCHERS="setup.sh preview.sh deploy.sh"
RECIPE_ROOT_FILES="Dockerfile setup.sh preview.sh deploy.sh setup.bat preview.bat deploy.bat setup.ps1 preview.ps1 deploy.ps1"
RECIPE_FOLDERS=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["recipeFolders"]["folders"]))' "$REPO/contracts/toolchain.json" 2>/dev/null)
recipe_differences() {  # how many places the folder's recipe differs from this checkout's
  local n=0 name folder
  for name in $RECIPE_LAUNCHERS; do cmp -s "$REPO/$name" "$WORKING_FOLDER/$name" || n=$((n+1)); done
  for name in $RECIPE_ROOT_FILES; do cmp -s "$REPO/$name" "$WORKING_FOLDER/.toolchain/$name" || n=$((n+1)); done
  for folder in $RECIPE_FOLDERS; do
    if [ -d "$WORKING_FOLDER/.toolchain/$folder" ]; then
      n=$((n + $(diff -rq --exclude=__pycache__ --exclude=.DS_Store "$REPO/$folder" "$WORKING_FOLDER/.toolchain/$folder" 2>/dev/null | wc -l)))
    else
      n=$((n+1))
    fi
  done
  echo "$n"
}
mirror_recipe() {
  local name folder
  for name in $RECIPE_LAUNCHERS; do
    cmp -s "$REPO/$name" "$WORKING_FOLDER/$name" || cp -p "$REPO/$name" "$WORKING_FOLDER/$name" || return 1
  done
  for name in $RECIPE_ROOT_FILES; do
    cmp -s "$REPO/$name" "$WORKING_FOLDER/.toolchain/$name" || cp -p "$REPO/$name" "$WORKING_FOLDER/.toolchain/$name" || return 1
  done
  for folder in $RECIPE_FOLDERS; do
    mkdir -p "$WORKING_FOLDER/.toolchain/$folder" \
      && rsync -a --delete --exclude=__pycache__ --exclude=.DS_Store "$REPO/$folder/" "$WORKING_FOLDER/.toolchain/$folder/" \
      || return 1
  done
}
if [ -z "$RECIPE_FOLDERS" ]; then
  echo "  ❌ could not read the recipe's folders from $REPO/contracts/toolchain.json"; exit 1
fi
if [ ! -f "$WORKING_FOLDER/preview.sh" ] || [ ! -f "$WORKING_FOLDER/.toolchain/Dockerfile" ]; then
  echo "  ❌ $WORKING_FOLDER has no preview.sh or no .toolchain/Dockerfile, so it is not a working folder to mirror a recipe into"; exit 1
fi
RECIPE_COMMIT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "not a checkout")
RECIPE_DIRTY=$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
RECIPE_CHANGED=$(recipe_differences)
if [ "$RECIPE_CHANGED" -eq 0 ]; then
  ok "the folder already runs this checkout's recipe (launchers and .toolchain, nothing differed)"
else
  mirror_recipe || { echo "  ❌ this checkout's recipe could not be mirrored into $WORKING_FOLDER; refusing to judge it against whatever the folder had"; exit 1; }
  RECIPE_LEFT=$(recipe_differences)
  if [ "$RECIPE_LEFT" -ne 0 ]; then
    echo "  ❌ mirrored this checkout's recipe, but $RECIPE_LEFT difference(s) remain; refusing to run"; exit 1
  fi
  ok "mirrored this checkout's recipe into the folder: $RECIPE_CHANGED difference(s) removed (the mirror stays; the app re-mirrors its own copy when it next touches the folder)"
fi
if pgrep -x Plantoir >/dev/null 2>&1; then
  echo "  ⚠️  Plantoir is running: if it touches this folder during the run it mirrors its OWN copy back, and the Result block will say so"
fi

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
      timeout { puts \"\nTIMED OUT waiting on the launcher\"; catch {close}; exit 124 }
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

# Runnable code (#455) and the site's own KaTeX (#494): every host must send
# the engine's files with types a browser will run - .wasm as
# application/wasm (WebAssembly.instantiateStreaming refuses anything else),
# .mjs and the worker as JavaScript - and any CSP it sends must let wasm
# compile ('unsafe-eval' or 'wasm-unsafe-eval'); KaTeX's stylesheet and a
# face must come back from the site itself, and Netlify's CSP must no longer
# name the CDN. contracts/shared-rules.json -> codeRunnerBlocks.loading.
check_engine() {  # check_engine <label> <site base url ending in />
  local base="$2" name type code headers csp
  for name in pyodide.asm.wasm pyodide.asm.mjs pyodide.mjs plantoir-worker.js python_stdlib.zip pyodide-lock.json; do
    headers=$(curl -s -D - -o /dev/null --max-time 30 "${base}static/pyodide/$name" 2>/dev/null | tr -d '\r')
    code=$(printf '%s\n' "$headers" | awk 'NR==1{print $2}')
    type=$(printf '%s\n' "$headers" | awk 'tolower($1)=="content-type:"{print tolower($2)}' | tail -1 | tr -d ';')
    case "$name" in
      *.wasm) want="application/wasm" ;;
      *.mjs|*.js) want="javascript" ;;
      *) want="" ;;
    esac
    if [ "$code" != "200" ]; then
      no "$1 answered HTTP $code for static/pyodide/$name"
    elif [ -n "$want" ] && ! printf '%s' "$type" | grep -q "$want"; then
      no "$1 sends static/pyodide/$name as '$type', which a browser will not run as $want"
    else
      ok "$1 sends static/pyodide/$name (HTTP 200${type:+, $type})"
    fi
  done
  headers=$(curl -s -D - -o /dev/null --max-time 30 "${base}static/pyodide/plantoir-worker.js" 2>/dev/null | tr -d '\r')
  csp=$(printf '%s\n' "$headers" | awk 'tolower($1)=="content-security-policy:"{ $1=""; print }' | tail -1)
  if [ -z "$csp" ] || printf '%s' "$csp" | grep -Eq "'(unsafe-eval|wasm-unsafe-eval)'"; then
    ok "$1's worker may compile WebAssembly (${csp:+CSP allows it}${csp:-no CSP})"
  else
    no "$1's worker CSP allows no wasm: $csp"
  fi
  # Hosts answer the .html address with a redirect to the pretty one (Netlify
  # 301, Cloudflare 308), so the page is fetched following it.
  code=$(curl -sL -o "$WORK/runner-page.html" -w "%{http_code}" --max-time 30 "${base}Runner-Deploy-Check" 2>/dev/null)
  if [ "$code" = "200" ] && grep -q 'class="plantoir-runner"' "$WORK/runner-page.html"; then
    ok "$1's page of runnable code carries its runnable block"
  else
    no "$1's page of runnable code answered HTTP $code or carries no runnable block"
  fi
  # Runnable Swift (#493): the page's thread and its WASI shim as JavaScript
  # (a module worker refuses anything else), and the block's program. The
  # program is compiled from its bytes, so its type does not decide whether
  # it runs; it is said, not required (review N4).
  for name in plantoir-swift-worker.js plantoir-wasi.mjs; do
    headers=$(curl -s -D - -o /dev/null --max-time 30 "${base}static/swift/$name" 2>/dev/null | tr -d '\r')
    code=$(printf '%s\n' "$headers" | awk 'NR==1{print $2}')
    type=$(printf '%s\n' "$headers" | awk 'tolower($1)=="content-type:"{print tolower($2)}' | tail -1 | tr -d ';')
    if [ "$code" = "200" ] && printf '%s' "$type" | grep -q javascript; then
      ok "$1 sends static/swift/$name (HTTP 200, $type)"
    else
      no "$1 answered HTTP $code, '$type' for static/swift/$name (a module worker needs JavaScript)"
    fi
  done
  local program
  program=$(grep -aoE 'data-runner-wasm="static/swift-wasm/[0-9a-f]{64}\.wasm"' "$WORK/runner-page.html" | head -1 | sed 's/^data-runner-wasm="//; s/"$//')
  if [ -z "$program" ]; then
    no "$1's page of runnable code carries no Swift program"
  else
    headers=$(curl -s -D - -o "$WORK/program.wasm" --max-time 30 "${base}$program" 2>/dev/null | tr -d '\r')
    code=$(printf '%s\n' "$headers" | awk 'NR==1{print $2}')
    type=$(printf '%s\n' "$headers" | awk 'tolower($1)=="content-type:"{print tolower($2)}' | tail -1 | tr -d ';')
    if [ "$code" = "200" ] && [ "$(head -c 4 "$WORK/program.wasm" | od -An -tx1 | tr -d ' \n')" = "0061736d" ]; then
      ok "$1 sends the page's Swift program (HTTP 200, ${type:-no type}, $(wc -c < "$WORK/program.wasm" | tr -d ' ') bytes)"
    else
      no "$1 answered HTTP $code for $program, or not a WebAssembly program"
    fi
  fi
  # Live input (#583): the page of runnable code (it reads input, and shows
  # nothing from another website) is sent the headers that isolate it -
  # following the host's redirect, since Netlify answers the address with
  # capitals with a 301 to its lower-case form - the engine folders carry
  # COEP, and a page with no runnable code carries neither
  # (contracts/shared-rules.json -> codeRunnerBlocks.isolation).
  headers=$(curl -sL -D - -o /dev/null --max-time 30 "${base}Runner-Deploy-Check" 2>/dev/null | tr -d '\r' | awk 'BEGIN{RS=""} {last=$0} END{print last}')
  if printf '%s\n' "$headers" | grep -qi '^cross-origin-opener-policy: same-origin' \
     && printf '%s\n' "$headers" | grep -qi '^cross-origin-embedder-policy: require-corp'; then
    ok "$1 isolates the page of runnable code (COOP same-origin, COEP require-corp), so it asks for input as it runs"
  else
    no "$1 does not send COOP and COEP on the page of runnable code, so it keeps the input box"
  fi
  for name in pyodide/pyodide.mjs pyodide/plantoir-worker.js swift/plantoir-wasi.mjs swift/plantoir-swift-worker.js; do
    headers=$(curl -s -D - -o /dev/null --max-time 30 "${base}static/$name" 2>/dev/null | tr -d '\r')
    if printf '%s\n' "$headers" | grep -qi '^cross-origin-embedder-policy: require-corp'; then
      ok "$1 sends COEP on static/$name"
    else
      no "$1 sends no COEP on static/$name, which an isolated page's worker needs"
    fi
  done
  headers=$(curl -sL -D - -o /dev/null --max-time 30 "${base}" 2>/dev/null | tr -d '\r' | awk 'BEGIN{RS=""} {last=$0} END{print last}')
  if printf '%s\n' "$headers" | grep -qi '^cross-origin-embedder-policy:'; then
    no "$1 sends COEP on the front page, which has no runnable code - its frames would break"
  else
    ok "$1 sends no COEP on the front page, which has no runnable code"
  fi
  headers=$(curl -s -D - -o /dev/null --max-time 30 "${base}static/katex/katex.min.css" 2>/dev/null | tr -d '\r')
  if printf '%s\n' "$headers" | head -1 | grep -q " 200" && printf '%s\n' "$headers" | grep -iq "^content-type: text/css"; then
    ok "$1 serves KaTeX's stylesheet itself (text/css)"
  else
    no "$1 does not serve static/katex/katex.min.css as text/css"
  fi
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "${base}static/katex/fonts/KaTeX_Main-Regular.woff2" 2>/dev/null)
  [ "$code" = "200" ] && ok "$1 serves KaTeX's faces itself" || no "$1 answered HTTP $code for a KaTeX face"
  headers=$(curl -sL -D - -o /dev/null --max-time 30 "${base}Runner-Deploy-Check" 2>/dev/null | tr -d '\r')
  if printf '%s\n' "$headers" | grep -iq "^content-security-policy:.*jsdelivr"; then
    no "$1's CSP still names cdn.jsdelivr.net"
  else
    ok "$1's CSP names no CDN for the maths"
  fi
}

# The pinned engine files, byte for byte, in a folder publish.
check_engine_folder() {  # check_engine_folder <label> <dir>
  local problems
  problems=$(python3 - "$2" "$(cd "$(dirname "$0")" && pwd)/contracts/toolchain.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
site, pins = Path(sys.argv[1]), {p["pin"]: p for p in json.load(open(sys.argv[2]))["pins"]}
problems = []
for name, digest in pins["pyodide"]["files"].items():
    path = site / "static" / "pyodide" / name
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        problems.append(f"static/pyodide/{name}")
for name, digest in pins["katex"]["files"].items():
    path = site / "static" / "katex" / name.replace("dist/", "", 1)
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        problems.append(f"static/katex/{name.replace('dist/', '', 1)}")
if not (site / "static" / "pyodide" / "plantoir-worker.js").is_file():
    problems.append("static/pyodide/plantoir-worker.js")
# Runnable Swift (#493): the overlay as it is in support/gated/swift, and the
# page's compiled program.
overlay = Path(sys.argv[2]).parent.parent / "support" / "gated" / "swift"
for item in sorted(overlay.iterdir()):
    copy = site / "static" / "swift" / item.name
    if not copy.is_file() or copy.read_bytes() != item.read_bytes():
        problems.append(f"static/swift/{item.name}")
programs = sorted((site / "static" / "swift-wasm").glob("*.wasm")) if (site / "static" / "swift-wasm").is_dir() else []
if not programs or any(path.read_bytes()[:4] != b"\0asm" for path in programs):
    problems.append("static/swift-wasm")
print(", ".join(problems))
PY
)
  [ -z "$problems" ] && ok "$1 carries the pinned Python engine, KaTeX and Swift's thread, byte for byte, and the page's Swift program" \
                     || no "$1 lacks or changed: $problems"
}

# Page addresses on Netlify (#628, contracts/shared-rules.json ->
# netlifyPageAddresses). Every same-site <a href> on the front page and the
# borrowed page of runnable code, resolved against the page and asked for
# WITHOUT following a redirect. On Netlify each one must answer 200 and the
# page must wear the marker the publish adds: a 301 to the same path in lower
# case is the rewrite failing. Three other redirects are Quartz's own link
# shapes, not the rewrite, and are counted as their own classes rather than
# failed: `/index` -> `/`, `%2C` -> `,`, and a file link with a trailing slash.
# On Cloudflare Pages (case-sensitive) the links stay in the build's mixed case,
# the page carries no marker, every link answers 200 apart from those classes,
# and one control - a mixed-case page link asked for in lower case - says what
# Cloudflare does with an address it does not hold.
check_page_links() {  # check_page_links <label> <site base url ending in /> <netlify|cloudflare>
  local said status
  said=$(python3 - "$2" "$3" <<'PY'
import html, re, sys, urllib.error, urllib.parse, urllib.request
base, host_kind = sys.argv[1], sys.argv[2]
own = urllib.parse.urlsplit(base).netloc.lower()
class Stay(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None
plain = urllib.request.build_opener(Stay)
def ask(url):
    try:
        response = plain.open(urllib.request.Request(url, headers={"User-Agent": "plantoir-verify-deploy"}), timeout=30)
        return response.status, "", response.read().decode("utf-8", "ignore")
    except urllib.error.HTTPError as error:
        return error.code, error.headers.get("Location") or "", ""
    except Exception as error:
        return 0, str(error), ""
def page(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "plantoir-verify-deploy"}), timeout=30) as response:
        return response.geturl(), response.read().decode("utf-8", "ignore")
problems, notes, links, marked, mixed = [], {}, {}, [], 0
for start in (base, base + ("runner-deploy-check" if host_kind == "netlify" else "Runner-Deploy-Check")):
    try:
        where, text = page(start)
    except Exception as error:
        problems.append(f"could not fetch {start}: {error}")
        continue
    marked.append('data-plantoir-paths="lowercase"' in text)
    for raw in re.findall(r'<a\s[^>]*?href="([^"]*)"', text):
        href = html.unescape(raw).strip()
        if not href or href.startswith(("#", "//")) or (re.match(r"^[A-Za-z][A-Za-z0-9+.\-]*:", href) and not href.lower().startswith(("http://", "https://"))):
            continue
        absolute = urllib.parse.urljoin(where, href)
        parts = urllib.parse.urlsplit(absolute)
        if parts.netloc.lower() != own:
            continue
        # %-escapes' hex digits are not capitals (`%2C`): as test_netlify_paths.path_has_capitals.
        if re.search(r"[A-Z]", re.sub(r"%[0-9A-Fa-f]{2}", "", parts.path)):
            mixed += 1
        links.setdefault(urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path, parts.query, "")), raw)
answered = 0
control = ""
for url, raw in sorted(links.items()):
    status, location, _ = ask(url)
    if status == 200:
        answered += 1
        continue
    path = urllib.parse.urlsplit(url).path
    target = urllib.parse.urlsplit(urllib.parse.urljoin(url, location)).path if location else ""
    if status in (301, 302, 307, 308) and target == path.lower() and path != path.lower():
        problems.append(f"{raw} -> {status} to {target} (the capitals were not taken out)")
    elif status in (301, 302, 307, 308) and path.endswith("/index") and target == path[: -len("index")]:
        notes.setdefault("/index -> /", []).append(raw)
    elif status in (301, 302, 307, 308) and target == path.replace("%2C", ",").replace("%2c", ","):
        notes.setdefault("%2C -> ,", []).append(raw)
    elif status in (301, 302, 307, 308) and path.endswith("/") and target == path.rstrip("/"):
        notes.setdefault("a file link with a trailing slash", []).append(raw)
    else:
        problems.append(f"{raw} -> HTTP {status}{' to ' + target if target else ''}")
if host_kind == "netlify":
    if not all(marked) or not marked:
        problems.append("a page does not carry data-plantoir-paths, which the Netlify publish adds")
    if mixed:
        problems.append(f"{mixed} same-site link(s) still have a capital in their path")
else:
    if any(marked):
        problems.append("a Cloudflare page carries data-plantoir-paths, which only a Netlify publish adds")
    if not mixed:
        problems.append("no link has a capital: Cloudflare was sent the Netlify rewrite")
    for url in sorted(links):
        path = urllib.parse.urlsplit(url).path
        if re.search(r"[A-Z]", path):
            status, location, _ = ask(url.replace(path, path.lower(), 1))
            control = f"{path.lower()} answers {status}{' to ' + location if location else ''}"
            if status == 200:
                problems.append(f"Cloudflare answered 200 for {path.lower()}, so it is not case-sensitive any more and this check's premise has moved")
            break
print(f"SUMMARY {len(links)} same-site links, {answered} answered 200" + "".join(f"; {name}: {len(items)}" for name, items in sorted(notes.items())) + (f"; control: {control}" if control else ""))
for problem in problems:
    print("PROBLEM " + problem)
PY
)
  status=$?
  if [ "$status" -ne 0 ] || [ -z "$said" ]; then
    no "$1's page links could not be checked"
    return
  fi
  if printf '%s\n' "$said" | grep -q '^PROBLEM '; then
    no "$1's page links: $(printf '%s\n' "$said" | sed -n 's/^SUMMARY //p')"
    printf '%s\n' "$said" | sed -n 's/^PROBLEM /       /p'
  else
    ok "$1's page links: $(printf '%s\n' "$said" | sed -n 's/^SUMMARY //p')"
  fi
}

# A folder publish is sent the build's bytes: no marker, links as built.
check_no_marker_folder() {  # check_no_marker_folder <label> <dir>
  if grep -rlq 'data-plantoir-paths' "$2" 2>/dev/null; then
    no "$1 carries data-plantoir-paths, which only a Netlify publish adds (#628)"
  else
    ok "$1 carries the build's links as built, with no Netlify marker (#628)"
  fi
}

# How long a publish takes, and how many bytes it sends: seconds around the
# launcher, and the Obytes delta of the interface the default route uses
# (read on a quiet machine, or it counts everything else too).
NET_IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
obytes() { netstat -ibn 2>/dev/null | awk -v i="$NET_IFACE" '$1==i && $3 ~ /Link/ {print $10; exit}'; }
measure_deploy() {  # measure_deploy <label> <logfile> <args...>
  local label="$1" log="$2"; shift 2
  local before after start finish rc files
  before=$(obytes); start=$(date +%s)
  run_deploy "$log" "$@"; rc=$?
  finish=$(date +%s); after=$(obytes)
  files=$(grep -aoE "Netlify requires [0-9]+ file|Uploaded [0-9]+ files \([0-9]+ already uploaded\)" "$log" | tail -1)
  MEASURED+=("$label: $((finish - start)) s, ${files:-no upload count}, $(( (${after:-0} - ${before:-0}) / 1024 )) KiB sent on ${NET_IFACE:-?}")
  return $rc
}

# ------------------------------------------------------- the preview itself
hdr "Preview — serve mode, which is what a teacher actually uses"
cat > "$RUNNER_PAGE" <<'RUNNERPAGE'
---
title: Runner Deploy Check
codeRunner: true
---
A page of runnable code borrowed by verify-deploy.sh (plantoir-runner-deploy-7f3a), and a formula: $\frac{a}{b} = c^2$.

```python run stdin
name = input("Name? ")
print("Hello,", name)
```

```swift run
print("What is your name?")
let name = readLine() ?? ""
print("Hello, \(name)!")
```
RUNNERPAGE
# This run's mark (#665): what tells this run's Cloudflare deployment from the
# one before it, when nothing else in the built site differs.
printf '\nThis run: %s.\n' "$RUN_MARK" >>"$RUNNER_PAGE"
ok "a page of runnable code borrowed into section $SECTION (removed on any exit)"
# A changed recipe means a new image, and patches that run only when Quartz's
# scaffold is first copied: so the section is rebuilt from scratch, in the
# foreground, BEFORE the serve below starts its ten-minute announce wait (an
# image rebuild alone can take most of that).
if [ "$RECIPE_CHANGED" -ne 0 ]; then
  RECIPE_BUILD_START=$(date +%s)
  if ( cd "$WORKING_FOLDER" && ./preview.sh "$COURSE" "$SECTION" --build-only --full-rebuild >"$WORK/build-recipe.log" 2>&1 ); then
    ok "the recipe changed, so the section was rebuilt from scratch with it ($(( $(date +%s) - RECIPE_BUILD_START )) s)"
  else
    no "the section did not build from scratch with this checkout's recipe (see $WORK/build-recipe.log)"
  fi
  MEASURED+=("Rebuilding from scratch after the recipe changed: $(( $(date +%s) - RECIPE_BUILD_START )) s")
fi
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
  check_engine "the preview" "http://localhost:$PREVIEW_PORT/"
  if grep -q "ws://localhost" "$WORK/preview.html"; then
    ok "the preview carries the live-reload client, as a preview should"
    # The only place anything reads a REAL serve-mode page: the client must
    # still be what contracts/app-rules.json -> buildFreshness.previewBuild
    # looks for (its tag, then its first statement, #291), or every check
    # would read a preview's site as production and publish it. Read as one
    # record in the C locale, exactly as deploy.sh reads it.
    # The working folder's own copy, the one its launchers were given.
    PREVIEW_RULE_FILE="$WORKING_FOLDER/.toolchain/contracts/app-rules.json"
    [ -f "$PREVIEW_RULE_FILE" ] || PREVIEW_RULE_FILE="$(cd "$(dirname "$0")" && pwd)/contracts/app-rules.json"
    PREVIEW_RULE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["buildFreshness"]["previewBuild"]["signature"]["asABasicRegex"], end="")' "$PREVIEW_RULE_FILE" 2>/dev/null)
    if [ -n "$PREVIEW_RULE" ] && LC_ALL=C grep -zq -- "$PREVIEW_RULE" "$WORK/preview.html"; then
      ok "the preview's live-reload client matches the rule in contracts/app-rules.json"
    else
      no "the preview's live-reload client no longer matches the rule in contracts/app-rules.json — re-measure it (#291)"
    fi
  else
    no "the preview has no live-reload client — serve mode may not be running"
  fi
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
# Asserted, not skipped. A preview WAS left serving two lines above, so if
# nothing was stopped the race is back — and a check that can only pass or be
# skipped proves nothing.
grep -aq "Stopped the preview that was still serving this section" "$WORK/deploy-after-preview.log" \
  && ok "the rebuild stopped the preview still serving THIS section, so it could not overwrite" \
  || no "nothing stopped the preview that was still serving — the race is back"
grep -aq "Killed existing process on port" "$WORK/deploy-after-preview.log" \
  && no "a preview was stopped BY PORT, which takes down other sections' previews" \
  || ok "no preview was stopped by port"
check_folder "folder (after a preview)" "$FOLDER_TARGET/section$SECTION"

# ------------------------------------------------------ each destination alone
hdr "Destination 1 of 3 — a folder on this Mac"
rm -rf "$FOLDER_TARGET"; mkdir -p "$FOLDER_TARGET"
set_destination "local_folder" "$FOLDER_TARGET" ""
: >"$WORK/deploy-folder.log"
run_deploy "$WORK/deploy-folder.log" "$COURSE" "$SECTION" --to-folder "$FOLDER_TARGET" \
  && ok "publish to a folder exited 0" || no "publish to a folder failed"
check_folder "folder" "$FOLDER_TARGET/section$SECTION"
check_engine_folder "the folder" "$FOLDER_TARGET/section$SECTION"
check_no_marker_folder "folder" "$FOLDER_TARGET/section$SECTION"

hdr "Destination 2 of 3 — Netlify"
if [ "$HAVE_NETLIFY" = true ]; then
  set_destination "netlify" "" ""
  : >"$WORK/deploy-netlify.log"
  measure_deploy "Netlify, first publish with the engine" "$WORK/deploy-netlify.log" "$COURSE" "$SECTION" \
    && ok "publish to Netlify exited 0" || no "publish to Netlify failed"
  NETLIFY_URL=$(url_from_log "$WORK/deploy-netlify.log")
  [ -n "$NETLIFY_URL" ] && check_url "Netlify" "$NETLIFY_URL" || no "no Netlify address in the output"
  [ -n "$NETLIFY_URL" ] && check_engine "Netlify" "$NETLIFY_URL/"
  [ -n "$NETLIFY_URL" ] && check_page_links "Netlify" "$NETLIFY_URL/" netlify
else
  skip "Netlify (no token)"
fi

hdr "Destination 3 of 3 — Cloudflare Pages"
if [ "$HAVE_CLOUDFLARE" = true ]; then
  set_destination "cloudflare_pages" "" ""
  : >"$WORK/deploy-cloudflare.log"
  measure_deploy "Cloudflare, first publish with the engine" "$WORK/deploy-cloudflare.log" "$COURSE" "$SECTION" --target cloudflare --account "$CF_ACCOUNT" \
    && ok "publish to Cloudflare exited 0" || no "publish to Cloudflare failed"
  snapshot_cloudflare_upload "Cloudflare Pages" "$WORK/deploy-cloudflare.log" "$WORK/cf-alone"; CF_SNAPPED=$?
  CF_URL=$(url_from_log "$WORK/deploy-cloudflare.log")
  [ -n "$CF_URL" ] && [ "$CF_SNAPPED" -eq 0 ] && wait_for_cloudflare_production "Cloudflare Pages" "$CF_URL" "$WORK/cf-alone"
  [ -n "$CF_URL" ] && check_url "Cloudflare Pages" "$CF_URL" || no "no Cloudflare address in the output"
  [ -n "$CF_URL" ] && check_engine "Cloudflare Pages" "$CF_URL/"
  [ -n "$CF_URL" ] && check_page_links "Cloudflare Pages" "$CF_URL/" cloudflare
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
  measure_deploy "Netlify, second publish" "$WORK/pair-nc.log" "$COURSE" "$SECTION" && ok "leg 1 (Netlify) exited 0" || no "leg 1 (Netlify) failed"
  N_URL=$(url_from_log "$WORK/pair-nc.log")
  : >"$WORK/pair-nc2.log"
  measure_deploy "Cloudflare, second publish" "$WORK/pair-nc2.log" "$COURSE" "$SECTION" --target cloudflare --account "$CF_ACCOUNT" \
    && ok "leg 2 (Cloudflare) exited 0" || no "leg 2 (Cloudflare) failed"
  snapshot_cloudflare_upload "Cloudflare (paired with Netlify)" "$WORK/pair-nc2.log" "$WORK/cf-with-netlify"; CF_SNAPPED=$?
  C_URL=$(url_from_log "$WORK/pair-nc2.log")
  [ -n "$C_URL" ] && [ "$CF_SNAPPED" -eq 0 ] && wait_for_cloudflare_production "Cloudflare (paired with Netlify)" "$C_URL" "$WORK/cf-with-netlify"
  [ -n "$N_URL" ] && check_url "Netlify (of the pair)" "$N_URL" || no "no Netlify address"
  [ -n "$C_URL" ] && check_url "Cloudflare (of the pair)" "$C_URL" || no "no Cloudflare address"
  [ -n "$N_URL" ] && check_engine "Netlify (of the pair)" "$N_URL/"
  [ -n "$C_URL" ] && check_engine "Cloudflare (of the pair)" "$C_URL/"
  [ -n "$N_URL" ] && check_page_links "Netlify (of the pair)" "$N_URL/" netlify
  [ -n "$C_URL" ] && check_page_links "Cloudflare (of the pair)" "$C_URL/" cloudflare
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
  [ -n "$N_URL" ] && check_page_links "Netlify (of the pair)" "$N_URL/" netlify
  check_folder "folder (of the pair)" "$FOLDER_TARGET/section$SECTION"
  check_no_marker_folder "folder (of the pair)" "$FOLDER_TARGET/section$SECTION"
  check_engine_folder "the folder (of the pair)" "$FOLDER_TARGET/section$SECTION"
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
  # Kept NOW: the folder leg below can rebuild the section before production
  # is judged.
  snapshot_cloudflare_upload "Cloudflare (paired with a folder)" "$WORK/pair-cf.log" "$WORK/cf-with-folder"; CF_SNAPPED=$?
  C_URL=$(url_from_log "$WORK/pair-cf.log")
  : >"$WORK/pair-cf2.log"
  run_deploy "$WORK/pair-cf2.log" "$COURSE" "$SECTION" --to-folder "$FOLDER_TARGET" \
    && ok "leg 2 (folder) exited 0" || no "leg 2 (folder) failed"
  [ -n "$C_URL" ] && [ "$CF_SNAPPED" -eq 0 ] && wait_for_cloudflare_production "Cloudflare (paired with a folder)" "$C_URL" "$WORK/cf-with-folder"
  [ -n "$C_URL" ] && check_url "Cloudflare (of the pair)" "$C_URL" || no "no Cloudflare address"
  [ -n "$C_URL" ] && check_page_links "Cloudflare (of the pair)" "$C_URL/" cloudflare
  check_folder "folder (of the pair)" "$FOLDER_TARGET/section$SECTION"
  check_engine_folder "the folder (of the pair)" "$FOLDER_TARGET/section$SECTION"
else
  skip "Cloudflare + folder (no credentials)"
fi

# ------------------------------------------ the machinery this branch added
hdr "A section with no front page refuses to publish, and ships nothing stale"
STASH="$STASHED_INDEX"
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

hdr "A course kept for reference is refused by the REAL launcher, at every destination"
# The one thing a unit test cannot prove: that the refusal returns BEFORE any
# network call and before anything reaches a folder. The marker is written by
# hand, the course is put back exactly as it was afterwards, and no site of any
# kind is created — that is the whole point.
#
# --to-folder is the case that matters most: it publishes host-side with rsync
# and exits 0 before the container is ever started, so `deploy.py`'s own
# refusal never runs on that path.
python3 - "$CONFIG" on <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
d["kept_for_reference"] = True
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
rm -rf "$FOLDER_TARGET"; mkdir -p "$FOLDER_TARGET"
for _case in "--to-folder $FOLDER_TARGET" "--target netlify" "--target cloudflare"; do
  : >"$WORK/deploy-reference.log"
  run_deploy "$WORK/deploy-reference.log" "$COURSE" "$SECTION" $_case
  _rc=$?
  [ "$_rc" -eq 1 ] && ok "refused ($_case), exit 1" \
                   || no "exit $_rc for $_case — expected 1"
  grep -aq "is kept for reference, so it is never deployed" "$WORK/deploy-reference.log" \
    && ok "it said why, in the sentence the contract pins ($_case)" \
    || no "the refusal sentence is missing ($_case)"
done
if [ -z "$(find "$FOLDER_TARGET" -type f 2>/dev/null)" ]; then
  ok "nothing reached the folder destination"
else
  no "A REFERENCE COURSE WAS PUBLISHED to the folder destination"
fi
python3 - "$CONFIG" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
d.pop("kept_for_reference", None)
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
grep -q "kept_for_reference" "$CONFIG" \
  && no "the marker was left behind on the scratch course" \
  || ok "the scratch course is back to an ordinary one"

# Asked again at the end: a running app that touches the folder mid-run
# mirrors its own bundled copy back, and then some cases ran another recipe.
hdr "The recipe this run used"
RECIPE_AT_END=$(recipe_differences)
[ "$RECIPE_AT_END" -eq 0 ] \
  && ok "the folder still runs this checkout's recipe at the end of the run" \
  || no "the folder's recipe differs from this checkout's in $RECIPE_AT_END place(s) at the end - something re-mirrored it during the run"

hdr "Result"
echo "  $PASS passed, $FAIL failed, $SKIP skipped"
echo "  recipe: this checkout at $RECIPE_COMMIT$( [ "$RECIPE_DIRTY" -gt 0 ] && echo " with $RECIPE_DIRTY uncommitted change(s)" || echo ", clean"); $RECIPE_CHANGED difference(s) mirrored into the folder"
if [ "${#MEASURED[@]}" -gt 0 ]; then
  echo
  echo "  Publishing a site that carries the Python engine (#455), and Cloudflare's switch to it (#665), measured:"
  for line in "${MEASURED[@]}"; do echo "    $line"; done
fi
echo
echo "  Sites this created (delete them when you are done):"
[ -n "${NETLIFY_URL:-}${N_URL:-}" ] && echo "    Netlify:    ${NETLIFY_URL:-$N_URL}"
[ -n "${CF_URL:-}${C_URL:-}" ]      && echo "    Cloudflare: ${CF_URL:-$C_URL}"
echo "    Folder:     $FOLDER_TARGET"
echo "  Logs: $WORK"
[ "$FAIL" -eq 0 ] || exit 1
