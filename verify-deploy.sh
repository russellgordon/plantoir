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
# The APP loops over a course's destinations and calls the launcher once per
# destination, naming each one — `--target netlify` included since #668,
# because a `deploy.sh` given NO destination now reads the course's saved
# destinations itself and runs every one of them (Russell, 2026-11-01). Every
# call here names its destination for the same reason, so a Netlify leg of a
# pairing never runs the pairing's other leg as well.
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
#                                          # Cloudflare (#665) and its retry of a
#                                          # new site's files (#740) and pages
#                                          # (#869), offline, ~75 s
#   ./verify-deploy.sh --first-publish [<folder> <CODE> <N>]
#                                          # publishes as a NEW teacher would:
#                                          # new sites, both questions asked (#712)
#
# It uses ONE course throughout, on purpose: a Netlify site and a Cloudflare
# project are created once and reused, rather than littering the accounts with
# one per case. The names are printed at the end so they can be deleted.
#
# --first-publish (#712, the mac's copy of Windows' -FirstPublish, #123/#623)
# moves aside what makes a publish a REPEAT one - the saved surname (and its
# pre-.internal location), the section's Netlify record (and its legacy
# per-section one) and its Cloudflare record - and answers the surname
# question with "Testing" plus six random letters, so deploy.py names, and
# creates, a Netlify site and a Cloudflare project nobody has ever uploaded
# to. A random surname alone changes nothing while the records are there:
# deploy.py reuses a recorded site and never asks (#699's plan review, B1).
# Everything moved aside is put back on every exit - Ctrl-C or a TERM ends
# the run there (130/143) rather than letting it publish on - and a run killed
# outright is put right by the next run's preflight, against the surname that
# run wrote into its sentinel. The two sites it made are DELETED
# at the end of the run, through the hosts' own APIs, and the Result block
# names them either way, so nothing is left on the accounts unannounced.

set -u

SELF_TEST=false
FIRST_PUBLISH=false
while :; do
  case "${1:-}" in
    --self-test)     SELF_TEST=true; shift ;;
    --first-publish) FIRST_PUBLISH=true; shift ;;
    *) break ;;
  esac
done

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
      MEASURED+=("$label: production matched the upload after $waited s of waiting, $since_upload s after its upload returned (a wait of 0 s on a later leg means the same bytes were already live, not a fast switch)")
      return 0
    fi
    [ "$waited" -ge "$CF_WAIT" ] && break
    sleep "$CF_POLL"
  done
  no "$label — production did not serve this deployment within $CF_WAIT s; judging what it does serve"
  MEASURED+=("$label: production had not switched to this deployment after $CF_WAIT s")
  return 1
}

# A FIRST publish asks for an address that did not exist a few seconds
# earlier (#712). Measured 2026-10-31 on the first --first-publish run: the
# moment the first Cloudflare upload returned, the wait above asked this
# Mac's resolver for the new <project>.pages.dev, got NODATA under the
# project's own zone, and the resolver kept that answer for the zone's
# negative TTL - 1800 s - so every Cloudflare check read HTTP 000 for half an
# hour while 1.1.1.1, 8.8.8.8 and the router all answered with Cloudflare's
# addresses. (*.netlify.app answers for any name, so Netlify never showed
# it.) So before anything on this Mac looks a NEW site up, this waits for a
# public resolver to answer for it, and only then lets curl and Python ask
# the system's; the wait is reported, never hidden. A plain run publishes to
# sites that already exist and returns at once.
wait_for_new_address() {  # wait_for_new_address <label> <url>
  local label="$1" host start waited
  [ "$FIRST_PUBLISH" = true ] || return 0
  host="${2#*://}"; host="${host%%/*}"
  start=$(date +%s)
  while :; do
    waited=$(( $(date +%s) - start ))
    if dig +short +time=3 +tries=1 @1.1.1.1 "$host" A 2>/dev/null | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      MEASURED+=("$label: the new address $host answered at 1.1.1.1 after $waited s, before anything here looked it up")
      return 0
    fi
    [ "$waited" -ge "$CF_WAIT" ] && break
    sleep "$CF_POLL"
  done
  no "$label — the new address $host had no answer at 1.1.1.1 after $CF_WAIT s"
  return 1
}

# ------------------------------- a brand-new site's files, retried (#740)
# On a site this run has just CREATED, Netlify's edges are not yet of one
# mind. Measured at the v1.9.1 gate (2026-11-01, dev e7a73e082, M4 Pro, home
# network): two consecutive --first-publish runs went red on the NEW Netlify
# site only - run 1 a 404 for static/pyodide/pyodide.mjs and no COEP on
# static/swift/plantoir-swift-worker.js, run 2 a 404 ('text/plain') for the
# swift worker while pyodide.mjs and its COEP passed - a different file each
# time, never on Cloudflare, and a watcher fetching both files every 5 s from
# the moment the site was live got 24 of 24 HTTP 200 with the right type and
# COEP in the same minute. The plain run against the long-lived sites was
# 174/0/0. So on a FIRST publish (and only there: a plain run's sites are old,
# and a wrong answer from them is a fault) a per-file fetch-back that does not
# get the answer its check wants is asked again every NS_POLL s for at most
# NS_WAIT s, each retry is written down and counted in the Result block, and
# an answer that never comes is still the check's failure, judged on the last
# answer. Rejected: a fixed sleep after creating the site (a guessed duration
# for a race, and the edges disagree file by file, so "long enough" for one
# file says nothing about the next); retrying on a plain run too (it would
# hide a real 404 on a site that has existed for weeks).
#
# Pages too, since #869. Measured at #835 part 2's gate (2026-11-13, two
# --first-publish runs): the borrowed page of runnable code, fetched once
# with no second asking, answered Netlify's new site HTTP 404 in run 1 and
# Cloudflare's new project HTTP 522 in run 2, a different host each time,
# seconds after the site went live, and failed two checks each time ("carries
# no runnable block" and "carries no Swift program", which reads the same
# fetched page). The same page passed on the next leg of the same run, and in
# run 2 a file one line earlier got #740's retry and passed. So every fetch
# of a brand-new site that judged it on one answer now goes through this
# helper: the page of runnable code (wanting its runnable block), the same
# page's isolation headers, the front page's headers and the page's CSP (the
# last two are checks for an ABSENT header, which a 404 or a 522 used to pass
# without the page ever being read), and in check_page_links the two pages it
# starts from and every link it asks for. check_url and the waits above
# already ask again on their own, in every run.
NS_POLL="${VERIFY_DEPLOY_NS_POLL:-5}"
NS_WAIT="${VERIFY_DEPLOY_NS_WAIT:-60}"
# One deadline for a whole check_engine or check_page_links call as well
# (#869 review): once it has passed, a fetch that does not settle is asked
# once and judged, so a genuinely broken new site fails in at most about
# NS_CALL_WAIT s a call plus one answer per remaining fetch, rather than
# NS_WAIT for every fetch (18 broken links would have been 18 minutes).
NS_CALL_WAIT="${VERIFY_DEPLOY_NS_CALL_WAIT:-180}"
NS_CALL_DEADLINE=""

# The last block of `curl -L -D -`'s headers: the answer the redirects led to.
last_header_block() {
  awk 'BEGIN{RS=""} {last=$0} END{print last}'
}

# fetch_headers <want> <url> [-o <file>]
# Prints the response headers (\r stripped), as `curl -s -D -` did. Wants
# that do not follow a redirect: "200" wants HTTP 200; "coep" wants HTTP 200
# and COEP require-corp. Wants that follow redirects (#869), and print every
# block as `curl -sL -D -` did: "page" wants the final answer HTTP 200;
# "runner" wants that and the body (-o) carrying the runnable block;
# "isolated" wants that and COOP same-origin with COEP require-corp.
fetch_headers() {
  local want="$1" url="$2" out="/dev/null" headers final code start deadline waited tries=0 good follow=""
  [ "${3:-}" = "-o" ] && out="$4"
  case "$want" in page|runner|isolated) follow="-L" ;; esac
  # A deadline fixed once, not a count of polls: how many retries fit before
  # it depends on how long each answer takes, so nothing may pin that number
  # (the self-test asserts a range).
  start=$(date +%s)
  deadline=$(( start + NS_WAIT ))
  if [ -n "$NS_CALL_DEADLINE" ] && [ "$NS_CALL_DEADLINE" -lt "$deadline" ]; then
    deadline=$NS_CALL_DEADLINE
  fi
  while :; do
    headers=$(curl -s $follow -D - -o "$out" --max-time 30 "$url" 2>/dev/null | tr -d '\r')
    final=$(printf '%s\n' "$headers" | last_header_block)
    code=$(printf '%s\n' "$final" | awk 'NR==1{print $2}')
    good=false
    if [ "$code" = "200" ]; then
      case "$want" in
        coep|isolated)
          printf '%s\n' "$final" | grep -qi '^cross-origin-embedder-policy: require-corp' && good=true
          if [ "$want" = isolated ] && ! printf '%s\n' "$final" | grep -qi '^cross-origin-opener-policy: same-origin'; then
            good=false
          fi ;;
        runner) grep -q 'class="plantoir-runner"' "$out" 2>/dev/null && good=true ;;
        *) good=true ;;
      esac
    fi
    waited=$(( $(date +%s) - start ))
    [ "$good" = true ] && break
    [ "$FIRST_PUBLISH" = true ] || break
    case "$url" in http://localhost:*) break ;; esac  # the preview is no new site
    [ "$(date +%s)" -ge "$deadline" ] && break
    tries=$((tries+1))
    sleep "$NS_POLL"
  done
  if [ "$tries" -gt 0 ]; then
    echo "  ↻ a brand-new site: $url needed $tries retr$([ "$tries" -eq 1 ] && echo y || echo ies) over $waited s ($([ "$good" = true ] && echo "then answered" || echo "never answered as wanted"))" >&2
    printf '%s\t%s\t%s\t%s\n' "$url" "$tries" "$waited" "$good" >>"${NS_RETRY_LOG:-$WORK/new-site-retries.tsv}"
  fi
  printf '%s\n' "$headers"
}

