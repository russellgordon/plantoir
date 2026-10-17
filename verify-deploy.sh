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
WORK=/tmp/plantoir-deploy-verify-$$
FOLDER_TARGET="$WORK/published"

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
no()   { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
skip() { echo "  ⏭️  $1"; SKIP=$((SKIP+1)); }
hdr()  { echo; echo "──────── $1"; }

CONFIG="$WORKING_FOLDER/courses/$COURSE/course_config.json"
PUBLIC_DIR="$WORKING_FOLDER/courses/$COURSE/.merged_output/section$SECTION/public"

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

# How long a publish takes, and how many bytes it sends: seconds around the
# launcher, and the Obytes delta of the interface the default route uses
# (read on a quiet machine, or it counts everything else too).
NET_IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
obytes() { netstat -ibn 2>/dev/null | awk -v i="$NET_IFACE" '$1==i && $3 ~ /Link/ {print $10; exit}'; }
MEASURED=()
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
ok "a page of runnable code borrowed into section $SECTION (removed on any exit)"
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

hdr "Destination 2 of 3 — Netlify"
if [ "$HAVE_NETLIFY" = true ]; then
  set_destination "netlify" "" ""
  : >"$WORK/deploy-netlify.log"
  measure_deploy "Netlify, first publish with the engine" "$WORK/deploy-netlify.log" "$COURSE" "$SECTION" \
    && ok "publish to Netlify exited 0" || no "publish to Netlify failed"
  NETLIFY_URL=$(url_from_log "$WORK/deploy-netlify.log")
  [ -n "$NETLIFY_URL" ] && check_url "Netlify" "$NETLIFY_URL" || no "no Netlify address in the output"
  [ -n "$NETLIFY_URL" ] && check_engine "Netlify" "$NETLIFY_URL/"
else
  skip "Netlify (no token)"
fi

hdr "Destination 3 of 3 — Cloudflare Pages"
if [ "$HAVE_CLOUDFLARE" = true ]; then
  set_destination "cloudflare_pages" "" ""
  : >"$WORK/deploy-cloudflare.log"
  measure_deploy "Cloudflare, first publish with the engine" "$WORK/deploy-cloudflare.log" "$COURSE" "$SECTION" --target cloudflare --account "$CF_ACCOUNT" \
    && ok "publish to Cloudflare exited 0" || no "publish to Cloudflare failed"
  CF_URL=$(url_from_log "$WORK/deploy-cloudflare.log")
  [ -n "$CF_URL" ] && check_url "Cloudflare Pages" "$CF_URL" || no "no Cloudflare address in the output"
  [ -n "$CF_URL" ] && check_engine "Cloudflare Pages" "$CF_URL/"
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
  C_URL=$(url_from_log "$WORK/pair-nc2.log")
  [ -n "$N_URL" ] && check_url "Netlify (of the pair)" "$N_URL" || no "no Netlify address"
  [ -n "$C_URL" ] && check_url "Cloudflare (of the pair)" "$C_URL" || no "no Cloudflare address"
  [ -n "$N_URL" ] && check_engine "Netlify (of the pair)" "$N_URL/"
  [ -n "$C_URL" ] && check_engine "Cloudflare (of the pair)" "$C_URL/"
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
  C_URL=$(url_from_log "$WORK/pair-cf.log")
  : >"$WORK/pair-cf2.log"
  run_deploy "$WORK/pair-cf2.log" "$COURSE" "$SECTION" --to-folder "$FOLDER_TARGET" \
    && ok "leg 2 (folder) exited 0" || no "leg 2 (folder) failed"
  [ -n "$C_URL" ] && check_url "Cloudflare (of the pair)" "$C_URL" || no "no Cloudflare address"
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

hdr "Result"
echo "  $PASS passed, $FAIL failed, $SKIP skipped"
if [ "${#MEASURED[@]}" -gt 0 ]; then
  echo
  echo "  Publishing a site that carries the Python engine (#455), measured:"
  for line in "${MEASURED[@]}"; do echo "    $line"; done
fi
echo
echo "  Sites this created (delete them when you are done):"
[ -n "${NETLIFY_URL:-}${N_URL:-}" ] && echo "    Netlify:    ${NETLIFY_URL:-$N_URL}"
[ -n "${CF_URL:-}${C_URL:-}" ]      && echo "    Cloudflare: ${CF_URL:-$C_URL}"
echo "    Folder:     $FOLDER_TARGET"
echo "  Logs: $WORK"
[ "$FAIL" -eq 0 ] || exit 1
