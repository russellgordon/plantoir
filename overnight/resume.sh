#!/bin/bash
#
# Pick up the baton on one issue from the overnight batch, with the original
# session's context intact — and with the resume briefing already typed.
#
#   ./overnight/resume.sh 5          # asks what shape the work should take
#   ./overnight/resume.sh 5 --show   # print the briefing, resume nothing
#
# It checks out that issue's branch FIRST, then resumes its session with the
# briefing as the opening message. The order matters: the agent's memory is of
# a working tree on that branch, so resuming while `dev` is checked out hands
# it files it does not recognise.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="$REPO/overnight/logs"

NUM="${1:-}"
SHOW="${2:-}"

if [ -z "$NUM" ]; then
    echo "usage: ./overnight/resume.sh <issue number> [--show]"
    echo
    echo "Issues with a session on disk:"
    for f in "$LOGS"/[0-9][0-9]-*.jsonl; do
        [ -e "$f" ] || continue
        b="$(basename "$f" .jsonl)"
        printf '  %s  %s\n' "${b%%-*}" "${b#*-}"
    done
    exit 1
fi

NUM="$(printf '%02d' "$((10#$NUM))" 2>/dev/null || echo "$NUM")"

JSONL="$(find "$LOGS" -maxdepth 1 -name "${NUM}-*.jsonl" | head -1)"
[ -n "$JSONL" ] || { echo "No session log for issue $NUM in $LOGS"; exit 1; }

BASE="$(basename "$JSONL" .jsonl)"
SLUG="${BASE#*-}"
BRANCH="issue/$SLUG"
TESTLOG="$LOGS/$BASE.tests.log"

# The session id is stamped on the init event and again on the result event.
SESSION_ID="$(python3 - "$JSONL" <<'PY'
import json, sys
found = None
try:
    with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if isinstance(event, dict) and event.get("session_id"):
                found = event["session_id"]      # last one wins
except OSError:
    pass
print(found or "")
PY
)"

[ -n "$SESSION_ID" ] || { echo "No session id in $JSONL — the run may have died before starting."; exit 1; }

VERDICT="$(grep -h '^BATCH-RESULT:' "$LOGS/$BASE.txt" 2>/dev/null | tail -1)"
[ -n "$VERDICT" ] || VERDICT="(no status line recorded)"

# What the driver decided, from the newest summary that mentions this issue.
STATUS="$(grep -h "^$NUM	" "$LOGS"/summary-*.tsv 2>/dev/null | tail -1 | cut -f3)"
[ -n "$STATUS" ] || STATUS="UNKNOWN"

echo "issue     $NUM — $SLUG"
echo "branch    $BRANCH"
echo "session   $SESSION_ID"
echo "driver    $STATUS"
echo "verdict   $VERDICT"
[ -f "$TESTLOG" ] && echo "tests     $TESTLOG"
echo

# ------------------------------------------------------- what shape of work --

# Suggest the likely one from what the driver recorded.
case "$STATUS" in
    TESTS-FAILED)  SUGGEST=2 ;;
    CONFLICT)      SUGGEST=1 ;;
    NO-COMMITS)    SUGGEST=3 ;;
    *)             case "$VERDICT" in
                       *TIMEOUT*)  SUGGEST=5 ;;
                       *PROPOSED*) SUGGEST=4 ;;
                       *BLOCKED*)  SUGGEST=3 ;;
                       *)          SUGGEST=1 ;;
                   esac ;;
esac

echo "What shape should this work take?"
echo "  1  Finish the work"
echo "  2  Fix the failing tests"
echo "  3  Explain what blocked you"
echo "  4  Implement a decision I have now made"
echo "  5  Recover from a timeout, then finish"
echo
printf 'choice [%s]: ' "$SUGGEST"
read -r CHOICE </dev/tty
CHOICE="${CHOICE:-$SUGGEST}"

DECISION=""
if [ "$CHOICE" = "4" ]; then
    echo
    echo "What have you decided? One or two sentences, in your own words."
    printf '> '
    read -r DECISION </dev/tty
    [ -n "$DECISION" ] || { echo "No decision given — nothing to implement."; exit 1; }