# One line per site for the Result block: how many of its files (and, since
# #869, its pages) a brand-new site needed asking again, and the most it took.
measure_new_site_retries() {  # measure_new_site_retries <label> <base url ending in /> [what] [counted, one, none]
  local log="${NS_RETRY_LOG:-$WORK/new-site-retries.tsv}" line
  [ "$FIRST_PUBLISH" = true ] || return 0
  case "$2" in http://localhost:*) return 0 ;; esac
  local what="${3:-}" counted="${4:-file(s)}" one="${5:-one file}" none="${6:-no file}"
  [ -n "$what" ] || what="a brand-new site's files and pages (#740, #869)"
  line=$(awk -F '\t' -v b="$2" -v counted="$counted" -v one="$one" -v none="$none" 'index($1, b) == 1 { n++; t += $2; if ($2 > m) m = $2; if ($3 > w) w = $3 }
    END { if (n == 0) print none " needed asking again"; else printf "%d %s needed asking again, %d retries in all, at most %d for %s, the longest %d s", n, counted, t, m, one, w }' "$log" 2>/dev/null)
  MEASURED+=("$1, $what: ${line:-$none needed asking again}")
}

# ------------------------------- what a published site is checked for
# check_engine and check_page_links are defined here, ahead of the self-test,
# so the self-test runs the real checks against a stub site (#869).

# Runnable code (#455) and the site's own KaTeX (#494): every host must send
# the engine's files with types a browser will run - .wasm as
# application/wasm (WebAssembly.instantiateStreaming refuses anything else),
# .mjs and the worker as JavaScript - and any CSP it sends must let wasm
# compile ('unsafe-eval' or 'wasm-unsafe-eval'); KaTeX's stylesheet and a
# face must come back from the site itself, and Netlify's CSP must no longer
# name the CDN. contracts/shared-rules.json -> codeRunnerBlocks.loading.
check_engine() {  # check_engine <label> <site base url ending in />
  # Each call keeps its own retry log, so a pairing leg that checks a site
  # an earlier leg already checked counts only its own retries (#740 review).
  NS_LEG=$(( ${NS_LEG:-0} + 1 ))
  NS_RETRY_LOG="$WORK/new-site-retries-$NS_LEG.tsv"
  : >"$NS_RETRY_LOG"
  NS_CALL_DEADLINE=$(( $(date +%s) + NS_CALL_WAIT ))
  local base="$2" name type code headers csp
  for name in pyodide.asm.wasm pyodide.asm.mjs pyodide.mjs plantoir-worker.js python_stdlib.zip pyodide-lock.json; do
    headers=$(fetch_headers 200 "${base}static/pyodide/$name")
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
  headers=$(fetch_headers 200 "${base}static/pyodide/plantoir-worker.js")
  csp=$(printf '%s\n' "$headers" | awk 'tolower($1)=="content-security-policy:"{ $1=""; print }' | tail -1)
  if [ -z "$csp" ] || printf '%s' "$csp" | grep -Eq "'(unsafe-eval|wasm-unsafe-eval)'"; then
    ok "$1's worker may compile WebAssembly (${csp:+CSP allows it}${csp:-no CSP})"
  else
    no "$1's worker CSP allows no wasm: $csp"
  fi
  # Hosts answer the .html address with a redirect to the pretty one (Netlify
  # 301, Cloudflare 308), so the page is fetched following it.
  # A brand-new site's page is asked again like its files (#869).
  code=$(fetch_headers runner "${base}Runner-Deploy-Check" -o "$WORK/runner-page.html" | last_header_block | awk 'NR==1{print $2}')
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
    headers=$(fetch_headers 200 "${base}static/swift/$name")
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
    headers=$(fetch_headers 200 "${base}$program" -o "$WORK/program.wasm")
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
  headers=$(fetch_headers isolated "${base}Runner-Deploy-Check" | last_header_block)
  if printf '%s\n' "$headers" | grep -qi '^cross-origin-opener-policy: same-origin' \
     && printf '%s\n' "$headers" | grep -qi '^cross-origin-embedder-policy: require-corp'; then
    ok "$1 isolates the page of runnable code (COOP same-origin, COEP require-corp), so it asks for input as it runs"
  else
    no "$1 does not send COOP and COEP on the page of runnable code, so it keeps the input box"
  fi
  for name in pyodide/pyodide.mjs pyodide/plantoir-worker.js swift/plantoir-wasi.mjs swift/plantoir-swift-worker.js; do
    headers=$(fetch_headers coep "${base}static/$name")
    if printf '%s\n' "$headers" | grep -qi '^cross-origin-embedder-policy: require-corp'; then
      ok "$1 sends COEP on static/$name"
    else
      no "$1 sends no COEP on static/$name, which an isolated page's worker needs"
    fi
  done
  # The two checks for an ABSENT header pass only on a real answer (#869
  # review): a page that never came is a failure, not a pass.
  headers=$(fetch_headers page "${base}" | last_header_block)
  code=$(printf '%s\n' "$headers" | awk 'NR==1{print $2}')
  if [ "$code" != "200" ]; then
    no "$1's front page answered HTTP ${code:-000}, so whether it sends COEP could not be judged"
  elif printf '%s\n' "$headers" | grep -qi '^cross-origin-embedder-policy:'; then
    no "$1 sends COEP on the front page, which has no runnable code - its frames would break"
  else
    ok "$1 sends no COEP on the front page, which has no runnable code"
  fi
  headers=$(fetch_headers 200 "${base}static/katex/katex.min.css")
  if printf '%s\n' "$headers" | head -1 | grep -q " 200" && printf '%s\n' "$headers" | grep -iq "^content-type: text/css"; then
    ok "$1 serves KaTeX's stylesheet itself (text/css)"
  else
    no "$1 does not serve static/katex/katex.min.css as text/css"
  fi
  code=$(fetch_headers 200 "${base}static/katex/fonts/KaTeX_Main-Regular.woff2" | awk 'NR==1{print $2}')
  [ "$code" = "200" ] && ok "$1 serves KaTeX's faces itself" || no "$1 answered HTTP $code for a KaTeX face"
  headers=$(fetch_headers page "${base}Runner-Deploy-Check")
  code=$(printf '%s\n' "$headers" | last_header_block | awk 'NR==1{print $2}')
  if [ "$code" != "200" ]; then
    no "$1's page of runnable code answered HTTP ${code:-000}, so whether its CSP names a CDN could not be judged"
  elif printf '%s\n' "$headers" | grep -iq "^content-security-policy:.*jsdelivr"; then
    no "$1's CSP still names cdn.jsdelivr.net"
  else
    ok "$1's CSP names no CDN for the maths"
  fi
  NS_CALL_DEADLINE=""
  measure_new_site_retries "$1" "$base"
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
  # Its own retry log, counted in the Result block like check_engine's (#869).
  NS_LEG=$(( ${NS_LEG:-0} + 1 ))
  NS_RETRY_LOG="$WORK/new-site-retries-$NS_LEG.tsv"
  : >"$NS_RETRY_LOG"
  said=$(python3 - "$2" "$3" "$FIRST_PUBLISH" "$NS_POLL" "$NS_WAIT" "$NS_RETRY_LOG" "$NS_CALL_WAIT" <<'PY'
import html, re, sys, time, urllib.error, urllib.parse, urllib.request
base, host_kind = sys.argv[1], sys.argv[2]
# The five after them are optional, because Windows' verify-deploy.ps1 runs
# this same program read out of this file and passes the first two only
# (Get-PageLinksProgram): without them nothing is asked again, as before #869.
extra = sys.argv[3:8] if len(sys.argv) >= 8 else ["false", "5", "60", "", "180"]
first_publish, ns_poll, ns_wait, retry_log = extra[0] == "true", float(extra[1]), float(extra[2]), extra[3]
# One deadline for the whole call, as check_engine's NS_CALL_WAIT.
call_deadline = time.time() + float(extra[4])
own = urllib.parse.urlsplit(base).netloc.lower()
def asked_again(url, attempt, settled):
    # fetch_headers' rule (#740, #869), for the fetches made here: on a first
    # publish only, an answer that is not settled is asked again every NS_POLL
    # s until NS_WAIT s have passed, each retry written down and counted, and
    # the last answer is what is judged.
    start = time.time()
    tries = 0
    while True:
        answer = attempt(url)
        good = settled(answer)
        if good or not first_publish or url.startswith("http://localhost:") or time.time() >= min(start + ns_wait, call_deadline):
            break
        tries += 1
        time.sleep(ns_poll)
    if tries:
        waited = int(time.time() - start)
        print(f"  ↻ a brand-new site: {url} needed {tries} retr{'y' if tries == 1 else 'ies'} over {waited} s ({'then answered' if good else 'never answered as wanted'})", file=sys.stderr)
        with open(retry_log, "a", encoding="utf-8") as log:
            log.write(f"{url}\t{tries}\t{waited}\t{'true' if good else 'false'}\n")
    return answer
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
def page_or_error(url):
    try:
        return page(url)
    except Exception as error:
        return error
def link_has_settled(answer):
    # 200, or a redirect, which the checks below judge by class; a 404, a 5xx
    # or no answer is a brand-new site's "not yet".
    return answer[0] == 200 or answer[0] in (301, 302, 307, 308)
problems, notes, links, marked, mixed = [], {}, {}, [], 0
for start in (base, base + ("runner-deploy-check" if host_kind == "netlify" else "Runner-Deploy-Check")):
    fetched = asked_again(start, page_or_error, lambda answer: not isinstance(answer, Exception))
    if isinstance(fetched, Exception):
        problems.append(f"could not fetch {start}: {fetched}")
        continue
    where, text = fetched
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
    status, location, _ = asked_again(url, ask, link_has_settled)
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
  measure_new_site_retries "$1" "$2" "a brand-new site's page links (#869)" "page(s) or link(s)" "one page or link" "no page or link"
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

  hdr "Self-test — a brand-new site's files, asked again (#740)"
  cat >"$ST_DIR/files.py" <<'STUB'
import http.server, os, pathlib, sys
portfile, mode = sys.argv[1:3]
kind, _, limit = mode.partition(":")
seen = {"n": 0}
class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.do_GET()
    def do_GET(self):
        n = seen["n"]; seen["n"] = n + 1
        early = limit == "inf" or n < int(limit)
        if kind == "404" and early:
            body = b"Not Found - Request ID: stub\n"
            self.send_response(404)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
        else:
            body = b"self.onmessage = () => {};\n"
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript; charset=UTF-8")
            if not (kind == "nocoep" and early):
                self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
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
  fs_start() {  # fs_start <mode>: 404:K, 404:inf or nocoep:K
    rm -f "$ST_DIR/fport"
    python3 -I "$ST_DIR/files.py" "$ST_DIR/fport" "$1" &
    STUB_PID=$!
    for _ in $(seq 1 100); do [ -s "$ST_DIR/fport" ] && break; sleep 0.1; done
    FS_URL="http://127.0.0.1:$(cat "$ST_DIR/fport" 2>/dev/null)/static/swift/plantoir-swift-worker.js"
  }
  code_of() { printf '%s\n' "$1" | awk 'NR==1{print $2}'; }
  NS_POLL=1; NS_WAIT=4
  NS_RETRY_LOG="$ST_DIR/retries.tsv"; : >"$NS_RETRY_LOG"

  FIRST_PUBLISH=true
  fs_start 404:2
  out=$(fetch_headers 200 "$FS_URL" 2>"$ST_DIR/said.txt")
  if [ "$(code_of "$out")" = "200" ] && printf '%s' "$out" | grep -qi '^content-type: application/javascript' \
     && grep -q 'needed 2 retries' "$ST_DIR/said.txt" && grep -q $'\t2\t[0-9]*\ttrue$' "$NS_RETRY_LOG"; then
    ok "a brand-new site answers 404 twice, then the file: asked again, it passes, and the log says it took 2 retries"
  else
    no "a brand-new site answers 404 twice, then the file: got HTTP $(code_of "$out"), said: $(cat "$ST_DIR/said.txt")"
  fi
  st_stop

  fs_start nocoep:2
  out=$(fetch_headers coep "$FS_URL" 2>"$ST_DIR/said.txt")
  printf '%s\n' "$out" | grep -qi '^cross-origin-embedder-policy: require-corp' \
    && ok "a brand-new site sends the file without COEP twice, then with it: asked again, the COEP check passes" \
    || no "a brand-new site sends the file without COEP twice: said: $(cat "$ST_DIR/said.txt")"
  st_stop

  fs_start 404:inf
  started=$(date +%s)
  out=$(fetch_headers 200 "$FS_URL" 2>"$ST_DIR/said.txt")
  elapsed=$(( $(date +%s) - started ))
  n=$(sed -n 's/.*needed \([0-9][0-9]*\) retr.*/\1/p' "$ST_DIR/said.txt" | head -1)
  if [ "$(code_of "$out")" = "404" ] && grep -q 'never answered as wanted' "$ST_DIR/said.txt" \
     && [ -n "$n" ] && [ "$n" -ge 2 ] && [ "$n" -le 5 ] \
     && [ "$elapsed" -ge 4 ] && [ "$elapsed" -le 10 ]; then
    ok "a brand-new site that never serves the file: still the check's failure, judged on the last answer, at the cap (${elapsed} s, ${n} retries)"
  else
    no "a brand-new site that never serves the file: HTTP $(code_of "$out"), ${elapsed} s, said: $(cat "$ST_DIR/said.txt")"
  fi
  st_stop

  MEASURED=()
  measure_new_site_retries "Netlify" "http://127.0.0.1:"
  total=$(awk -F '\t' '{ t += $2 } END { print t + 0 }' "$NS_RETRY_LOG")
  printf '%s\n' "${MEASURED[@]}" | grep -q "3 file(s) needed asking again, $total retries in all" \
    && [ "$(awk -F '\t' '$4 == "true" && $2 == 2' "$NS_RETRY_LOG" | wc -l | tr -d ' ')" -eq 2 ] \
    && ok "the Result block counts them: ${MEASURED[0]#*: }" \
    || no "the Result block's count: ${MEASURED[*]:-nothing}"

  FIRST_PUBLISH=false
  : >"$NS_RETRY_LOG"
  fs_start 404:2
  out=$(fetch_headers 200 "$FS_URL" 2>"$ST_DIR/said.txt")
  if [ "$(code_of "$out")" = "404" ] && [ ! -s "$ST_DIR/said.txt" ] && [ ! -s "$NS_RETRY_LOG" ]; then
    ok "a plain run's long-lived site answers 404: judged at once, never asked again"
  else
    no "a plain run's 404: HTTP $(code_of "$out"), said: $(cat "$ST_DIR/said.txt")"
  fi
  st_stop

  hdr "Self-test — a brand-new site's pages, asked again (#869)"
  # A whole site on 127.0.0.1, so the REAL check_engine and check_page_links
  # run against it: every engine file at its type with COEP, the page of
  # runnable code with its block, its Swift program and its isolation, and a
  # front page with one more link. The page of runnable code, the front page
  # or the extra link can be made to answer 404 or 522 (Netlify's and
  # Cloudflare's measured answers at #835's gate), or 200 without the
  # runnable block, for the first K requests.
  cat >"$ST_DIR/whole.py" <<'STUB'
import http.server, os, pathlib, sys
portfile, runner_mode, front_mode, lesson_mode = sys.argv[1:5]
program = "static/swift-wasm/" + "ab" * 32 + ".wasm"
links = '<a href="/Runner-Deploy-Check">code</a> <a href="/Lesson-One">lesson</a>'
runner = f'<html><body>{links}<div class="plantoir-runner" data-runner-wasm="{program}"></div></body></html>'.encode()
front = f"<html><body>{links}</body></html>".encode()
types = {".wasm": "application/wasm", ".mjs": "application/javascript", ".js": "application/javascript",
         ".zip": "application/zip", ".json": "application/json", ".css": "text/css", ".woff2": "font/woff2"}
counts = {}
def early(path, mode):
    kind, _, limit = mode.partition(":")
    seen = counts.get(path, 0)
    counts[path] = seen + 1
    if kind == "good" or not (limit == "inf" or seen < int(limit)):
        return ""
    return kind
class Handler(http.server.BaseHTTPRequestHandler):
    def answer(self, status, body, kind, extra=()):
        self.send_response(status)
        self.send_header("Content-Type", kind)
        for name, value in extra:
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def not_yet(self, kind):
        if kind == "404":
            self.answer(404, b"Not Found - Request ID: stub\n", "text/plain")
        elif kind == "522":
            self.answer(522, b"error code: 522\n", "text/plain")
        else:
            self.answer(200, b"<html><body>a placeholder</body></html>", "text/html")
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/Runner-Deploy-Check.html":
            self.send_response(308)
            self.send_header("Location", "/Runner-Deploy-Check")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if path == "/Runner-Deploy-Check":
            kind = early(path, runner_mode)
            if kind:
                return self.not_yet(kind)
            return self.answer(200, runner, "text/html", (("Cross-Origin-Opener-Policy", "same-origin"),
                                                          ("Cross-Origin-Embedder-Policy", "require-corp")))
        if path == "/":
            kind = early(path, front_mode)
            if kind:
                return self.not_yet(kind)
            return self.answer(200, front, "text/html")
        if path == "/Lesson-One":
            kind = early(path, lesson_mode)
            if kind:
                return self.not_yet(kind)
            return self.answer(200, front, "text/html")
        if path == "/" + program:
            return self.answer(200, b"\0asm\1\0\0\0", "application/wasm")
        if path.startswith("/static/"):
            return self.answer(200, b"x", types.get(pathlib.PurePosixPath(path).suffix, "application/octet-stream"),
                               (("Cross-Origin-Embedder-Policy", "require-corp"),))
        self.answer(404, b"no such page\n", "text/plain")
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
pathlib.Path(portfile + ".part").write_text(str(server.server_port))
os.replace(portfile + ".part", portfile)
server.serve_forever()
STUB
  ws_start() {  # ws_start <runner mode> <front mode> <lesson mode>: good, 404:K, 522:K or bare:K
    rm -f "$ST_DIR/wport"
    python3 -I "$ST_DIR/whole.py" "$ST_DIR/wport" "$1" "$2" "$3" &
    STUB_PID=$!
    for _ in $(seq 1 100); do [ -s "$ST_DIR/wport" ] && break; sleep 0.1; done
    WS_URL="http://127.0.0.1:$(cat "$ST_DIR/wport" 2>/dev/null)/"
  }
  # Each check runs in a subshell so its ✅ and ❌ are read here rather than
  # counted, and the Result block's lines it would add are printed after it.
  ws_run() {  # ws_run <check_engine|check_page_links> -> its lines, then MEASURED lines
    ( MEASURED=(); NS_LEG=0
      if [ "$1" = check_engine ]; then check_engine "case" "$WS_URL"; else check_page_links "case" "$WS_URL" cloudflare; fi
      for line in ${MEASURED[@]+"${MEASURED[@]}"}; do printf 'MEASURED %s\n' "$line"; done ) 2>"$ST_DIR/said.txt"
  }
  WORK="$ST_DIR/work"; mkdir -p "$WORK"
  NS_POLL=1; NS_WAIT=4; NS_CALL_WAIT=60

  ws_start good good good
  FIRST_PUBLISH=true
  out=$(ws_run check_engine)
  if [ "$(printf '%s\n' "$out" | grep -c '❌')" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '✅')" -ge 20 ] && [ ! -s "$ST_DIR/said.txt" ]; then
    ok "control: the whole stub site passes every check_engine check at once, so the cases below test only the page"
  else
    no "control: the whole stub site did not pass check_engine at once: $(printf '%s\n' "$out" | grep '❌' | head -3) $(cat "$ST_DIR/said.txt")"
  fi
  st_stop

  for mode in 404:2 522:2 bare:2; do
    ws_start "$mode" good good
    out=$(ws_run check_engine)
    if [ "$(printf '%s\n' "$out" | grep -c '❌')" -eq 0 ] \
       && printf '%s\n' "$out" | grep -q "page of runnable code carries its runnable block" \
       && printf '%s\n' "$out" | grep -q "sends the page's Swift program" \
       && grep -q 'Runner-Deploy-Check needed 2 retries' "$ST_DIR/said.txt" \
       && printf '%s\n' "$out" | grep -q '^MEASURED case, .*(#740, #869): 1 file(s) needed asking again, 2 retries in all'; then
      ok "a brand-new site's page of runnable code answers ${mode%%:*} twice, then the page: asked again, the runnable block and Swift program checks pass, counted in the Result block"
    else
      no "a brand-new site's page of runnable code answers ${mode%%:*} twice: $(printf '%s\n' "$out" | grep -E '❌|^MEASURED' | head -4) said: $(cat "$ST_DIR/said.txt")"
    fi
    st_stop
  done

  # Three fetches of the page (its block, its isolation, its CSP) each ask
  # again until NS_WAIT, so at least 12 s; measured 12 to 13 s on a quiet
  # Mac and 28 s on a busy one, hence the wide ceiling.
  ws_start 522:inf good good
  started=$(date +%s)
  out=$(ws_run check_engine)
  elapsed=$(( $(date +%s) - started ))
  if printf '%s\n' "$out" | grep -q "page of runnable code answered HTTP 522 or carries no runnable block" \
     && printf '%s\n' "$out" | grep -q "page of runnable code carries no Swift program" \
     && grep -q 'Runner-Deploy-Check needed [0-9]* retr.*never answered as wanted' "$ST_DIR/said.txt" \
     && [ "$elapsed" -ge 12 ] && [ "$elapsed" -le 60 ]; then
    ok "a brand-new site's page that never comes is still the checks' failure, judged on the last answer (HTTP 522, ${elapsed} s in all)"
  else
    no "a brand-new site's page that never comes: ${elapsed} s, $(printf '%s\n' "$out" | grep '❌' | head -4) said: $(cat "$ST_DIR/said.txt")"
  fi
  st_stop

  ws_start good 404:2 404:1
  out=$(ws_run check_page_links)
  if printf '%s\n' "$out" | grep -q "✅ case's page links: 2 same-site links, 2 answered 200" \
     && grep -q '127.0.0.1:[0-9]*/ needed 2 retries' "$ST_DIR/said.txt" \
     && grep -q 'Lesson-One needed 1 retry' "$ST_DIR/said.txt" \
     && printf '%s\n' "$out" | grep -q "^MEASURED case, a brand-new site's page links (#869): 2 page(s) or link(s) needed asking again, 3 retries in all"; then
    ok "a brand-new site's front page and one link answer 404 at first: the page links are asked again, pass, and are counted in the Result block"
  else
    no "a brand-new site's page links: $(printf '%s\n' "$out" | head -4) said: $(cat "$ST_DIR/said.txt")"
  fi
  st_stop

  # A negative check passes only on a real answer (#869 review): the front
  # page never answering is a failure on the no-COEP line, never a pass.
  ws_start good 522:inf good
  out=$(ws_run check_engine)
  if printf '%s\n' "$out" | grep -q "❌ case's front page answered HTTP 522, so whether it sends COEP could not be judged" \
     && ! printf '%s\n' "$out" | grep -q "✅ case sends no COEP on the front page"; then
    ok "a front page that never answers fails the no-COEP check rather than passing it"
  else
    no "a front page that never answers: $(printf '%s\n' "$out" | grep -i 'front page' | head -2)"
  fi
  st_stop

  # The same for the CSP check when the page of runnable code never comes.
  ws_start 522:inf good good
  out=$(ws_run check_engine)
  if printf '%s\n' "$out" | grep -q "❌ case's page of runnable code answered HTTP 522, so whether its CSP names a CDN could not be judged" \
     && ! printf '%s\n' "$out" | grep -q "✅ case's CSP names no CDN"; then
    ok "a page of runnable code that never answers fails the CSP check rather than passing it"
  else
    no "a page that never answers, CSP: $(printf '%s\n' "$out" | grep -i 'CSP' | head -2)"
  fi
  st_stop

  # One deadline per call: once NS_CALL_WAIT has passed, the fetches left are
  # asked once. check_engine's page fetches (three) and check_page_links'
  # front page and link would each wait NS_WAIT; with the call's deadline at
  # NS_WAIT, only the first one is asked again.
  NS_CALL_WAIT=4
  ws_start 522:inf good good
  out=$(ws_run check_engine)
  n=$(grep -c 'Runner-Deploy-Check needed' "$ST_DIR/said.txt")
  if [ "$n" -eq 1 ] && printf '%s\n' "$out" | grep -q "page of runnable code carries no Swift program"; then
    ok "check_engine's call deadline: of the page's three fetches only the first is asked again, and the checks still fail"
  else
    no "check_engine's call deadline: $n fetches asked again, said: $(cat "$ST_DIR/said.txt")"
  fi
  st_stop
  ws_start good 404:inf 404:inf
  out=$(ws_run check_page_links)
  if grep -q '127.0.0.1:[0-9]*/ needed' "$ST_DIR/said.txt" && ! grep -q 'Lesson-One needed' "$ST_DIR/said.txt" \
     && printf '%s\n' "$out" | grep -q "❌ case's page links"; then
    ok "check_page_links' call deadline: the front page is asked again, the link after the deadline is asked once, and the check still fails"
  else
    no "check_page_links' call deadline: said: $(cat "$ST_DIR/said.txt")"
  fi
  st_stop
  NS_CALL_WAIT=60

  # Windows' verify-deploy.ps1 reads check_page_links' program out of this
  # file with its own expression and runs it with two arguments only. Read
  # the same way here, it must still run, and judge each answer once.
  ws_start good good 404:1
  python3 - "$0" "$ST_DIR/page_links.py" <<'READ'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read().replace("\r", "")
found = re.search(r"(?m)^check_page_links\(\) \{[^\n]*\n(?:(?!\}\n)[^\n]*\n)*?[^\n]*<<'PY'\n((?:(?!PY\n)[^\n]*\n)*?)PY\n", text)
open(sys.argv[2], "w", encoding="utf-8").write(found.group(1) + "\n" if found else "")
READ
  out=$(python3 -I "$ST_DIR/page_links.py" "$WS_URL" cloudflare 2>"$ST_DIR/said.txt"); rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^SUMMARY 2 same-site links, 1 answered 200' \
     && printf '%s\n' "$out" | grep -q '^PROBLEM /Lesson-One -> HTTP 404' && [ ! -s "$ST_DIR/said.txt" ]; then
    ok "the page-links program read out of this file as Windows reads it, given two arguments, runs and judges each answer once"
  else
    no "the page-links program as Windows reads it: rc $rc, said: $(printf '%s\n' "$out" | head -3) $(head -3 "$ST_DIR/said.txt")"
  fi
  st_stop

  FIRST_PUBLISH=false
  ws_start 404:2 good 404:1
  out=$(ws_run check_engine; ws_run check_page_links)
  if printf '%s\n' "$out" | grep -q "page of runnable code answered HTTP 404 or carries no runnable block" \
     && printf '%s\n' "$out" | grep -q "❌ case's page links" \
     && ! printf '%s\n' "$out" | grep -q '^MEASURED' && [ ! -s "$ST_DIR/said.txt" ]; then
    ok "a plain run's long-lived site answers 404 for its page and a link: judged at once, never asked again"
  else
    no "a plain run's page and link 404: $(printf '%s\n' "$out" | grep -E '❌|^MEASURED' | head -4) said: $(cat "$ST_DIR/said.txt")"
  fi
  st_stop

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

# ------------------------------------------------- a FIRST publish (#712)
# What a first publish reads, moved aside so deploy.py asks for a surname and
# names new sites - the same five paths as Windows' verify-deploy.ps1.
#
# THE ORIGINALS ARE NEVER DELETED, only renamed to <path>.verify-deploy-hidden,
# and the sentinel records, path by path and AFTER each step, whether that
# path's original was hidden or absent. Restoring deletes what is at a path
# only when its original is safe beside it (hidden) or there never was one
# (absent): then it is a record deploy.py wrote for the test's site. Anything
# else - a move that failed, a kill between a move and the sentinel - is left
# alone, and a hidden original is always moved back. So a run killed half way
# is put right by the NEXT run's preflight, and no failure on the way can
# cost the course its real records (Windows' Opus review of the same code).
FIRST_PUBLISH_STATE=(
  "$WORKING_FOLDER/courses/.internal/profile.json"
  "$WORKING_FOLDER/courses/_secrets/profile.json"
  "$WORKING_FOLDER/courses/$COURSE/.netlify_sites/section$SECTION.json"
  "$WORKING_FOLDER/courses/$COURSE/.cloudflare_sites/section$SECTION.json"
  "$WORKING_FOLDER/courses/$COURSE/section$SECTION/.netlify_site.json"
)
FIRST_PUBLISH_SENTINEL="$WORKING_FOLDER/courses/.verify-deploy-first-publish.txt"
SITES_MADE=()      # "netlify<TAB>name<TAB>site id<TAB>surname" / "cloudflare<TAB>name<TAB>account id<TAB>surname"
SITES_REPORT=()    # what the Result block says about each, deleted or not
SURNAME="Testing"
if [ "$FIRST_PUBLISH" = true ]; then
  # Letters only, as deploy.py asks. The host may keep the capital or fold
  # it (Netlify keeps it, measured), so the deletion below compares the site's
  # name with the surname in lower case. The surname is written into the
  # sentinel too, so a run killed half way is cleaned up against ITS surname.
  SURNAME="Testing$(LC_ALL=C tr -dc 'a-z' </dev/urandom | head -c 6)"
fi
first_publish_anything_hidden() {
  local path
  [ -f "$FIRST_PUBLISH_SENTINEL" ] && return 0
  for path in "${FIRST_PUBLISH_STATE[@]}"; do [ -e "$path.verify-deploy-hidden" ] && return 0; done
  return 1
}
first_publish_recorded() {  # first_publish_recorded <path> -> hidden|absent|""
  [ -f "$FIRST_PUBLISH_SENTINEL" ] || return 0
  awk -F '\t' -v p="$1" '$2 == p { v = $1 } END { if (v != "") print v }' "$FIRST_PUBLISH_SENTINEL"
}
first_publish_surname() {  # the surname the run that wrote the sentinel used, or ""
  [ -f "$FIRST_PUBLISH_SENTINEL" ] || return 0
  awk -F '\t' '$1 == "surname" { v = $2 } END { if (v != "") print v }' "$FIRST_PUBLISH_SENTINEL"
}
restore_first_publish_state() {
  local path hidden safe recorded line surname
  first_publish_anything_hidden || return 0
  # The surname of the run that hid these records - this run's, or a killed
  # earlier run's - never the current run's guess. Empty (a sentinel written
  # before #699's fixes, or none at all) means no site is deleted, only named.
  surname=$(first_publish_surname)
  for path in "${FIRST_PUBLISH_STATE[@]}"; do
    hidden="$path.verify-deploy-hidden"
    safe=false; [ -e "$hidden" ] && safe=true
    recorded=$(first_publish_recorded "$path")
    if [ -e "$path" ] && { [ "$safe" = true ] || [ "$recorded" = absent ]; }; then
      # A record deploy.py wrote for the test's site: its name (and the id the
      # host's API deletes it by) is kept for the Result block, then it goes.
      line=$(python3 - "$path" <<'PY2'
import json, sys
path = sys.argv[1]
try:
    record = json.load(open(path))
except Exception:
    sys.exit(0)
name = record.get("name") or ""
if not name:
    sys.exit(0)
if "cloudflare_sites" in path:
    print("cloudflare\t" + name + "\t" + (record.get("account_id") or ""))
elif "netlify" in path:
    print("netlify\t" + name + "\t" + (record.get("site_id") or record.get("id") or ""))
PY2
)
      [ -n "$line" ] && SITES_MADE+=("$line"$'\t'"$surname")
      rm -f "$path"
    fi
    if [ "$safe" = true ]; then
      mv -f "$hidden" "$path" 2>/dev/null \
        || { echo "  ⚠️  could not put $path back from $hidden - move it back by hand"; return 1; }
    elif [ "$recorded" = hidden ]; then
      echo "  ⚠️  $path was recorded as moved aside but $hidden is not there; left as it is"
    fi
  done
  rm -f "$FIRST_PUBLISH_SENTINEL"
  # deploy.py makes .internal/ to save the surname; when there was no saved
  # surname before the run, an empty one is all it left, and it goes too.
  rmdir "$WORKING_FOLDER/courses/.internal" 2>/dev/null
  echo "  ↩︎  put the saved surname and the section's own site records back"
}
hide_first_publish_state() {
  local path
  printf 'surname\t%s\n' "$SURNAME" >"$FIRST_PUBLISH_SENTINEL" \
    || { echo "could not write $FIRST_PUBLISH_SENTINEL"; return 1; }
  for path in "${FIRST_PUBLISH_STATE[@]}"; do
    if [ -e "$path" ]; then
      mv "$path" "$path.verify-deploy-hidden" 2>/dev/null || { echo "could not move $path aside"; return 1; }
      printf 'hidden\t%s\n' "$path" >>"$FIRST_PUBLISH_SENTINEL"
    else
      printf 'absent\t%s\n' "$path" >>"$FIRST_PUBLISH_SENTINEL"
    fi
  done
  return 0
}
# Deletes the sites a first publish made, through each host's own API, so a
# release's first-publish run leaves nothing on the accounts. Only a site whose
# record deploy.py wrote while the originals were hidden (collected by the
# restore above) and whose name carries the random surname of the run that hid
# them - read from the sentinel, so a killed run's sites are matched against
# ITS surname - is ever touched; never the section's own sites, whose records
# were hidden and are now back. The token
# goes to curl on stdin (-H @-), never on a command line.
delete_sites_made() {
  local entry kind name id surname code token
  for entry in ${SITES_MADE[@]+"${SITES_MADE[@]}"}; do
    IFS=$'\t' read -r kind name id surname <<<"$entry"
    if [ -z "$surname" ]; then
      SITES_REPORT+=("$kind $name: NOT deleted (the run that made it left no surname to check it against) - delete it by hand if it is a test site")
      continue
    fi
    surname=$(printf '%s' "$surname" | tr 'A-Z' 'a-z')
    # Netlify keeps the name as typed ("Testingabcdef", measured on the first
    # run, whose case-sensitive test left that site behind), so compare in
    # lower case.
    case "$(printf '%s' "$name" | tr 'A-Z' 'a-z')" in
      *"$surname"*) ;;
      *) SITES_REPORT+=("$kind $name: NOT deleted (its name does not carry the surname $surname of the run that made it)"); continue ;;
    esac
    code=""
    if [ "$kind" = netlify ] && [ -n "$id" ]; then
      token=$(security find-generic-password -s "containerized-quartz-netlify" -w 2>/dev/null)
      code=$(printf 'Authorization: Bearer %s\n' "$token" | curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
        -X DELETE -H @- "https://api.netlify.com/api/v1/sites/$id")
    elif [ "$kind" = cloudflare ] && [ -n "$id" ]; then
      token=$(security find-generic-password -s "containerized-quartz-cloudflare" -w 2>/dev/null)
      code=$(printf 'Authorization: Bearer %s\n' "$token" | curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
        -X DELETE -H @- "https://api.cloudflare.com/client/v4/accounts/$id/pages/projects/$name")
    fi
    token=""
    case "$code" in
      2??) SITES_REPORT+=("$kind $name: created by the first publish as $surname, and DELETED (HTTP $code)") ;;
      *)   SITES_REPORT+=("$kind $name: created by the first publish as $surname, NOT deleted (HTTP ${code:-none}) - delete it by hand") ;;
    esac
  done
  SITES_MADE=()
}

