#!/bin/bash
#
# Overnight batch: work the 18 issues from MAC-HANDOFF.md, one Claude session
# each, sequentially, on their own branches.
#
#   ./overnight/run.sh              # all 18, in order
#   ./overnight/run.sh 4            # just issue 04
#   ./overnight/run.sh 4 9          # issues 04 through 09
#   DRY_RUN=1 ./overnight/run.sh    # print what it would do, run nothing
#
# Design note, because it differs from how these sessions normally work:
# the SESSION does not merge to dev. It commits and pushes its own branch and
# stops. This driver then runs the mac test suite itself and merges only if
# that suite is green. Every issue branches off dev, so one session merging
# broken work would poison all the issues that follow it. Branches are left
# intact either way, so nothing is lost when a merge is refused.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERE="$REPO/overnight"
ISSUES="$HERE/issues"
LOGS="$HERE/logs"
PREAMBLE="$HERE/preamble.md"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
SUMMARY="$LOGS/summary-$RUN_ID.tsv"
TRANSCRIPT="$LOGS/run-$RUN_ID.log"

# Wall-clock ceiling for one session. A session that hits this is killed and
# recorded as TIMEOUT; the batch carries on with the next issue.
SESSION_TIMEOUT_SECONDS="${SESSION_TIMEOUT_SECONDS:-5400}"   # 90 minutes
DRY_RUN="${DRY_RUN:-0}"

mkdir -p "$LOGS"

# ---------------------------------------------------------------- output ----

say()  { printf '%s\n' "$*" | tee -a "$TRANSCRIPT"; }
rule() { say "════════════════════════════════════════════════════════════════"; }
stamp(){ date '+%H:%M:%S'; }

# ------------------------------------------------------------- preflight ----

preflight() {
    local failed=0

    command -v claude    >/dev/null || { say "MISSING: claude CLI";    failed=1; }
    command -v git       >/dev/null || { say "MISSING: git";           failed=1; }
    command -v xcodebuild>/dev/null || { say "MISSING: xcodebuild";    failed=1; }
    command -v xcodegen  >/dev/null || { say "MISSING: xcodegen (brew install xcodegen)"; failed=1; }
    command -v python3   >/dev/null || { say "MISSING: python3";       failed=1; }

    cd "$REPO" || exit 1

    if [ -n "$(git status --porcelain -- . ':!overnight')" ]; then
        say "REFUSING: working tree is dirty. Commit or stash first:"
        git status --short -- . ':!overnight' | tee -a "$TRANSCRIPT"
        failed=1
    fi

    local hooks
    hooks="$(git config --get core.hooksPath || true)"
    if [ "$hooks" != ".githooks" ]; then
        say "NOTE: core.hooksPath is '$hooks', expected '.githooks'. Setting it."
        git config core.hooksPath .githooks
    fi

    if [ ! -d "$REPO/mac-app/Vendor/llama" ]; then
        say "REFUSING: mac-app/Vendor/llama is absent — xcodegen will fail."
        say "  Run: cd mac-app && ./Vendor/fetch-llama.sh"
        failed=1
    fi

    if ! git ls-remote --exit-code origin >/dev/null 2>&1; then
        say "REFUSING: cannot reach origin. Check the network and credentials."
        failed=1
    fi

    if pgrep -x Plantoir >/dev/null 2>&1; then
        say "NOTE: Plantoir is running. 'xcodebuild test' will terminate it."
        say "      Quitting it now so that happens cleanly."
        osascript -e 'quit app "Plantoir"' >/dev/null 2>&1
        sleep 2
    fi

    [ "$failed" -eq 0 ] || { say "Preflight failed. Nothing was run."; exit 1; }
    say "Preflight OK."
}

# ------------------------------------------------------------- watchdog ----

# macOS has no coreutils `timeout`, so this is the equivalent.
# Returns 124 on timeout, otherwise the command's own status.
run_limited() {
    local secs="$1"; shift
    "$@" &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge "$secs" ]; then
            say "  !! session exceeded ${secs}s — terminating"
            kill -TERM "$pid" 2>/dev/null
            sleep 10
            kill -KILL "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 10
        waited=$((waited + 10))
    done
    wait "$pid"
}