fi

case "$CHOICE" in
  1) ASK="Finish the work. Pick up where you stopped rather than re-planning it." ;;
  2) ASK="The suite is red and I have not looked at why. Read $TESTLOG, find the actual cause, and fix it. If the failure is in code you did not touch, say so plainly rather than fixing around it — it may belong to an issue that merged after yours, and I would rather know that than have it papered over. Do NOT weaken or delete an assertion to get green. If the honest answer is that your change is wrong, say that; reverting is a fine outcome." ;;
  3) ASK="Explain what stopped you, and what you would need in order to finish. I am at the keyboard this time, which you did not have overnight, so ask me rather than guessing. Do not resume implementing until I have answered." ;;
  4) ASK="You wrote this up as a proposal rather than implementing it, which was what the brief told you to do. I have read it and I am choosing: ${DECISION}

Implement that now. Keep the reasoning you already wrote — including the options you rejected — and record my decision alongside it in the handoff, so the next person sees what was chosen and what was not. Where your proposal and my decision differ, mine is what ships, but say so if you think I have missed something: I would rather hear it now than find it in a teacher's course." ;;
  5) ASK="You were killed by the batch's time ceiling, so your last few steps may be half-finished. Before continuing, work out what state you actually left things in — git status, git log --oneline dev..HEAD, and a look at the files you were editing. Tell me what is complete, what is half-done, and what you had not started, then finish it. If the work is genuinely too large for one session, say so and propose where to cut it rather than rushing." ;;
  *) echo "Not a choice: $CHOICE"; exit 1 ;;
esac

# -------------------------------------------------------------- the briefing --

MERGE_NOTE="Your branch $BRANCH was pushed to origin either way, so your work is safe."
[ "$STATUS" = "MERGED" ] || MERGE_NOTE="$MERGE_NOTE It was NOT merged, so dev was left untouched."

TEST_NOTE=""
[ -f "$TESTLOG" ] && TEST_NOTE=" The suite output is in $TESTLOG — read it before theorising."

PROMPT="You are resuming after the overnight batch finished. You have your full context — your plan, the Fable reviews, and what you tried. Do not start over, and do not re-read everything: pick up where you stopped.

Three things happened after your session ended that you do not know about.

One. The batch driver ran the mac unit suite itself, independently of whatever you reported, and used it to decide whether to merge. The driver recorded your result as ${STATUS}, and your own last line was: ${VERDICT}.${TEST_NOTE}

Two. ${MERGE_NOTE}

Three. Other issues ran after yours and some of them merged, so dev has moved on. Before you do anything else: git fetch origin, then merge origin/dev into your branch and resolve anything that conflicts. Do not rebase — the branch is already pushed. Then re-run the suite, because the tree you are looking at is not the tree you were working in.

What I want from you now: ${ASK}

The rules have not changed. CLAUDE.md still applies, the write-ups (GUI-IMPROVEMENTS.md, both handoffs, the activity trail, the documentation pass) are still part of the work, and any further chunk still gets an adversarial Fable review before you call it done. Commit and push your branch as you go. Do NOT merge into dev — that stays mine.

Finish with the same BATCH-RESULT: line as before so I can scan it."

if [ "$SHOW" = "--show" ]; then
    echo
    echo "──────── briefing ────────"
    printf '%s\n' "$PROMPT"
    echo "──────────────────────────"
    echo
    echo "would run: git checkout $BRANCH && claude --resume=$SESSION_ID <briefing>"
    exit 0
fi

# ------------------------------------------------------------------ resume ---

cd "$REPO" || exit 1

if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    echo "WARNING: branch $BRANCH does not exist locally — the session may have"
    echo "         committed nothing. Resuming on $(git rev-parse --abbrev-ref HEAD)."
else
    if [ -n "$(git status --porcelain)" ]; then
        echo "REFUSING: working tree is dirty. Commit or stash before switching branches."
        git status --short
        exit 1
    fi
    git checkout "$BRANCH" || exit 1
fi

echo
echo "Resuming $BRANCH with the briefing already sent…"
echo
exec claude --resume="$SESSION_ID" "$PROMPT"