restore_what_was_borrowed() {
  # The unit plans leg's own borrowings (#709), when the run got that far.
  if type restore_the_plans_leg >/dev/null 2>&1; then restore_the_plans_leg; fi
  restore_first_publish_state
  delete_sites_made
  for line in ${SITES_REPORT[@]+"${SITES_REPORT[@]}"}; do echo "  ↩︎  $line"; done
  SITES_REPORT=()
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
# The teacher's own folder is never a test folder: this run rewrites its
# recipe, its destinations and its sites. Refused BEFORE the trap below is
# armed, so a refusal cannot run the trap's pkill against the teacher's
# own preview (#665 implementation review).
CANONICAL_FOLDER=$(cd "$WORKING_FOLDER" 2>/dev/null && /bin/pwd -P)
CLASS_WEBSITES=$(cd "$HOME/Desktop/Class Websites" 2>/dev/null && /bin/pwd -P)
if [ -n "$CANONICAL_FOLDER" ] && [ "$CANONICAL_FOLDER" = "$CLASS_WEBSITES" ]; then
  echo "  ❌ $WORKING_FOLDER is the teaching folder (Class Websites); run this against a test folder"
  exit 1
fi
# INT and TERM EXIT, and the EXIT trap puts things back once. A trap on INT
# that only restored would return to the script, which then kept publishing -
# as repeat publishes to the section's own sites, against addresses the
# restore had just deleted (#699 implementation review, measured).
trap restore_what_was_borrowed EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------------------------------------------------------------- preflight
hdr "Preflight — refuse clearly rather than half-running"
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

if first_publish_anything_hidden; then
  restore_first_publish_state
  delete_sites_made
  ok "a FIRST-publish run before this one was stopped half way: its surname and site records were put back first"
  for line in ${SITES_REPORT[@]+"${SITES_REPORT[@]}"}; do echo "    $line"; done
  SITES_REPORT=()
fi
if [ "$FIRST_PUBLISH" = true ]; then
  HIDE_PROBLEM=$(hide_first_publish_state) || {
    no "FIRST publish: ${HIDE_PROBLEM} - refusing to publish, and putting back what was moved"
    exit 1
  }
  ok "FIRST publish: the surname and the section's site records are moved aside; deploy.py will be told '$SURNAME'"
fi

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
      -re {last name.*: }        { send \"$SURNAME\r\"; exp_continue }
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

# wrangler 4.108 and later sends a NEW static project to Workers instead of
# Pages when it believes an AI agent is driving it (CLAUDECODE, AI_AGENT, ...
# in its environment, or an agent among its ancestors) - a different product
# at a different address. deploy.py is guarded three ways (--branch is an
# argument the delegation refuses, the project is made through the API before
# wrangler runs, and docker exec hands the container six named variables
# only), so a leg that prints the delegation's notice is a FAILURE: the site a
# teacher was told about is not the one that was made (#699).
check_no_delegation() {  # check_no_delegation <label> <logfile>
  if grep -aq "now part of Cloudflare Workers" "$2" 2>/dev/null; then
    no "$1 — wrangler delegated the upload to Cloudflare Workers instead of Pages"
  else
    ok "$1 — uploaded to Cloudflare Pages itself, with no delegation to Workers"
  fi
}

url_from_log() {  # url_from_log <logfile>
  grep -aoE "https://[a-zA-Z0-9._-]+\.(netlify\.app|pages\.dev)" "$1" | tail -1
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
  # Pages' line is "Uploaded N files (M already uploaded)" in 4.80.0 and
  # 4.156.0 alike, but a first-ever upload has nothing already uploaded and
  # prints "Uploaded N files (4.85 sec)", which the old pattern, requiring the
  # parenthesis, never matched (#712, measured). "files" exactly, so Netlify's
  # own "Uploaded N file(s)" line is not read as a Cloudflare count.
  files=$(grep -aoE "Netlify requires [0-9]+ file|Uploaded [0-9]+ files( \([0-9]+ already uploaded\))?" "$log" | tail -1)
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
  measure_deploy "Netlify, first publish with the engine" "$WORK/deploy-netlify.log" "$COURSE" "$SECTION" --target netlify \
    && ok "publish to Netlify exited 0" || no "publish to Netlify failed"
  NETLIFY_URL=$(url_from_log "$WORK/deploy-netlify.log")
  [ -n "$NETLIFY_URL" ] && wait_for_new_address "Netlify" "$NETLIFY_URL"
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
  check_no_delegation "Cloudflare Pages" "$WORK/deploy-cloudflare.log"
  snapshot_cloudflare_upload "Cloudflare Pages" "$WORK/deploy-cloudflare.log" "$WORK/cf-alone"; CF_SNAPPED=$?
  CF_URL=$(url_from_log "$WORK/deploy-cloudflare.log")
  [ -n "$CF_URL" ] && wait_for_new_address "Cloudflare Pages" "$CF_URL"
  [ -n "$CF_URL" ] && [ "$CF_SNAPPED" -eq 0 ] && wait_for_cloudflare_production "Cloudflare Pages" "$CF_URL" "$WORK/cf-alone"
  [ -n "$CF_URL" ] && check_url "Cloudflare Pages" "$CF_URL" || no "no Cloudflare address in the output"
  [ -n "$CF_URL" ] && check_engine "Cloudflare Pages" "$CF_URL/"
  [ -n "$CF_URL" ] && check_page_links "Cloudflare Pages" "$CF_URL/" cloudflare
else
  skip "Cloudflare (no credentials)"
fi

# ------------------------------------------- sharing unit plans (#709)
# The course's unit plans shared through deploy.sh --plans, for real, then
# fetched back: open, protected, sticky, a new password, open again, stopped.
# documentation/07-deployment.md -> "Sharing a unit plan (#709)" says why each
# check is here. School year 2099, which no teacher shares, so the leg never
# touches a real year's marker or site, and the project's name carries
# "plans-2099", which is what delete_sites_made matches it by if the leg dies.
# The plans' username and password are made for the run, stored in the
# Keychain under this folder's own account the way the launcher stores them,
# and removed on every exit; they reach curl through its config on stdin
# (-K -), never its arguments. A Keychain item the folder already had is not
# read: the leg is skipped instead.
PLANS_YEAR=2099
PLANS_DIR="$WORKING_FOLDER/courses/$COURSE/.internal/planning"
PLANS_MARKER="$WORKING_FOLDER/courses/$COURSE/.cloudflare_sites/plans-$PLANS_YEAR.json"
PLANS_ACCOUNT="$(cd "$WORKING_FOLDER" 2>/dev/null && /bin/pwd -P | shasum -a 256 | cut -c1-8)/$COURSE"
PLANS_USER="colleague709"
PLANS_PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
PLANS_PASS2="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
PLANS_BORROWED=false
PLANS_HAD_INTERNAL=true
PLANS_HAD_SITES_FOLDER=true
PLANS_STORED=false
restore_the_plans_leg() {
  if [ "$PLANS_STORED" = true ]; then
    security delete-generic-password -s containerized-quartz-unit-plan -a "$PLANS_ACCOUNT" >/dev/null 2>&1
    PLANS_STORED=false
    echo "  ↩︎  removed the unit plans' test username and password from the Keychain"
  fi
  if [ "$PLANS_BORROWED" = true ]; then
    rm -rf "$PLANS_DIR"
    if [ -e "$PLANS_DIR.verify-deploy-hidden" ]; then
      mv "$PLANS_DIR.verify-deploy-hidden" "$PLANS_DIR"
    fi
    rm -f "$PLANS_MARKER"
    if [ -e "$PLANS_MARKER.verify-deploy-hidden" ]; then
      mv "$PLANS_MARKER.verify-deploy-hidden" "$PLANS_MARKER"
    fi
    # Folders the leg made for a course that had none: removed only when
    # empty, so nothing else that landed in them is lost.
    [ "$PLANS_HAD_SITES_FOLDER" = true ] || rmdir "$(dirname "$PLANS_MARKER")" 2>/dev/null
    [ "$PLANS_HAD_INTERNAL" = true ] || rmdir "$(dirname "$PLANS_DIR")" 2>/dev/null
    PLANS_BORROWED=false
    echo "  ↩︎  put the course's own planning folder back as it was"
  fi
}
plan_status() {  # plan_status <url> [credential] -> the HTTP status, or 000
  if [ -n "${2:-}" ]; then
    printf 'user = "%s"\n' "$2" | curl -s -o /dev/null -w '%{http_code}' --max-time 20 -K - "$1" 2>/dev/null
  else
    curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$1" 2>/dev/null
  fi
}
plan_header() {  # plan_header <url> <header name> -> its value, without the credential
  curl -s -D - -o /dev/null --max-time 20 "$1" 2>/dev/null | tr -d '\r' | awk -v h="$(printf '%s' "$2" | tr 'A-Z' 'a-z')" -F': ' 'tolower($1) == h { print $2; exit }'
}
plans_api() {  # plans_api <path> -> the JSON; the token goes to curl on stdin
  local token
  token=$(security find-generic-password -s "containerized-quartz-cloudflare" -w 2>/dev/null)
  printf 'Authorization: Bearer %s\n' "$token" | curl -s --max-time 30 -H @- "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/pages/projects/$1"
  token=""
}
plans_expect() {  # plans_expect <label> <want> <url> [credential]
  local got waited=0
  for _ in $(seq 1 15); do
    got=$(plan_status "$3" "${4:-}")
    [ "$got" = "$2" ] && break
    sleep 2; waited=$((waited+2))
  done
  if [ "$got" = "$2" ]; then ok "$1 answers $2"; else no "$1 answered $got, not $2"; fi
}
plans_share() {  # plans_share <logfile> <flags...>
  local log="$1"; shift
  : >"$log"
  run_deploy "$log" "$COURSE" --plans --year "$PLANS_YEAR" --non-interactive "$@"
}

hdr "Sharing unit plans — Cloudflare Pages (#709)"
if [ "$HAVE_CLOUDFLARE" != true ]; then
  skip "unit plans (no Cloudflare credentials)"
elif security find-generic-password -s containerized-quartz-unit-plan -a "$PLANS_ACCOUNT" >/dev/null 2>&1; then
  skip "unit plans: this folder already keeps a username and password for $COURSE's plans, which this run will not read or replace"
else
  # Borrowed and put back exactly: a fresh course has no .internal yet, a
  # taught one may hold a plan of the teacher's own, and either may have
  # sites already recorded.
  [ -d "$(dirname "$PLANS_DIR")" ] || PLANS_HAD_INTERNAL=false
  [ -d "$(dirname "$PLANS_MARKER")" ] || PLANS_HAD_SITES_FOLDER=false
  PLANS_BORROWED=true
  if [ -e "$PLANS_DIR" ]; then mv "$PLANS_DIR" "$PLANS_DIR.verify-deploy-hidden"; fi
  if [ -e "$PLANS_MARKER" ]; then mv "$PLANS_MARKER" "$PLANS_MARKER.verify-deploy-hidden"; fi
  mkdir -p "$(dirname "$PLANS_DIR")"
  cp -R "$REPO/support/agent_guidance/skills/plantoir-unit-planning/template" "$PLANS_DIR"
  mkdir -p "$PLANS_DIR/unit/pdfs"
  printf '%%PDF-1.4 invented quiz\n' >"$PLANS_DIR/unit/pdfs/Quiz 1, Part A.pdf"
  printf '%%PDF-1.4 invented answer key\n' >"$PLANS_DIR/unit/pdfs/Quiz 1 - Solutions.pdf"
  security add-generic-password -U -s containerized-quartz-unit-plan -a "$PLANS_ACCOUNT" -w "$PLANS_USER:$PLANS_PASS" >/dev/null 2>&1 \
    && PLANS_STORED=true

  # 1. Open.
  plans_share "$WORK/plans-open.log" && ok "an open share exited 0" || no "an open share failed"
  PLANS_NAME=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name",""))' "$PLANS_MARKER" 2>/dev/null)
  PLANS_URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("address",""))' "$PLANS_MARKER" 2>/dev/null)
  [ -n "$PLANS_NAME" ] && SITES_MADE+=("cloudflare"$'\t'"$PLANS_NAME"$'\t'"$CF_ACCOUNT"$'\t'"plans-$PLANS_YEAR")
  if [ -z "$PLANS_URL" ]; then
    no "the open share wrote no address into its marker"
  else
    plans_expect "open: the list of plans" 200 "$PLANS_URL"
    plans_expect "open: a unit's plan" 200 "${PLANS_URL}unit/"
    plans_expect "open: a PDF with a space and a comma" 200 "${PLANS_URL}unit/pdfs/Quiz%201%2C%20Part%20A.pdf"
    plans_expect "open: the answer key, left out" 404 "${PLANS_URL}unit/pdfs/Quiz%201%20-%20Solutions.pdf"
    plans_expect "open: a missing path" 404 "${PLANS_URL}no-such-page"
    plans_expect "open: /_worker.js" 404 "${PLANS_URL}_worker.js"
    [ "$(plan_header "$PLANS_URL" x-robots-tag)" = "noindex, nofollow" ] && ok "open: X-Robots-Tag is sent" || no "open: no X-Robots-Tag"
    # Each share's worker names itself on every answer, which is how the
    # share's own proof tells its deployment from the one before (#709 M1).
    PLANS_SHARE_OPEN=$(plan_header "$PLANS_URL" x-plantoir-share)
    [ -n "$PLANS_SHARE_OPEN" ] && [ "$(plan_header "${PLANS_URL}no-such-page" x-plantoir-share)" = "$PLANS_SHARE_OPEN" ] \
      && ok "open: every answer carries the share's own id" || no "open: an answer without the share's own id"
    [ "$(curl -s --max-time 20 "${PLANS_URL}robots.txt" | tr -d '\r')" = "$(printf 'User-agent: *\nDisallow: /')" ] \
      && ok "open: robots.txt is the two lines" || no "open: robots.txt is not the two lines"
    plans_api "$PLANS_NAME" | python3 -c 'import json,sys; c=json.load(sys.stdin)["result"]["deployment_configs"]; sys.exit(0 if c["production"]["fail_open"] is False and c["preview"]["fail_open"] is False else 1)' \
      && ok "fail_open is false on both environments" || no "fail_open is not false on both environments"
    # The deployment's OWN address (eight hex characters before the
    # project), not the main one the share line prints after it.
    PLANS_FIRST=$(grep -aoE "https://[0-9a-f]{8}\.[a-z0-9-]+\.pages\.dev" "$WORK/plans-open.log" | tail -1)
    # A new project's own deployment addresses need their certificate first
    # (about 135 s, measured), or "the old address no longer answers" below
    # would pass for the wrong reason.
    for _ in $(seq 1 60); do [ "$(plan_status "$PLANS_FIRST/")" = "200" ] && break; sleep 5; done
    [ "$(plan_status "$PLANS_FIRST/")" = "200" ] && ok "the first deployment's own address answers before the protected share" \
      || no "the first deployment's own address never answered, so the old-copy check below proves nothing"

    # 2. Protected.
    plans_share "$WORK/plans-protect.log" --protect && ok "a protected share exited 0" || no "a protected share failed"
    for path in "" "unit/" "unit/pdfs/Quiz%201%2C%20Part%20A.pdf" "no-such-page" "_worker.js"; do
      plans_expect "protected: /$path without the password" 401 "${PLANS_URL}$path"
      plans_expect "protected: /$path with a wrong password" 401 "${PLANS_URL}$path" "$PLANS_USER:wrong-password"
    done
    _protected_share=$(plan_header "$PLANS_URL" x-plantoir-share)
    [ -n "$_protected_share" ] && [ "$_protected_share" != "$PLANS_SHARE_OPEN" ] \
      && ok "protected: the 401 comes from the new share's deployment" || no "protected: the 401 does not carry the new share's id"
    plans_expect "protected: the list of plans with the password" 200 "$PLANS_URL" "$PLANS_USER:$PLANS_PASS"
    plans_expect "protected: the answer key, included" 200 "${PLANS_URL}unit/pdfs/Quiz%201%20-%20Solutions.pdf" "$PLANS_USER:$PLANS_PASS"
    plans_expect "protected: /_worker.js with the password" 404 "${PLANS_URL}_worker.js" "$PLANS_USER:$PLANS_PASS"
    [ "$(plan_status "$PLANS_FIRST/")" != "200" ] && ok "the old open deployment's own address no longer answers 200" \
      || no "the OLD OPEN DEPLOYMENT still answers 200 without a password"
    [ "$(plans_api "$PLANS_NAME/deployments" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["result"]))')" = "1" ] \
      && ok "exactly one deployment is left" || no "older deployments were left"

    # 3. Sticky.
    plans_share "$WORK/plans-again.log" && ok "a share with no flag exited 0" || no "a share with no flag failed"
    plans_expect "a share with no flag is still protected" 401 "$PLANS_URL"

    # 4. A new password.
    security add-generic-password -U -s containerized-quartz-unit-plan -a "$PLANS_ACCOUNT" -w "$PLANS_USER:$PLANS_PASS2" >/dev/null 2>&1
    plans_share "$WORK/plans-new-password.log" --protect && ok "a share with a new password exited 0" || no "a share with a new password failed"
    plans_expect "the old password" 401 "$PLANS_URL" "$PLANS_USER:$PLANS_PASS"
    plans_expect "the new password" 200 "$PLANS_URL" "$PLANS_USER:$PLANS_PASS2"

    # 5. Open again.
    plans_share "$WORK/plans-open-again.log" --remove-password && ok "Remove Password exited 0" || no "Remove Password failed"
    plans_expect "open again: the list of plans" 200 "$PLANS_URL"
    plans_expect "open again: the answer key colleagues opened with the password" 404 "${PLANS_URL}unit/pdfs/Quiz%201%20-%20Solutions.pdf"
    if security find-generic-password -s containerized-quartz-unit-plan -a "$PLANS_ACCOUNT" >/dev/null 2>&1; then
      no "Remove Password left the Keychain item"
    else
      ok "Remove Password removed the Keychain item"; PLANS_STORED=false
    fi
    [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["address"])' "$PLANS_MARKER" 2>/dev/null)" = "$PLANS_URL" ] \
      && ok "the address did not change" || no "the address changed"

    # 6. Stop sharing.
    plans_share "$WORK/plans-stop.log" --stop-sharing && ok "Stop Sharing exited 0" || no "Stop Sharing failed"
    [ ! -e "$PLANS_MARKER" ] && ok "Stop Sharing removed the year's marker" || no "Stop Sharing left the year's marker"
    # Stop Sharing says stopped only once the address stopped answering, so
    # the very next fetch must not be the plans (#709 M5).
    case "$(plan_status "$PLANS_URL")" in
      200|401) no "Stop Sharing said stopped while the address still answered with the plans" ;;
      *) ok "Stop Sharing said stopped only once the address had stopped answering" ;;
    esac
    _stopped=false
    for _ in $(seq 1 15); do [ "$(plan_status "$PLANS_URL")" != "200" ] && { _stopped=true; break; }; sleep 2; done
    [ "$_stopped" = true ] && ok "the address stopped answering 200 within 30 s" || no "the address still answers 200 after Stop Sharing"
    if [ "$_stopped" = true ]; then
      # Gone already: only this leg's own entry leaves the list.
      _kept=()
      for _entry in ${SITES_MADE[@]+"${SITES_MADE[@]}"}; do
        case "$_entry" in *"$PLANS_NAME"*) ;; *) _kept+=("$_entry") ;; esac
      done
      SITES_MADE=(${_kept[@]+"${_kept[@]}"})
    fi
  fi
  restore_the_plans_leg