# ----------------------------------------------------------- test gating ----

# The gate the driver trusts. Deliberately run by the driver and not read from
# the session's own claim of success.
run_mac_suite() {
    local log="$1"
    (
        cd "$REPO/mac-app" || exit 1
        xcodegen generate >/dev/null 2>&1
        xcodebuild -project Plantoir.xcodeproj -scheme Plantoir \
                   -configuration Debug test -only-testing:QuartzTeachersTests
    ) >"$log" 2>&1
}

# Did the TEST HOST die, rather than a test failing?
#
# `xcodebuild` reports both as exit 65 and `** TEST FAILED **`, and names
# whichever test was running when the process went — which is a bystander. The
# honest reading is two lines further up: XCTest says `Restarting after
# unexpected exit, crash, or test timeout`, and the totals say 0 failures.
#
# On 2026-09-06/07 that rejected 3 of 7 pieces of correct work in one batch,
# and the driver could not tell, because it branched on the exit status alone.
#
# **This deliberately does NOT retry.** A retry was the obvious answer and is
# the wrong one: a host crash a diff genuinely introduced at, say, a one-in-three
# rate would pass a single retry two times in three, and the batch merges into
# `dev` unattended, so that is exactly the thing nobody would be awake to catch.
# The harm this gate actually did was not "refused a merge" — a refused merge
# costs one `git merge` in the morning — it was "said TESTS-FAILED about work
# whose tests all passed", and sent somebody after an innocent test. Naming it
# fixes that at no cost in honesty.
#
# It matters more now, not less. The crash this was written for is fixed at
# source (`mac-app/Tests/QuartzTeachersTests/SheetAnimationSuppressor.swift`),
# so a host crash here is NEWS: something new kills the host. Retrying past it
# would throw away the one signal that has become worth having.
# It reports the two facts SEPARATELY, because they are independent and the
# first version of this got that wrong: it required "no failed test case", so a
# host crash landing in the same run as an ordinary failure still printed
# TESTS-FAILED — which is exactly the confusion it was written to remove, and
# is not hypothetical, since `dev` currently carries one deliberate red case
# (the `section restored` trail event Windows proposed; see MAC-HANDOFF.md).
#
# Note that "unexpected exit, crash, or test timeout" also covers a HANG, so a
# crash is not the only thing this can mean and the message says so — a timed-out
# run leaves no .ips to go and read.
mac_suite_host_died() {
    grep -q 'Restarting after unexpected exit' "$1"
}

mac_suite_failed_a_test() {
    grep -qE '^[[:space:]]*(Test Case .* failed|.*: error:)' "$1"
}

# `xcodebuild test` leaves a TEST HOST in DerivedData, not the app. A plain
# build afterwards is what makes the Dock icon point at something runnable.
rebuild_app() {
    (
        cd "$REPO/mac-app" || exit 1
        xcodebuild -project Plantoir.xcodeproj -scheme Plantoir \
                   -configuration Debug build
    ) >"$LOGS/final-build-$RUN_ID.log" 2>&1
}

# ---------------------------------------------------------------- issues ----

# macOS ships bash 3.2, which has no `mapfile`.
ALL_BRIEFS=()
while IFS= read -r line; do
    ALL_BRIEFS+=("$line")
done < <(find "$ISSUES" -name '[0-9][0-9]-*.md' | sort)
[ "${#ALL_BRIEFS[@]}" -gt 0 ] || { echo "No briefs in $ISSUES"; exit 1; }

FROM="${1:-1}"
TO="${2:-${#ALL_BRIEFS[@]}}"

# -------------------------------------------------------------- one issue ---