fi

# --------------------------------------------------------- the three pairings
# Run as the app runs them: the primary first, then each additional, one
# launcher call apiece. Both destinations are then fetched back — a pairing
# where the second leg silently did nothing is the failure worth catching.
hdr "Pairing 1 of 3 — Netlify primary, Cloudflare also"
if [ "$HAVE_NETLIFY" = true ] && [ "$HAVE_CLOUDFLARE" = true ]; then
  set_destination "netlify" "" '[{"type":"cloudflare_pages"}]'
  : >"$WORK/pair-nc.log"
  measure_deploy "Netlify, second publish" "$WORK/pair-nc.log" "$COURSE" "$SECTION" --target netlify && ok "leg 1 (Netlify) exited 0" || no "leg 1 (Netlify) failed"
  N_URL=$(url_from_log "$WORK/pair-nc.log")
  : >"$WORK/pair-nc2.log"
  measure_deploy "Cloudflare, second publish" "$WORK/pair-nc2.log" "$COURSE" "$SECTION" --target cloudflare --account "$CF_ACCOUNT" \
    && ok "leg 2 (Cloudflare) exited 0" || no "leg 2 (Cloudflare) failed"
  check_no_delegation "Cloudflare (paired with Netlify)" "$WORK/pair-nc2.log"
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
  run_deploy "$WORK/pair-nf.log" "$COURSE" "$SECTION" --target netlify && ok "leg 1 (Netlify) exited 0" || no "leg 1 (Netlify) failed"
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
  check_no_delegation "Cloudflare (paired with a folder)" "$WORK/pair-cf.log"
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