work_issue() {
    local brief="$1"
    local base slug num branch prompt_file log_jsonl log_txt test_log
    base="$(basename "$brief" .md)"
    num="${base%%-*}"
    slug="${base#*-}"
    branch="issue/$slug"

    prompt_file="$LOGS/$base.prompt.md"
    log_jsonl="$LOGS/$base.jsonl"
    log_txt="$LOGS/$base.txt"
    test_log="$LOGS/$base.tests.log"

    rule
    say "[$(stamp)] Issue $num — $slug"
    rule

    cd "$REPO" || return 1

    # Always start from a fresh dev, so each issue builds on the merges before it.
    git checkout dev >/dev/null 2>&1
    if ! git pull --ff-only origin dev >/dev/null 2>&1; then
        say "  SKIP: could not fast-forward dev. Resolve by hand."
        printf '%s\t%s\t%s\t%s\n' "$num" "$slug" "SKIPPED" "dev not fast-forwardable" >>"$SUMMARY"
        return 0
    fi

    if git rev-parse --verify "$branch" >/dev/null 2>&1; then
        say "  SKIP: branch $branch already exists — this issue looks done."
        printf '%s\t%s\t%s\t%s\n' "$num" "$slug" "SKIPPED" "branch already exists" >>"$SUMMARY"
        return 0
    fi

    cat "$PREAMBLE" "$brief" >"$prompt_file"

    if [ "$DRY_RUN" = "1" ]; then
        say "  DRY RUN: would branch $branch and run a session on $(basename "$brief")"
        printf '%s\t%s\t%s\t%s\n' "$num" "$slug" "DRY-RUN" "-" >>"$SUMMARY"
        return 0
    fi

    git checkout -b "$branch" dev >/dev/null 2>&1 || {
        say "  FAIL: could not create $branch"
        printf '%s\t%s\t%s\t%s\n' "$num" "$slug" "FAILED" "branch creation" >>"$SUMMARY"
        return 0
    }
    say "  branched $branch off dev"

    say "  [$(stamp)] session starting (limit $((SESSION_TIMEOUT_SECONDS / 60))m)…"
    run_limited "$SESSION_TIMEOUT_SECONDS" \
        claude -p "$(cat "$prompt_file")" \
            --model opus \
            --permission-mode bypassPermissions \
            --output-format stream-json \
            --verbose \
            >"$log_jsonl" 2>>"$TRANSCRIPT"
    local claude_status=$?

    # Render the session's own text out of the stream for a readable log,
    # and pull the BATCH-RESULT line it was told to end with.
    local verdict
    verdict="$(python3 - "$log_jsonl" "$log_txt" <<'PY'
import json, sys, re
src, dst = sys.argv[1], sys.argv[2]
text = []
try:
    with open(src, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except ValueError:
                continue
            message = event.get("message") or {}
            for block in message.get("content") or []:
                if isinstance(block, dict) and block.get("type") == "text":
                    text.append(block["text"])
            if event.get("type") == "result" and isinstance(event.get("result"), str):
                text.append(event["result"])
except OSError:
    pass
body = "\n".join(text)
with open(dst, "w", encoding="utf-8") as handle:
    handle.write(body)
found = re.findall(r"^BATCH-RESULT:.*$", body, re.MULTILINE)
print(found[-1].strip() if found else "BATCH-RESULT: UNKNOWN — no status line")
PY
)"

    if [ "$claude_status" -eq 124 ]; then
        verdict="BATCH-RESULT: TIMEOUT — killed after ${SESSION_TIMEOUT_SECONDS}s"
    fi
    say "  $verdict"

    # Did it actually produce anything?
    local commits
    commits="$(git rev-list --count dev.."$branch" 2>/dev/null || echo 0)"
    say "  commits on branch: $commits"

    if [ "$commits" -eq 0 ]; then
        say "  nothing committed — leaving dev untouched"
        printf '%s\t%s\t%s\t%s\n' "$num" "$slug" "NO-COMMITS" "$verdict" >>"$SUMMARY"
        git checkout dev >/dev/null 2>&1
        return 0
    fi

    # Push the branch regardless of what the gate says. Work that stays on one
    # machine is invisible to every other machine (CLAUDE.md rule 6).
    if git push -u origin "$branch" >/dev/null 2>&1; then
        say "  pushed $branch"
    else
        say "  WARNING: could not push $branch"
    fi

    say "  [$(stamp)] running the mac suite as the merge gate…"
    if run_mac_suite "$test_log"; then
        say "  tests GREEN"
        git checkout dev >/dev/null 2>&1
        if git merge --no-ff "$branch" \
             -m "Merge $branch into dev

Overnight batch $RUN_ID, issue $num.
$verdict

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>" >/dev/null 2>&1; then
            if git push origin dev >/dev/null 2>&1; then
                say "  MERGED into dev and pushed"
                printf '%s\t%s\t%s\t%s\n' "$num" "$slug" "MERGED" "$verdict" >>"$SUMMARY"
            else
                say "  merged locally but PUSH FAILED — dev is ahead of origin"
                printf '%s\t%s\t%s\t%s\n' "$num" "$slug" "MERGED-NOT-PUSHED" "$verdict" >>"$SUMMARY"
            fi
        else
            say "  MERGE CONFLICT — aborting, dev left as it was"
            git merge --abort >/dev/null 2>&1
            printf '%s\t%s\t%s\t%s\n' "$num" "$slug" "CONFLICT" "$verdict" >>"$SUMMARY"
        fi
    else
        # Two independent facts, reported as such. A run can carry both.
        local outcome="TESTS-FAILED"
        if mac_suite_host_died "$test_log"; then
            if mac_suite_failed_a_test "$test_log"; then
                outcome="HOST-DIED-AND-TESTS-FAILED"
                say "  THE TEST HOST DIED **and** a test failed — both, in one run."
            else
                outcome="HOST-DIED"
                say "  THE TEST HOST DIED and NO test failed. The 'Failing tests:'"
                say "  line below names a bystander; the totals are the truth."
            fi
            say "  A crash or a hang: look for the newest"
            say "  ~/Library/Logs/DiagnosticReports/Plantoir-*.ips, and if there"
            say "  is none, it was a hang."
        else
            say "  tests RED — a test genuinely failed."
        fi
        say "  Refusing to merge. Branch is pushed and kept; see $test_log."
        printf '%s\t%s\t%s\t%s\n' "$num" "$slug" "$outcome" "$verdict" >>"$SUMMARY"
    fi

    git checkout dev >/dev/null 2>&1
    return 0
}