# A first publish's records are put back, and the sites it made deleted,
# BEFORE the Result block, so the block can name them. The exit trap does it
# again, harmlessly, on every other path.
restore_first_publish_state
delete_sites_made

hdr "Result"
echo "  $PASS passed, $FAIL failed, $SKIP skipped"
echo "  recipe: this checkout at $RECIPE_COMMIT$( [ "$RECIPE_DIRTY" -gt 0 ] && echo " with $RECIPE_DIRTY uncommitted change(s)" || echo ", clean"); $RECIPE_CHANGED difference(s) mirrored into the folder"
if [ "${#MEASURED[@]}" -gt 0 ]; then
  echo
  echo "  Publishing a site that carries the Python engine (#455), and Cloudflare's switch to it (#665), measured:"
  for line in "${MEASURED[@]}"; do echo "    $line"; done
fi
echo
if [ "$FIRST_PUBLISH" = true ]; then
  echo "  A FIRST publish, as surname '$SURNAME'. The sites it made:"
  [ "${#SITES_REPORT[@]}" -gt 0 ] || echo "    none recorded (no publish to Netlify or Cloudflare wrote a record)"
  for line in ${SITES_REPORT[@]+"${SITES_REPORT[@]}"}; do echo "    $line"; done
  SITES_REPORT=()
  echo "    Folder:     $FOLDER_TARGET"
else
  echo "  Sites this published to (the section's own; delete them when you are done with the folder):"
  [ -n "${NETLIFY_URL:-}${N_URL:-}" ] && echo "    Netlify:    ${NETLIFY_URL:-$N_URL}"
  [ -n "${CF_URL:-}${C_URL:-}" ]      && echo "    Cloudflare: ${CF_URL:-$C_URL}"
  echo "    Folder:     $FOLDER_TARGET"
fi
echo "  Logs: $WORK"
[ "$FAIL" -eq 0 ] || exit 1