# ------------------------------------------------------------------ main ----

: >"$SUMMARY"
printf 'num\tslug\tstatus\tverdict\n' >>"$SUMMARY"

rule
say "Plantoir overnight batch — run $RUN_ID"
say "issues $FROM..$TO of ${#ALL_BRIEFS[@]}, sequential"
say "logs: $LOGS"
rule

preflight

START_EPOCH=$(date +%s)

index=0
for brief in "${ALL_BRIEFS[@]}"; do
    index=$((index + 1))
    [ "$index" -ge "$FROM" ] || continue
    [ "$index" -le "$TO" ]   || continue
    work_issue "$brief"
done

# Leave the Dock icon pointing at a real app rather than a test host, and
# leave it QUIT — launching it would steal focus (CLAUDE.md rule 10).
if [ "$DRY_RUN" != "1" ]; then
    say ""
    say "[$(stamp)] final rebuild so the Debug bundle is runnable…"
    if rebuild_app; then say "  build OK"; else say "  BUILD FAILED — see $LOGS/final-build-$RUN_ID.log"; fi
fi

ELAPSED=$(( ($(date +%s) - START_EPOCH) / 60 ))

rule
say "Finished in ${ELAPSED} minutes."
rule
column -t -s $'\t' "$SUMMARY" 2>/dev/null | tee -a "$TRANSCRIPT" || cat "$SUMMARY"
rule
say ""
say "dev is now at: $(git -C "$REPO" rev-parse --short dev)"
say "Branches kept for stitching against the Windows work:"
git -C "$REPO" branch --list 'issue/*' | tee -a "$TRANSCRIPT"
say ""
say "Full summary: $SUMMARY"
say "Per-issue transcripts: $LOGS/NN-slug.txt"

# Give the terminal back (CLAUDE.md rule 9).
osascript -e 'tell application "iTerm" to activate' >/dev/null 2>&1 || true
