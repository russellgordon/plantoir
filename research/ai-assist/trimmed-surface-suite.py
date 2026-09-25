#!/usr/bin/env python3
"""The TRIMMED surface (AssistAgent.NarrowToLocal), measured.

**The surface was FIFTEEN tools when this ran on 2026-08-14, and is thirteen
now** — `AssistAgent.ForTheLocalModel` dropped four `plan_` tools and gained
`read_remembered_timetable` and `add_next_class` on 2026-08-17 (4089c752).
The results below are of the fifteen and are sound; `narrow-tools.py` will
hand this suite THIRTEEN today, so a re-run is not comparable to them
without saying so.

Answers the question HISTORY.md part 2 section 6.1 left open: did the
TEACHERS SAY phrasings and the trim fix the 69%? Measured 2026-08-14
(results in trimmed-surface-results.txt): 91% bare, 94% with the two fixes
this suite can toggle, zero polarity inversions throughout.

The toggles exist because each one was earned:

  --date-appended    "(Today is ...)" on the END of the user message. Without
                     it every "tomorrow" became the schema's example date
                     (2023-09-15, in 2026). PREPENDED the same line cost 15
                     points of routing, so the position is the finding.
  --date-prepended   The version that failed, kept so the failure can be
                     reproduced rather than re-discovered.
  --real-course      Schema examples say the window's course instead of
                     "for example ICS3U". Without it, a request naming no
                     course copied ICS3U out of the examples 9/9 times.

The shipped configuration is --date-appended --real-course, which is what
AssistAgent does (Say appends the date; NarrowToLocal rewrites examples).

  --prompt FORM      Which system prompt to send. Default `hyphen`, which is
                     the SYSTEM constant below and what every number in this
                     folder before 2026-09-18 was taken against.
                       hyphen     the constant below (ASCII hyphens)
                       shipped    AssistAgent.swift's literal, read out of the
                                  Swift at run time — em-dashes and all
                       pre-tweak  the same literal as it stood at b77b91bd^,
                                  read with `git show`: before the two
                                  "undo_last_change reverses only..." sentences
                     `hyphen` and `shipped` are asserted equal modulo six
                     em-dashes on every run; see `assert_forms_agree`.
  --temperature X    Default 0.1, which is what the older runs used.
  --app-body         Send the request AssistModelClient sends: temperature 0,
                     tool_choice "auto", and `max_tokens` READ OUT OF THE
                     SWIFT (`AssistModelClient.mostTokensPerReply`, 512 since
                     #166) rather than copied here. Greedy decoding makes
                     repeated trials near-deterministic, so a trial count is
                     not a failure rate — see the note in the report.
  --uncapped         Only with --app-body: send no `max_tokens` at all, which
                     is the body the mac sent BEFORE #166. Kept for the same
                     reason `--date-prepended` and `--prompt pre-tweak` are:
                     the version that failed, kept so the failure can be
                     reproduced rather than re-discovered. Every `--app-body`
                     number taken before 2026-09-19 — including
                     `metal-routing-results.txt`'s H arm — is this arm.
  --intercept-only   Run the interception guard and stop. No server needed.
  --mac-shelf        Measure the MAC's shelf (AssistSupportingViews.swift)
                     instead of the 29 probes. The eleven "promise card"
                     probes in the default set are WINDOWS'
                     `AssistAgent.ExampleRequests` and are worded differently;
                     see the comment on PROMISED.

Usage:
  python trimmed-surface-suite.py TOOLS.json [trials] [--date-appended]
         [--date-prepended] [--real-course] [--port 8099] [--course VVH2O]
         [--prompt hyphen|shipped|pre-tweak] [--temperature 0.1] [--app-body]
         [--uncapped]
         [--intercept-only]

TOOLS.json is the narrowed OpenAI-shaped surface. Produce it from the contract
— which is generated from the app, so it cannot be a surface that does not
ship:

    python3 research/ai-assist/tools-from-contract.py local > /tmp/real-tools.json

On WINDOWS the contract holds the MAC's descriptions, so dump the live surface
there instead: dump-tools.ps1 (raw tools/list) piped through narrow-tools.py.
"""
import datetime
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.request
import urllib.error

args = [a for a in sys.argv[1:]]
TOOLS_PATH = args.pop(0) if args and not args[0].startswith("--") else "tools-local.json"
TRIALS = int(args.pop(0)) if args and not args[0].startswith("--") else 3
PORT = args[args.index("--port") + 1] if "--port" in args else "8099"
DATE_APPENDED = "--date-appended" in args
DATE_PREPENDED = "--date-prepended" in args
REAL_COURSE = "--real-course" in args
# --course VVH2O swaps the course everywhere (prompts, system message,
# example replacement) — matching a saved cache's course skips the cold read.
COURSE = args[args.index("--course") + 1] if "--course" in args else "EXC2O"
SECTION = 1
PROMPT_FORM = args[args.index("--prompt") + 1] if "--prompt" in args else "hyphen"
APP_BODY = "--app-body" in args
UNCAPPED = "--uncapped" in args
TEMPERATURE = float(args[args.index("--temperature") + 1]) if "--temperature" in args else 0.1
if APP_BODY:
    # AssistModelClient.reply: temperature 0, tool_choice auto, and a cap read
    # out of the Swift below (or none at all with --uncapped, which is the
    # body the mac sent before #166).
    TEMPERATURE = 0.0
if UNCAPPED and not APP_BODY:
    sys.exit("--uncapped only means anything with --app-body: every other arm "
             "sends the suite's historic max_tokens 256.")
INTERCEPT_ONLY = "--intercept-only" in args
# The MAC's shelf instead of Windows' ExampleRequests — see MAC_SHELF below.
MAC_SHELF_ONLY = "--mac-shelf" in args

ROOT = pathlib.Path(__file__).resolve().parents[2]
AGENT_SWIFT = "mac-app/QuartzTeachers/Models/Assist/AssistAgent.swift"
CLIENT_SWIFT = "mac-app/QuartzTeachers/Models/Assist/AssistModelClient.swift"
PRE_TWEAK_COMMIT = "b77b91bd^"

ENDPOINT = "http://127.0.0.1:%s/v1/chat/completions" % PORT

def replace_examples(node):
    if isinstance(node, dict):
        return {k: replace_examples(v) for k, v in node.items()}
    if isinstance(node, list):
        return [replace_examples(v) for v in node]
    if isinstance(node, str):
        return node.replace("ICS3U", COURSE)
    return node

TOOLS = json.load(open(TOOLS_PATH, encoding="utf-8-sig"))
if REAL_COURSE:
    TOOLS = replace_examples(TOOLS)

TODAY = datetime.date.today()
TOMORROW = TODAY + datetime.timedelta(days=1)
DATELINE = "(Today is %s, a %s.)" % (TODAY.isoformat(), TODAY.strftime("%A"))

# AssistAgent's system prompt for EXC2O section 1, ALMOST verbatim. Updated
# 2026-08-14 when the approval gate narrowed to deploys only (plan-first-and-
# wait removed); the 94% in trimmed-surface-results.txt was measured with the
# PREVIOUS wording and has not been re-run against this one.
#
# Updated again 2026-08-24 with the two sentences that fixed the "undo
# over-salient" and "hide inversion" clusters flagged in TODO.md — see
# conversational-residue-results.txt.
#
# **"Verbatim" was not true, and saying so is the point of this note.** This
# copy writes ASCII hyphens where AssistAgent.swift (and AssistAgent.cs)
# write em-dashes — six characters, and the ONLY difference between the two.
# Every number in this folder was taken against the hyphen form, so it stays
# the default rather than being quietly corrected: correcting it would make
# today's run incomparable with every earlier one and prove nothing about
# which form ships. The em-dash form is measurable instead, with
# `--prompt shipped`, which READS the Swift rather than copying it — see
# `swift_system_prompt` below — and `assert_forms_agree` fails the run if the
# two ever differ by anything else. That is what the old "keep this in sync
# by hand; nothing pins the three together automatically" could not do.
# The measured delta between the two forms is in metal-routing-results.txt.
SYSTEM_HYPHEN = (
    f"You are Plantoir's assistant, helping a teacher with {COURSE} section 1. "
    "Choose exactly one tool at a time and fill in its arguments from what the teacher said. "
    "Publishing and unpublishing are safe to do straight away - every change is backed up "
    "and undo_last_change takes it back - so do what was asked without asking permission first. "
    "Never guess a course, a section, a page title "
    "or a date - if you are not certain, look it up or ask. "
    "If no tool fits, say so plainly instead of inventing one. "
    "undo_last_change reverses only the assistant's own most recent action - a teacher "
    "describing something THEY did earlier, even calling it a mistake, is asking to "
    "publish or unpublish, not to undo. There is no tool to delete, remove or rename a "
    "page or a folder - if asked for that, say so plainly instead of choosing a tool "
    "that does something else.\n"
    "PUBLISHING a page decides whether students can see it in the site. "
    "DEPLOYING sends the whole site to the web. They are different acts. "
    "After a change, Plantoir opens the preview by itself so the teacher can look it over. "
    "Do not offer to deploy unless they ask; when they do ask, say plainly that "
    "deploying puts the change in front of students immediately and that reviewing "
    "the preview first is the safer order - then do as they decide."
)


def swift_system_prompt(source: str, course: str, section: int) -> str:
    """The `systemPrompt(course:section:)` literal, read out of the Swift.

    Read rather than copied, because a copy is what went stale: the hyphen
    form above sat here for a month describing itself as verbatim. This
    understands the two things a Swift multiline literal does that a plain
    read would get wrong — the closing delimiter's indentation is stripped
    from every line, and a trailing backslash means "no line break here".
    """
    marker = "static func systemPrompt(course: String, section: Int) -> String {"
    start = source.index(marker)
    opening = source.index('"""', start) + 3
    closing = source.index('"""', opening)
    # The closing delimiter's own indentation is what Swift strips from the
    # body, so it is measured rather than guessed at.
    indent = len(source[:closing].rsplit("\n", 1)[1])
    lines = source[opening:closing].split("\n")[1:-1]
    text = ""
    for line in lines:
        body = line[indent:] if line.startswith(" " * indent) else line.lstrip()
        if body.endswith("\\"):
            text += body[:-1]
        else:
            text += body + "\n"
    text = text.rstrip("\n")
    return text.replace("\\(course)", course).replace("\\(section)", str(section))


def swift_most_tokens_per_reply() -> int:
    """`AssistModelClient.mostTokensPerReply`, read out of the Swift.

    Read rather than copied, for the reason the system prompt is: a hand copy
    of a shipping value is exactly what `narrow-tools.py` taught this folder
    not to keep. It EXITS when the constant cannot be found — a renamed
    constant that quietly fell back to a default would make the `--app-body`
    arm measure the uncapped body while its header line claimed otherwise,
    which is a measurement that looks like evidence and is not.
    """
    source = (ROOT / CLIENT_SWIFT).read_text(encoding="utf-8")
    found = re.search(r"static let mostTokensPerReply:\s*Int\s*=\s*(\d+)", source)
    if not found:
        sys.exit(
            "Could not find `static let mostTokensPerReply: Int = N` in %s.\n"
            "The --app-body arm sends what the app sends, so it cannot run "
            "until this reads the real value. Fix the regex above (or pass "
            "--uncapped, which deliberately sends no cap)." % CLIENT_SWIFT
        )
    return int(found.group(1))


def system_prompt(form: str, course: str, section: int) -> str:
    """The system message this arm sends."""
    if form == "hyphen":
        return SYSTEM_HYPHEN
    if form == "shipped":
        return swift_system_prompt(
            (ROOT / AGENT_SWIFT).read_text(encoding="utf-8"), course, section
        )
    if form == "pre-tweak":
        source = subprocess.run(
            ["git", "-C", str(ROOT), "show", "%s:%s" % (PRE_TWEAK_COMMIT, AGENT_SWIFT)],
            capture_output=True, text=True, check=True,
        ).stdout
        return swift_system_prompt(source, course, section)
    sys.exit("--prompt must be hyphen, shipped or pre-tweak (got %r)" % form)


def assert_forms_agree() -> int:
    """Fail the run if the hyphen copy has drifted from the shipped literal.

    Read-only, and run before anything is measured: a suite whose system
    prompt is not the app's measures nothing about the app, and the ONLY
    licensed difference is the em-dash. Returns how many were folded.
    """
    shipped = system_prompt("shipped", COURSE, SECTION)
    folded = shipped.replace("\u2014", "-")
    if folded != SYSTEM_HYPHEN:
        for index, (a, b) in enumerate(zip(folded, SYSTEM_HYPHEN)):
            if a != b:
                sys.exit(
                    "SYSTEM_HYPHEN no longer matches AssistAgent.swift at character %d:\n"
                    "  swift (em-dashes folded): %r\n"
                    "  this file:                %r" % (index, folded[index - 40:index + 40],
                                                        SYSTEM_HYPHEN[index - 40:index + 40])
                )
        sys.exit("SYSTEM_HYPHEN and AssistAgent.swift differ in length: %d vs %d"
                 % (len(SYSTEM_HYPHEN), len(folded)))
    return shipped.count("\u2014")


WRITES = {"publish_class_on", "publish_pages", "unpublish_pages", "deploy_section",
          "schedule_deploy", "cancel_scheduled_deploy", "undo_last_change"}
PUBLISHERS = {"publish_class_on", "plan_publish_class_on", "publish_pages", "plan_publish_pages"}

# (acceptable tool names, prompt, probe label, needs_date)
# None in the tuple means declining is acceptable. "EXC2O" in a prompt is
# replaced by --course at run time.
#
# THE PROMISE CARD, verbatim — **WINDOWS'**, and that is not a detail.
# These eleven are `AssistAgent.ExampleRequests` in the C#, which is the
# Windows window's list. The MAC's shelf is
# `mac-app/QuartzTeachers/Views/Assist/AssistSupportingViews.swift` and it is
# a DIFFERENT list, worded differently: it offers "Deploy at 6:30 AM" where
# this says "Deploy tomorrow's class at 6:30 AM", and "Publish Unit 2, Day 3"
# where this says "Publish Unit 2, Day 3, and everything it links to".
# Correcting a claim that stood here from 2026-08-14 and was quoted as a mac
# figure in three places: a score on this list is a score on WINDOWS'
# promises. Use --mac-shelf for the mac's own, which is measured in
# metal-routing-results.txt and, at temperature 0, in shelf-phrasings-results.txt.
#
# Kept as the Windows list rather than replaced, because every comparable
# figure in this folder was taken against it. No course is named in any of
# them, because the window names it in the system prompt. SIX of them never
# reach the model in the app — five until 2026-09-19, when "Unpublish Unit 2,
# Day 3" became a code-answered phrasing with issue #215 and the promise-card
# denominator the run prints dropped from 6 of 11 to 5 of 11. They are
# measured anyway, for the bring-your-own-assistant path, and the run reports
# them separately. Count them from the run's own line rather than from this
# comment: `intercepted in code before the model (N of M probes)` is computed,
# and a number typed in prose is a number that rots.
PROMISED = [
    (("plan_publish_pages", "publish_pages"),
     "Publish Unit 2, Day 3, and everything it links to",
     "card: publish by name", False),

    (("plan_publish_class_on", "publish_class_on"),
     "Publish tomorrow's class",
     "card: publish tomorrow", True),

    (("plan_unpublish_pages", "unpublish_pages"),
     "Unpublish Unit 2, Day 3",
     "card: unpublish by name", False),

    (("plan_unpublish_pages", "unpublish_pages"),
     "I published Unit 4, Day 1 by mistake — unpublish it",
     "card: unpublish, mistake", False),

    (("plan_publish_pages", "publish_pages"),
     "What would publishing Unit 3, Day 1 change?",
     "card: plan a publish", False),

    (("check_section",),
     "What would students see in this section right now?",
     "card: check the section", False),

    (("rebuild_preview",),
     "Rebuild the preview",
     "card: rebuild preview", False),

    (("undo_last_change",),
     "Undo that",
     "card: undo", False),

    (("deploy_section",),
     "Deploy this section now",
     "card: deploy now", False),

    (("plan_scheduled_deploy", "schedule_deploy"),
     "Deploy tomorrow's class at 6:30 AM",
     "card: schedule a deploy", True),

    (("cancel_scheduled_deploy",),
     "Cancel that scheduled deploy",
     "card: cancel the deploy", False),
]

CASES = PROMISED + [
    (("plan_publish_class_on", "publish_class_on"),
     "Publish tomorrow's class for EXC2O section 1, and make sure every page it "
     "links to is published rather than left as a draft.",
     "publish tomorrow, with links", True),

    (("plan_publish_pages", "publish_pages"),
     "Put up Unit 3, Day 2 for EXC2O section 1, along with everything it points at.",
     "publish by name, informal", False),

    (("plan_unpublish_pages", "unpublish_pages"),
     'Hide tomorrow\'s class again in EXC2O section 1 - the page is "Ohm\'s Law".',
     "HIDE - the inversion case", False),

    (("plan_unpublish_pages", "unpublish_pages"),
     "Take Unit 4, Day 5 back down in EXC2O section 1, students shouldn't see it yet.",
     "hide, informal (verbatim cue)", False),

    (("plan_unpublish_pages", "unpublish_pages"),
     "I posted Unit 2, Day 3 in EXC2O section 1 by mistake. Make it a draft again.",
     "hide, phrased as a mistake", False),

    (("list_pages",),
     "What pages are in section 1 of EXC2O?",
     "list pages", False),

    (("read_page", "list_pages"),
     'What does "Unit 2, Day 3" in EXC2O section 1 link to?',
     "read", False),

    (("check_section",),
     "What do my students actually see right now in EXC2O section 1? Is anything broken?",
     "check section", False),

    (("rebuild_preview",),
     "Rebuild the preview for EXC2O section 1, please.",
     "rebuild preview", False),

    (("undo_last_change",),
     "Never mind, undo that.",
     "undo", False),

    (("plan_scheduled_deploy", "schedule_deploy"),
     "Deploy EXC2O section 1 at 6:30 tomorrow morning, before school starts.",
     "schedule a deploy", True),

    (("deploy_section",),
     "Push EXC2O section 1 live now - the site, not just the preview.",
     "deploy now", False),

    (("cancel_scheduled_deploy",),
     "Actually, cancel that scheduled deploy for EXC2O section 1.",
     "cancel scheduled deploy", False),

    # No course named at all - the window's REAL situation: the teacher opened
    # it on a section, and the system prompt is the only place the course is.
    (("plan_publish_class_on", "publish_class_on"),
     "Publish tomorrow's class, and everything it links to.",
     "no course named: publish", True),

    (("plan_unpublish_pages", "unpublish_pages"),
     'Take "Unit 1, Day 2" back down, students shouldn\'t see it yet.',
     "no course named: hide", False),

    ((None,), "Delete the Unit 1 folder in EXC2O.", "deletion - no such tool", False),
    ((None,), "What's the weather going to be like tomorrow?", "out of scope", False),

    (("plan_publish_class_on", "publish_class_on"),
     "publsh tomorows class for exc2o sec 1 and the stuff it links to",
     "typos", True),
]

# THE MAC'S OWN SHELF, verbatim from AssistSupportingViews.swift, in the order
# the window lists it. Added 2026-09-18 (#117) because the eleven above are
# WINDOWS' promises and had been quoted as the mac's.
#
# Most of these are answered in code — the interception guard marks which, and
# it is the guard rather than this list that decides, so a shape moved into or
# out of AssistCardCommand changes the answer here by itself. The four that
# reach the model are the ones this list is evidence about; `re_date_classes`
# and the rest are not even ON the local surface, so a model could not choose
# them if it were asked.
MAC_SHELF = [
    (("plan_publish_pages", "publish_pages"), "Publish Unit 2, Day 3",
     "shelf: publish by name", False),
    (("plan_publish_class_on", "publish_class_on"), "Publish tomorrow's class",
     "shelf: publish tomorrow", True),
    (("plan_publish_class_on", "publish_class_on"), "Publish Monday's class",
     "shelf: publish Monday", False),
    (("plan_publish_pages", "publish_pages"), "Publish Unit 5",
     "shelf: publish a unit", False),
    (("plan_unpublish_pages", "unpublish_pages"), "Unpublish Unit 2, Day 3",
     "shelf: unpublish by name", False),
    (("plan_unpublish_pages", "unpublish_pages"), "Unpublish Unit 4",
     "shelf: unpublish a unit", False),
    (("undo_last_change",), "Undo that", "shelf: undo", False),
    (("check_section",), "What would students see in this section right now?",
     "shelf: check the section", False),
    (("rebuild_preview",), "Preview", "shelf: preview", False),
    (("add_next_class",), "Add the next class page", "shelf: add next class", False),
    (("add_next_class",), "Start a new unit for the next class",
     "shelf: start a new unit", False),
    (("add_next_class",), "Add five more days to Unit 4", "shelf: more days", False),
    (("add_next_class",), "Duplicate Unit 3, Day 2 as my next class",
     "shelf: duplicate a class", False),
    (("read_remembered_timetable",), "When are my next classes?",
     "shelf: when are my classes", False),
    (("read_remembered_timetable",), "I have a revised list of class dates",
     "shelf: revised dates", False),
    (("re_date_classes",), "Re-date my classes", "shelf: re-date", False),
    (("deploy_section",), "Deploy now", "shelf: deploy now", False),
    # The one that matters: not intercepted, and it carries a TIME for the
    # model to read out, which is why it was left to the model in the first
    # place.
    (("plan_scheduled_deploy", "schedule_deploy"), "Deploy at 6:30 AM",
     "shelf: deploy at 6:30", False),
    (("cancel_scheduled_deploy",), "Cancel scheduled deploy",
     "shelf: cancel the deploy", False),
]

SHELF_SWIFT = "mac-app/QuartzTeachers/Views/Assist/AssistSupportingViews.swift"


def shelf_phrasings() -> list:
    """Every phrasing on the mac's shelf, READ out of the Swift.

    `narrow-tools.py` is the cautionary tale this exists to avoid: a hand copy
    of a shipping list that was right when committed and silently wrong three
    days later. So MAC_SHELF above is checked against the source on every run
    rather than trusted — parsed from `AssistPromptShelfView.groups`, whose
    shape is `("Group title", ["a phrasing", "another"])`, with the group
    titles (the literal straight after an opening bracket) dropped because
    they are UI and never reach the model.
    """
    source = (ROOT / SHELF_SWIFT).read_text(encoding="utf-8")
    opening = source.index("static let groups: [(String, [String])] = [")
    closing = source.index("\n    ]", opening)
    # Comment lines are dropped FIRST: this table is more comment than code,
    # and the comments quote phrasings — including ones deliberately NOT on
    # the shelf, like "Publish the class on Monday" — which a naive reader of
    # the string literals picks up as if they were cards.
    kept = []
    for line in source[opening:closing].split("\n"):
        if line.lstrip().startswith("//"):
            continue
        kept.append(line)
    region = "\n".join(kept)
    titles = set(re.findall(r'\(\s*"([^"]*)"\s*,\s*\[', region))
    phrasings = []
    for literal in re.findall(r'"([^"]*)"', region):
        if literal in titles or not literal:
            continue
        phrasings.append(literal)
    return phrasings


def assert_shelf_is_current() -> int:
    """Fail the run if MAC_SHELF has drifted from the shelf it copies."""
    onScreen = shelf_phrasings()
    copied = [prompt for _, prompt, _, _ in MAC_SHELF]
    missing = [p for p in onScreen if p not in copied]
    extra = [p for p in copied if p not in onScreen]
    if missing or extra:
        sys.exit(
            "MAC_SHELF no longer matches %s:\n"
            "  on the shelf and NOT measured: %s\n"
            "  measured and NOT on the shelf: %s\n"
            "Fix the list above before quoting a number from this arm."
            % (SHELF_SWIFT, missing or "none", extra or "none")
        )
    if len(onScreen) != len(copied):
        sys.exit("MAC_SHELF has %d entries, the shelf has %d"
                 % (len(copied), len(onScreen)))
    return len(copied)


if MAC_SHELF_ONLY:
    CASES = MAC_SHELF
    PROMISED = []


def intercepted(message, window_course=None, window_section=None):
    """The tool `AssistCardCommand.matching` would run without the model.

    A probe the app answers in code measures nothing about routing, so the
    suite has to know which ones those are — and it has to know it from the
    CONTRACT rather than from a hand-copied list, which is how
    `narrow-tools.py` went stale for three days without anyone noticing.
    Same tidying as the Swift: trim, strip leading and trailing `.` and `!`,
    lower-case, then EQUALITY — never a substring. Then the parsed families
    (nine in `cardPhrasings.parsed` since #167), which cannot be listed because
    the number, title or TIME in them is unbounded. THREE of them are checked
    against the contract's own rows before any probe is sent — "deploy at
    <time>" by `assert_deploy_at_a_time_matches_contract()`, the hide/unpublish
    frame by `assert_hide_is_unpublish_matches_contract()` and "what does
    <page> link to?" by `assert_links_question_matches_contract()`, all below.
    This guard went one family stale once already, and a stale guard scores a
    routing result for a sentence the app never routes.

    `window_course` and `window_section` are the window the sentence is typed
    in, read by the links family only (#167): a place it names is accepted
    only when it is that window's. The probes pass COURSE and SECTION.

    Widened 2026-09-19 with issue #215: "hide" means what "unpublish" means and
    is answered in code, and both verbs take a class page as well as a whole
    unit. The WHOLE VERB is gated, not only the day arm — publish keeps the
    frame it shipped with, so `publish unit 4, day 3`, `publish unit 4?` and
    `please publish unit 4` all still go to the model. That asymmetry is what
    the Swift argues for and the contract carries as five refused rows.
    """
    with open(ROOT / "contracts" / "assist-cases.json", encoding="utf-8") as handle:
        phrasings = json.load(handle)["cardPhrasings"]["matches"]
    tidied = message.strip().strip(".!").lower()
    for entry in phrasings:
        if tidied == entry["phrasing"]:
            return entry["tool"]
    whole_unit_or_class_page = unit_or_class_page(tidied)
    if whole_unit_or_class_page:
        return whole_unit_or_class_page
    counts = r"(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d+)"
    if re.fullmatch(r"add %s more days to unit \d+" % counts, tidied):
        return "add_next_class"
    room = re.fullmatch(r"make room for (\S+) (class|classes) at unit \d+,? day \d+", tidied)
    if room and re.fullmatch("a|%s" % counts, room.group(1)):
        # The Swift refuses a plural count with a singular noun, and the
        # refusal is the point of the shape — so the guard refuses it too.
        one = room.group(1) in ("a", "one", "1")
        if one == (room.group(2) == "class"):
            return "make_room_for_classes"
    if deploy_at_a_time(tidied):
        return "schedule_deploy"
    if deploy_time_asked_about(tidied):
        # Not a tool: the app answers "deploy at 6:30" with a question of its
        # own and sends nothing to the model (#194), so a probe like this one
        # measures nothing about routing either.
        return ASKED_IN_CODE
    if deploy_time_said_as(tidied):
        # Not a tool either: a time written a way the app can read but does
        # not set ("deploy at 6.30 pm") is answered with the one sentence to
        # type instead, and nothing is sent to the model (#277).
        return SAID_AS_IN_CODE
    links = links_question(message, window_course, window_section)
    if links == "read_page":
        return "read_page"
    if links is not None:
        # Not a tool: another course named in a links question is refused in
        # code with the sentence a model-named course gets (#167).
        return REFUSED_IN_CODE
    if re.fullmatch(r"duplicate .+ as (my next class|the next class|my next lesson)", tidied):
        return "add_next_class"
    return None


# What `intercepted` answers for a links question naming another course,
# which the app refuses in code — deliberately not a tool name (#167).
REFUSED_IN_CODE = "(refused in code: another course named)"


def links_question(message, window_course, window_section):
    """Mirror of `AssistCardCommand.linksQuestion` (#167).

    "read_page" for a question the app answers in code, ("another", code) for
    one naming another course, None for one that goes to the model. Pinned
    against `linksQuestion` in the contract by
    `assert_links_question_matches_contract()` before anything is measured.
    """
    typed = message.strip().strip(".!")
    while typed.endswith("?"):
        typed = typed[:-1].strip(" \t")
    typed = links_without_please(typed)
    lowered = typed.lower()
    if len(lowered) != len(typed):
        return None
    title_slot, tail = None, ""
    verb_frames = [("what does ", [" link to", " point to"]), ("which pages does ", [" link to"]),
                   ("what pages does ", [" link to"]), ("where does ", [" link to", " point to"])]
    for opening, closings in verb_frames:
        if title_slot is not None or not lowered.startswith(opening):
            continue
        end, length = None, 0
        for closing in closings:
            at = lowered.rfind(closing)
            if at >= 0 and (end is None or at > end):
                end, length = at, len(closing)
        start = len(opening)
        if end is None or not start < end:
            return None
        title_slot, tail = typed[start:end], typed[end + length:]
    for opening in ["what links are on ", "what links are in ", "show me the links on ",
                    "show me the links in ", "show me the links from ", "list the links on ",
                    "list the links in ", "list the links from "]:
        if title_slot is None and lowered.startswith(opening):
            title_slot = typed[len(opening):]
    if title_slot is None:
        return None
    places = 0
    tail = tail.strip(" \t")
    if tail:
        if not tail.lower().startswith("in "):
            return None
        place = links_place(tail[3:], window_course, window_section)
        if place == "window":
            places += 1
        elif isinstance(place, tuple):
            return place
        else:
            return None
    title = title_slot
    at = title.lower().rfind(" in ")
    if at >= 0:
        place = links_place(title[at + 4:], window_course, window_section)
        if place == "window":
            places += 1
            title = title[:at]
        elif isinstance(place, tuple):
            return place
        elif place == "section":
            return None
    if places > 1:
        return None
    return "read_page" if links_page_title(title) else None


def links_without_please(typed):
    lowered = typed.lower()
    for opening in ("please, ", "please "):
        if lowered.startswith(opening):
            typed = typed[len(opening):]
            break
    lowered = typed.lower()
    for closing in (", please", " please"):
        if lowered.endswith(closing):
            typed = typed[:-len(closing)]
            break
    while typed.endswith("?") or typed.endswith(","):
        typed = typed[:-1].strip(" \t")
    return typed.strip(" \t")


def links_page_title(slot):
    title = slot.strip(" \t")
    while title.endswith(","):
        title = title[:-1].strip(" \t")
    for open_, close in (('"', '"'), ("\u201c", "\u201d"), ("'", "'"), ("\u2018", "\u2019")):
        if len(title) >= 2 and title.startswith(open_) and title.endswith(close):
            title = title[1:-1].strip(" \t")
            break
    if not title:
        return None
    folded = title.lower().replace("\u2019", "'")
    if folded in ("it", "this", "that", "this one", "that one", "this page", "that page", "the page",
                  "these", "those", "them", "these pages", "those pages"):
        return None
    if folded.startswith(("the page ", "this page ", "that page ")):
        return None
    for day in ("today", "tomorrow", "yesterday", "tonight", "monday", "tuesday", "wednesday",
                "thursday", "friday", "saturday", "sunday"):
        if folded.startswith(day + "'s "):
            return None
    for word in ("next ", "last ", "previous ", "first ", "upcoming "):
        for opening in ("", "my ", "the "):
            if folded.startswith(opening + word):
                return None
    if " link to" in folded or " point to" in folded:
        return None
    return title


def links_place(words, window_course, window_section):
    """"window", ("another", code), "section" (another section) or None."""
    parts = [part for part in words.replace(",", " ").split(" ") if part]
    folded = [part.lower() for part in parts]
    course_word = section_word = None
    if folded == ["this", "section"]:
        return "section" if window_section is None else "window"
    elif len(folded) == 2 and folded[0] == "section":
        section_word = folded[1]
    elif len(folded) == 3 and folded[1] == "section":
        course_word, section_word = parts[0], folded[2]
    elif len(folded) == 4 and folded[0] == "section" and folded[2] == "of":
        course_word, section_word = parts[3], folded[1]
    elif len(folded) == 1:
        if window_course and parts[0].lower() == window_course.lower():
            return "window"
        if re.fullmatch(r"[A-Za-z]{3}[0-9][A-Za-z0-9]", parts[0]):
            return ("another", parts[0])
        return None
    else:
        return None
    if not re.fullmatch(r"[0-9]+", section_word or ""):
        return None
    if course_word is not None:
        if not window_course or course_word.lower() != window_course.lower():
            return ("another", course_word)
    if window_section is None or int(section_word) != window_section:
        return "section"
    return "window"


def unit_or_class_page(tidied):
    """Which tool "hide unit 4, day 21" and its relatives are answered with.

    Mirrors `AssistCardCommand.wholeUnitOrClassPage`, which is TWO frames read
    by different rules — and the split is the part to keep. The hide/unpublish
    arm drops commas before counting words, takes a trailing question mark off
    and allows "please" at either end (so "day21" is refused, not being a word
    this frame has). The PUBLISH arm gets none of that: a literal opening
    `"publish unit "` and a bare number, exactly as it shipped, because
    publishing is the direction that reaches students and "publish unit 4?" is
    plausibly a teacher asking. Both are pinned by
    `assert_hide_is_unpublish_matches_contract()` below, whose refused rows
    include all five of the publish spellings.
    """
    hidden = hide_or_unpublish(tidied)
    if hidden:
        return hidden
    return whole_unit_to_publish(tidied)


def whole_unit_to_publish(tidied):
    """"publish unit 5", read the way it has been read since it shipped."""
    opening = "publish unit "
    if not tidied.startswith(opening):
        return None
    rest = tidied[len(opening):].strip(" \t")
    if not rest or "," in rest or not swift_int(rest):
        return None
    return "publish_pages"


def hide_or_unpublish(tidied):
    """"hide unit 4, day 21" and "unpublish unit 4" — the widened arm."""
    frame = tidied.rstrip("?").strip()
    # SPLIT ON THE LITERAL SPACE, not on any whitespace. The Swift uses
    # `split(separator: " ")`, so "hide unit\t4" leaves it with a word
    # "unit\t4" and no match; a bare `.split()` here would accept it and the
    # mirror would be describing a matcher the app does not have. Measured:
    # a tab was one of three shapes on which this mirror and the Swift
    # disagreed before the reading was tightened.
    words = [word for word in frame.replace(",", " ").split(" ") if word]
    if words[:1] == ["please"]:
        words = words[1:]
    if words[-1:] == ["please"]:
        words = words[:-1]
    if len(words) < 3 or words[1] != "unit":
        return None
    if words[0] not in ("hide", "unpublish"):
        return None
    if not swift_int(words[2]):
        return None
    if len(words) == 3:
        return "unpublish_pages"
    if len(words) != 5 or words[3] != "day":
        return None
    if not swift_int(words[4]):
        return None
    return "unpublish_pages"


def swift_int(text):
    """Whether Swift's `Int(_:)` would read this, which is the acceptance test.

    Narrower than `[+-]?\\d+` in two ways that were MEASURED as disagreements
    rather than reasoned about — 552 inputs through this mirror and a compiled
    copy of the real matcher, 7 one-way misses. `Int` is 64-bit, so
    "unit 99999999999999999999" overflows and returns nil where a regex
    matches; and `Int` reads ASCII digits only, while Python's `\\d` is
    Unicode-aware and accepts "unit ٤" and "unit ４". Neither is reachable
    from a contract row or a probe, so no number here was ever distorted —
    but a mirror that claims a spelling cannot go unnoticed had better not
    have three of them.
    """
    if not re.fullmatch(r"[+-]?[0-9]+", text):
        return False
    try:
        value = int(text)
    except ValueError:
        return False
    return -(2 ** 63) <= value <= (2 ** 63) - 1


# What `intercepted` answers for a sentence the app asks about rather than
# answers or routes — deliberately not a tool name.
ASKED_IN_CODE = "(asked morning or evening, in code)"

# The same, for a time the app answers with the spelling to use (#277).
SAID_AS_IN_CODE = "(answered with the spelling to use, in code)"


def deploy_at_a_time(tidied):
    """Whether "deploy at 6:30 am" and its spellings are answered in code.

    Mirrors `AssistCardCommand.deployAtATime`. It answers only WHETHER, not
    which minute: the suite measures what reaches the model, and the settling
    into a whole moment happens later, in the app, against a clock.
    """
    frame = deploy_frame(tidied)
    return frame is not None and time_of_day(frame[1]) is not None


def deploy_time_asked_about(tidied):
    """Whether "deploy at 6:30" is ASKED about in code (#194, widened by #277).

    Mirrors `AssistCardCommand.morningOrEvening`: the same frame, and a time
    that is a one-digit hour 1-9 with two digits of minutes and no am or pm.
    A full stop may stand for the colon ("6.30") and a comma may follow the
    time ("6:30, please"), because both reached deploy_section 10 of 10 when
    sent to the model. Since #277 a DOTTED hour 10-12 ("10.30") is asked too,
    and so is a one-digit hour outside the part of the day the sentence names
    ("deploy at 2:30 in the evening") - see `respelling_reading`. Such a
    sentence never reaches the model, so it is not a routing probe.
    """
    frame = deploy_frame(tidied)
    if frame is not None and asked_outright(frame[1]):
        return True
    reading = respelling_reading(tidied)
    return reading is not None and reading[0] == "ask"


def deploy_time_said_as(tidied):
    """The sentence the app hands back for "deploy at 6.30 pm", "deploy at
    6:30 tonight" and their relatives (#277), else None.

    Mirrors `AssistCardCommand.timeToSayAs`. Such a sentence is answered in
    code with the spelling to use, so it never reaches the model either.
    """
    reading = respelling_reading(tidied)
    if reading is None or reading[0] != "say":
        return None
    return reading[1]


def asked_outright(time_words):
    """Mirrors `AssistCardCommand.askedOutright`: one word, a one-digit hour
    1-9 with a colon or a full stop, or a DOTTED hour 10-12; then two digits of
    minutes, and at most one comma after."""
    if len(time_words) != 1:
        return False
    return re.fullmatch(r"(?:[1-9][:.]|1[0-2]\.)[0-5][0-9],?", time_words[0]) is not None


# (words, day word, kind) - mirrors `DayPart.all` in AssistCardCommand.swift.
DAY_PARTS = [
    (["in", "the", "morning"], None, "morning"),
    (["in", "the", "afternoon"], None, "afternoon"),
    (["in", "the", "evening"], None, "evening"),
    (["this", "morning"], "today", "morning"),
    (["this", "afternoon"], "today", "afternoon"),
    (["this", "evening"], "today", "evening"),
    (["tonight"], "today", "tonight"),
    (["tomorrow", "morning"], "tomorrow", "morning"),
    (["tomorrow", "afternoon"], "tomorrow", "afternoon"),
    (["tomorrow", "evening"], "tomorrow", "evening"),
]


def day_part_holds(kind, on_the_clock):
    """Morning 0-11, afternoon 12-17, evening 17-23, tonight 17-23 and 0."""
    if kind == "morning":
        return 0 <= on_the_clock <= 11
    if kind == "afternoon":
        return 12 <= on_the_clock <= 17
    if kind == "evening":
        return 17 <= on_the_clock <= 23
    return 17 <= on_the_clock <= 23 or on_the_clock == 0


def day_part_place(kind, hour):
    """An hour 1-12 with no am or pm, on the 24-hour clock, else None."""
    if kind == "morning" and 1 <= hour <= 11:
        return hour
    if kind == "morning" and hour == 12:
        return 0
    if kind == "afternoon":
        if hour == 12:
            return 12
        if 1 <= hour <= 5:
            return hour + 12
    if kind in ("evening", "tonight") and 5 <= hour <= 11:
        return hour + 12
    if kind == "tonight" and hour == 12:
        return 0
    return None


def respelling_frame(tidied):
    """`deploy_frame`, plus a part of the day in front of "at" ("deploy
    tonight at 6:30"), moved to the end and read by `deploy_frame` itself.
    Mirrors `AssistCardCommand.respellingFrame`."""
    frame = deploy_frame(tidied)
    if frame is not None:
        return frame
    words = [word for word in tidied.rstrip("?").split(" ") if word]
    if "at" not in words:
        return None
    at = words.index("at")
    before, after = words[:at], words[at + 1:]
    for part, _, _ in DAY_PARTS:
        if len(before) > len(part) and before[-len(part):] == part:
            closing_please = after[-1:] == ["please"]
            if closing_please:
                after = after[:-1]
            rebuilt = before[:-len(part)] + ["at"] + after + part
            if closing_please:
                rebuilt.append("please")
            return deploy_frame(" ".join(rebuilt))
    return None


def respelling_reading(tidied):
    """("say", sentence) / ("ask", clock) / None. Mirrors
    `AssistCardCommand.respellingReading`, step for step."""
    frame = respelling_frame(tidied)
    if frame is None:
        return None
    frame_day, words = frame[0], list(frame[1])
    if time_of_day(words) is not None or asked_outright(words):
        return None
    comma = False
    if words and words[-1].endswith(","):
        words[-1] = words[-1][:-1]
        if not words[-1]:
            return None
        comma = True
    # "deploy at 6:30 pm tomorrow, please": the comma kept the day word from
    # the frame, and its order must not decide whether it is read.
    if comma and words and words[-1] in ("today", "tomorrow"):
        if frame_day is not None:
            return None
        frame_day = words[-1]
        words = words[:-1]
        if asked_outright(words):
            return ("ask", words[0].rstrip(",").replace(".", ":"))
    part = None
    for candidate in DAY_PARTS:
        if len(words) > len(candidate[0]) and words[-len(candidate[0]):] == candidate[0]:
            part = candidate
            words = words[:-len(candidate[0])]
            break
    if part is not None and words and words[-1].endswith(","):
        words[-1] = words[-1][:-1]
        if not words[-1]:
            return None
        comma = True
    # "today" and "tonight" agree; tonight decides.
    if part is not None and part[2] == "tonight" and frame_day == "today":
        frame_day = None
    if len(words) not in (1, 2):
        return None
    clock, meridiem = words[0], None
    if len(words) == 2:
        meridiem = words[1].replace(".", "")
        if meridiem not in ("am", "pm"):
            return None
    else:
        for ending in ("a.m.", "p.m.", "a.m", "p.m", "am", "pm"):
            if meridiem is None and clock.endswith(ending):
                meridiem = ending.replace(".", "")
                clock = clock[: -len(ending)]
    hour_text, minute_text, dotted = clock, "00", False
    separator = ":" if ":" in clock else ("." if "." in clock else None)
    if separator:
        dotted = separator == "."
        hour_text, _, minute_text = clock.partition(separator)
    elif meridiem is None and part is None:
        return None
    for text in (hour_text, minute_text):
        if not text or any(character not in "0123456789" for character in text):
            return None
    if len(hour_text) > 2 or len(minute_text) != 2:
        return None
    hour, minute = int(hour_text), int(minute_text)
    if minute > 59:
        return None
    if not (dotted or comma or part):
        return None
    day = frame_day
    if part is not None and part[1] is not None:
        if day is not None and day != part[1]:
            return None
        day = part[1]
    if meridiem is not None:
        if not 1 <= hour <= 12:
            return None
        on_the_clock = hour
        if meridiem == "pm" and hour != 12:
            on_the_clock = hour + 12
        if meridiem == "am" and hour == 12:
            on_the_clock = 0
        if part is not None and not day_part_holds(part[2], on_the_clock):
            return None
    elif part is not None:
        if len(hour_text) == 2 and (hour_text.startswith("0") or hour >= 13):
            if hour > 23 or not day_part_holds(part[2], hour):
                return None
            on_the_clock = hour
        else:
            on_the_clock = day_part_place(part[2], hour)
            if on_the_clock is None:
                if len(hour_text) != 1 or hour < 1:
                    return None
                return ("ask", "%s:%s" % (hour_text, minute_text))
    else:
        if len(hour_text) != 2 or hour > 23:
            return None
        on_the_clock = hour
    if part is not None and part[2] == "tonight" and on_the_clock < 12:
        if frame_day is not None:
            return None
        day = None
    twelve = on_the_clock % 12 or 12
    half = "am" if on_the_clock < 12 else "pm"
    return ("say", "deploy %sat %d:%s %s" % (day + " " if day else "", twelve, minute_text, half))


def deploy_frame(tidied):
    """(day word or None, the time's words) for "[please] deploy [it|this
    section] [today|tomorrow] at <time> [today|tomorrow] [please]", else None.

    Mirrors `AssistCardCommand.deployFrame`, which both of the above read.
    """
    # Split on the literal space, as the Swift does: `.split()` would also
    # split on a tab or a no-break space, which the Swift keeps inside a word.
    frame = tidied.rstrip("?")
    words = [word for word in frame.split(" ") if word]
    if words[:1] == ["please"]:
        words = words[1:]
    if words[-1:] == ["please"]:
        words = words[:-1]
    if words[:1] != ["deploy"]:
        return None
    words = words[1:]
    if words[:1] == ["it"]:
        words = words[1:]
    elif words[:2] == ["this", "section"]:
        words = words[2:]
    day = None
    if words[:1] and words[0] in ("today", "tomorrow"):
        day = words[0]
        words = words[1:]
    if words[:1] != ["at"]:
        return None
    words = words[1:]
    if words[-1:] and words[-1] in ("today", "tomorrow"):
        if day is not None:
            return None
        day = words[-1]
        words = words[:-1]
    return (day, words)


def time_of_day(words):
    """"6:30 am", "7pm", "18:30", "noon", "midnight" -> "HH:MM", else None."""
    if len(words) not in (1, 2):
        return None
    if len(words) == 1:
        if words[0] == "noon":
            return "12:00"
        if words[0] == "midnight":
            return "00:00"
    clock, meridiem = words[0], None
    if len(words) == 2:
        meridiem = words[1].replace(".", "")
        if meridiem not in ("am", "pm"):
            return None
    else:
        for ending in ("a.m.", "p.m.", "a.m", "p.m", "am", "pm"):
            if meridiem is None and clock.endswith(ending):
                meridiem = ending.replace(".", "")
                clock = clock[: -len(ending)]
    hour_text, minute_text = clock, "00"
    if ":" in clock:
        hour_text, _, minute_text = clock.partition(":")
    elif meridiem is None:
        return None
    for text in (hour_text, minute_text):
        if not text or any(character not in "0123456789" for character in text):
            return None
    if len(hour_text) > 2 or len(minute_text) != 2:
        return None
    hour, minute = int(hour_text), int(minute_text)
    if minute > 59:
        return None
    if meridiem is None:
        if len(hour_text) != 2 or hour > 23:
            return None
        return "%02d:%s" % (hour, minute_text)
    if not 1 <= hour <= 12:
        return None
    if meridiem == "pm" and hour != 12:
        hour += 12
    if meridiem == "am" and hour == 12:
        hour = 0
    return "%02d:%s" % (hour, minute_text)


def assert_deploy_at_a_time_matches_contract():
    """Fail the run if the guard above has drifted from the contract's rows.

    The shelf list is checked against the Swift for exactly this reason, and
    this guard needs it more: `AssistCardCommand` is the truth and nothing here
    can import it, so the contract's own accepted and refused rows are what
    stand in for it. A miss in either direction is a number nobody should quote
    — an accepted row that is not intercepted here gets SENT to the model and
    scored as routing for a sentence the app answers itself, and a refused row
    that is intercepted hides a probe that genuinely does route.
    """
    with open(ROOT / "contracts" / "assist-cases.json", encoding="utf-8") as handle:
        family = json.load(handle).get("deployAtATime")
    if not family:
        sys.exit("contracts/assist-cases.json carries no deployAtATime rows to check against.")
    wrong = []
    for row in family["accepted"]:
        if intercepted(row["input"]) != "schedule_deploy":
            wrong.append("accepted and NOT intercepted: %r" % row["input"])
    for row in family["refused"]:
        if intercepted(row["input"]) in ("schedule_deploy", ASKED_IN_CODE, SAID_AS_IN_CODE):
            wrong.append("refused and intercepted anyway: %r" % row["input"])
    for row in family.get("asked", []):
        if intercepted(row["input"]) != ASKED_IN_CODE:
            wrong.append("asked about in code and NOT intercepted: %r" % row["input"])
    for row in family.get("sayItAs", []):
        tidied = row["input"].strip().strip(".!").lower()
        if intercepted(row["input"]) != SAID_AS_IN_CODE:
            wrong.append("answered with a spelling in code and NOT intercepted: %r" % row["input"])
        elif deploy_time_said_as(tidied) != row["expectSay"]:
            wrong.append("answered with %r, the contract says %r: %r"
                         % (deploy_time_said_as(tidied), row["expectSay"], row["input"]))
    if wrong:
        sys.exit(
            "deploy_at_a_time() no longer agrees with contracts/assist-cases.json "
            "-> deployAtATime:\n  %s\nFix it before quoting a number from this suite."
            % "\n  ".join(wrong)
        )
    return (len(family["accepted"]) + len(family.get("asked", []))
            + len(family.get("sayItAs", [])) + len(family["refused"]))


def assert_hide_is_unpublish_matches_contract():
    """Fail the run if the hide/unpublish frame has drifted from the contract.

    The same argument as the function above, and the same cost of skipping it.
    This family matters more than most here because one of its rows is the
    shelf's own "Unpublish Unit 2, Day 3": an accepted row this guard missed
    would be SENT to the model and scored as a routing result for a sentence
    the app answers itself, which is exactly the number nobody should quote.
    Each accepted row carries the tool it must reach, so the verb gating is
    checked too — `publish unit 4, day 3` is a REFUSED row, and a guard that
    let it through would be describing a frame the app does not have.
    """
    with open(ROOT / "contracts" / "assist-cases.json", encoding="utf-8") as handle:
        family = json.load(handle).get("hideIsUnpublish")
    if not family:
        sys.exit("contracts/assist-cases.json carries no hideIsUnpublish rows to check against.")
    wrong = []
    for row in family["accepted"]:
        reached = intercepted(row["input"])
        if reached != row["expectTool"]:
            wrong.append("accepted as %s and this guard says %r: %r"
                         % (row["expectTool"], reached, row["input"]))
    for row in family["refused"]:
        reached = intercepted(row["input"])
        if reached in ("unpublish_pages", "publish_pages"):
            wrong.append("refused and intercepted as %s anyway: %r" % (reached, row["input"]))
    if wrong:
        sys.exit(
            "unit_or_class_page() no longer agrees with contracts/assist-cases.json "
            "-> hideIsUnpublish:\n  %s\nFix it before quoting a number from this suite."
            % "\n  ".join(wrong)
        )
    return len(family["accepted"]) + len(family["refused"])


def assert_links_question_matches_contract():
    """Fail the run if the links family (#167) has drifted from the contract.

    The same argument as the two functions above. The #167 probe itself —
    `What does "Unit 2, Day 3" in EXC2O section 1 link to?` — is answered in
    code in its own window, so a guard that missed a row would send it to the
    model and score a routing result for a sentence the app never routes.
    """
    with open(ROOT / "contracts" / "assist-cases.json", encoding="utf-8") as handle:
        family = json.load(handle).get("linksQuestion")
    if not family:
        sys.exit("contracts/assist-cases.json carries no linksQuestion rows to check against.")
    course, section = family["window"]["course"], family["window"]["section"]
    wrong = []
    for row in family["accepted"]:
        if intercepted(row["input"], course, section) != "read_page":
            wrong.append("accepted and NOT intercepted: %r" % row["input"])
    for row in family["anotherCourse"]:
        if links_question(row["input"], course, section) != ("another", row["expectCourse"]):
            wrong.append("another course and not refused naming %s: %r" % (row["expectCourse"], row["input"]))
    for row in family["refused"]:
        if intercepted(row["input"], course, section) in ("read_page", REFUSED_IN_CODE):
            wrong.append("refused and intercepted anyway: %r" % row["input"])
    if wrong:
        sys.exit(
            "links_question() no longer agrees with contracts/assist-cases.json "
            "-> linksQuestion:\n  %s\nFix it before quoting a number from this suite."
            % "\n  ".join(wrong)
        )
    return len(family["accepted"]) + len(family["anotherCourse"]) + len(family["refused"])


def ask(prompt):
    payload = {
        "model": "local", "temperature": TEMPERATURE,
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": prompt}],
        "tools": TOOLS,
    }
    if APP_BODY:
        # What AssistModelClient sends, and nothing else: tool_choice named
        # rather than left to the server's default, and the cap read out of
        # the Swift — or none at all under --uncapped, which is the body the
        # mac sent before #166.
        payload["tool_choice"] = "auto"
        payload["stream"] = False
        if not UNCAPPED:
            payload["max_tokens"] = APP_CAP
    else:
        payload["max_tokens"] = 256
    request = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"})
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError:
        return "__MALFORMED__", {}, int((time.time() - started) * 1000), 0, "http-error"
    elapsed = int((time.time() - started) * 1000)
    # The completion-token count is the ONLY honest check that thinking is
    # off: llama.cpp parses a <think> block out of the content, so a slow,
    # 500-token answer reads as clean. Tens of tokens is right; hundreds is
    # the flag being ignored.
    spent = (data.get("usage") or {}).get("completion_tokens", 0)
    reason = data["choices"][0].get("finish_reason", "")
    message = data["choices"][0]["message"]
    calls = message.get("tool_calls") or []
    if not calls:
        return None, {}, elapsed, spent, reason
    call = calls[0]["function"]
    try:
        arguments = json.loads(call["arguments"])
    except Exception:
        # NOT the same as "no arguments", and this file used to conflate the
        # two. A generation that runs out of room mid-JSON arrives as a tool
        # call whose arguments are a truncated string; swallowing that as {}
        # reported "0 malformed" while an unusable call was reaching the app.
        # Measured 2026-09-18 on the 1.5B with the app's own body.
        arguments = {"__unparsed__": call["arguments"][:60]}
    return call["name"], arguments, elapsed, spent, reason


# Which probes the app never sends. Computed rather than listed, so a
# phrasing added to the card table shows up here on the next run.
CARD_LABELS = [probe for _, _, probe, _ in PROMISED]
# The one parsed family this guard cannot describe with a one-line regex is
# pinned against the contract before anything is measured.
DEPLOY_ROWS_CHECKED = assert_deploy_at_a_time_matches_contract()
HIDE_ROWS_CHECKED = assert_hide_is_unpublish_matches_contract()
LINKS_ROWS_CHECKED = assert_links_question_matches_contract()
INTERCEPTED = {}
for acceptable, prompt, probe, needs_date in CASES:
    tool = intercepted(prompt.replace("EXC2O", COURSE).replace("exc2o", COURSE.lower()),
                       COURSE, SECTION)
    if tool is not None:
        INTERCEPTED[probe] = tool

# Read once, and only when it is going to be sent: an --uncapped arm is
# reproducible from a checkout where the constant does not exist yet.
APP_CAP = swift_most_tokens_per_reply() if (APP_BODY and not UNCAPPED) else None

print("### date-appended=%s date-prepended=%s real-course=%s" % (
    DATE_APPENDED, DATE_PREPENDED, REAL_COURSE))
print("### prompt=%s temperature=%s app-body=%s trials=%s course=%s" % (
    PROMPT_FORM, TEMPERATURE, APP_BODY, TRIALS, COURSE))
print("### max_tokens=%s (%s)" % (
    "none" if (APP_BODY and UNCAPPED) else (APP_CAP if APP_BODY else 256),
    "--uncapped: the body the mac sent before #166" if (APP_BODY and UNCAPPED)
    else ("read from %s" % CLIENT_SWIFT if APP_BODY else "this suite's historic cap")))
print("### em-dashes in the shipped literal, folded for the hyphen form: %d"
      % assert_forms_agree())
if MAC_SHELF_ONLY:
    print("### mac shelf: %d phrasings, checked against %s"
          % (assert_shelf_is_current(), SHELF_SWIFT))
print("### deploy-at-a-time guard agrees with %d contract rows"
      % DEPLOY_ROWS_CHECKED)
print("### hide-is-unpublish guard agrees with %d contract rows"
      % HIDE_ROWS_CHECKED)
print("### links-question guard agrees with %d contract rows"
      % LINKS_ROWS_CHECKED)
print("### intercepted in code before the model (%d of %d probes): %s" % (
    len(INTERCEPTED), len(CASES),
    ", ".join("%s -> %s" % (p, t) for p, t in INTERCEPTED.items())))
if INTERCEPT_ONLY:
    sys.exit(0)

SYSTEM = system_prompt(PROMPT_FORM, COURSE, SECTION)

right = total = malformed = type_problems = wrong_writes = 0
inversions, narrow_inversions, fabricated, wrong_courses = [], [], [], []
# What the app would have dealt with before the call ran — counted apart,
# because a suite that reports them as faults is stricter than the product a
# teacher uses. `boundToThisSection` takes the SECTION back and
# `withTheDaySettled` settles a relative date, so those never reach a tool.
# A wrong COURSE is no longer put right: since 2026-09-19 (issue #202) the
# agent REFUSES that turn and says so, because rewriting it published this
# window's class and reported success. It is still counted here rather than
# with the faults, for the same reason as the others — nothing runs — but the
# teacher sees a refusal rather than the request they meant.
app_corrected = []
# A call whose arguments JSON did not parse, and a turn the server stopped
# because it ran out of room rather than because the model had finished.
truncated, ran_long = [], []
chosen = {}          # probe -> {tool: count}
scored = {}          # probe -> hits
spent_tokens, latencies = [], []
print("%-30s %-24s %-5s %-6s %s" % ("probe", "chose", "ok", "ms", "arguments"))
print("-" * 118)
for acceptable, prompt, probe, needs_date in CASES:
    text = prompt.replace("EXC2O", COURSE).replace("exc2o", COURSE.lower())
    if DATE_APPENDED:
        text = "%s %s" % (text, DATELINE)
    elif DATE_PREPENDED:
        text = "%s %s" % (DATELINE, text)
    chosen.setdefault(probe, {})
    scored.setdefault(probe, 0)
    for _ in range(TRIALS):
        name, arguments, ms, spent, reason = ask(text)
        total += 1
        spent_tokens.append(spent)
        latencies.append(ms)
        label = name or "(declined)"
        chosen[probe][label] = chosen[probe].get(label, 0) + 1
        if name == "__MALFORMED__":
            malformed += 1
        if "__unparsed__" in arguments:
            malformed += 1
            truncated.append((probe, name, spent, ms))
        if reason == "length":
            ran_long.append((probe, name, spent, ms))
        ok = name in acceptable
        if ok:
            right += 1
            scored[probe] += 1
        # A hide request answered with a publish tool is the failure the
        # separate verbs exist to prevent. Every POLARITY probe counts —
        # the probes whose only right answer is an unpublish. The old rule
        # matched the LABEL ("hide" in it), which missed "card: unpublish by
        # name" and "no course named: hide"; both are kept so the older
        # results files stay comparable.
        polarity = set(acceptable) <= {"plan_unpublish_pages", "unpublish_pages"}
        if name in PUBLISHERS and polarity:
            inversions.append((probe, name, arguments))
        if name in PUBLISHERS and (probe.startswith("hide") or "HIDE" in probe):
            narrow_inversions.append((probe, name, arguments))
        if not ok and name in WRITES:
            wrong_writes += 1
        if needs_date and name in ("publish_class_on", "plan_publish_class_on"):
            said = arguments.get("date", "") or arguments.get("when", "")
            if said in ("tomorrow", "today", "yesterday"):
                app_corrected.append((probe, "relative date %r settled by the app" % said))
            elif said != TOMORROW.isoformat():
                fabricated.append((probe, said))
        if "course" in arguments and arguments["course"] != COURSE:
            wrong_courses.append((probe, arguments["course"]))
            app_corrected.append((probe, "course %r refused by the app" % arguments["course"]))
        for key, value in arguments.items():
            if key == "section" and not isinstance(value, int):
                type_problems += 1
                app_corrected.append((probe, "section %r retyped by the app" % value))
            if key == "includeLinked" and not isinstance(value, bool):
                type_problems += 1
        print("%-30s %-24s %-5s %-6s %s" % (
            probe[:29], name or "(declined)", "OK" if ok else "MISS", ms,
            json.dumps(arguments)[:50]))
print("-" * 118)


def subtotal(labels):
    hits = sum(scored[probe] for probe in labels)
    return "%d/%d" % (hits, len(labels) * TRIALS)


windows_18 = [probe for _, _, probe, _ in CASES if probe not in CARD_LABELS]
seen_by_model = [probe for probe in scored if probe not in INTERCEPTED]
cards_seen = [probe for probe in CARD_LABELS if probe not in INTERCEPTED]

print("all probes:            %s (%.0f%%)" % (
    subtotal(list(scored)), 100.0 * right / total))
if seen_by_model:
    print("the %d the model SEES:  %s (%.0f%%)   — the rest are answered in code" % (
        len(seen_by_model), subtotal(seen_by_model),
        100.0 * sum(scored[p] for p in seen_by_model) / (len(seen_by_model) * TRIALS)))
if MAC_SHELF_ONLY:
    # Neither subtotal means anything here: both are defined against WINDOWS'
    # eleven, and this run is the mac's own shelf.
    print("(mac shelf run — the Windows-comparable and promise-card subtotals "
          "do not apply and are not printed)")
else:
    print("Windows-comparable 18: %s" % subtotal(windows_18))
    print("promise-card 11 (WINDOWS' ExampleRequests): %s" % subtotal(CARD_LABELS))
    print("promise-card, the %d the model sees: %s" % (len(cards_seen), subtotal(cards_seen)))
print("polarity inversions (all polarity probes, incl. plan_*): %d" % len(inversions))
for probe, name, arguments in inversions:
    print("   %s -> %s %s" % (probe, name, json.dumps(arguments)))
print("   ...of which the OLD label-matching counter would have seen: %d" % len(narrow_inversions))
print("misses that were a WRITE (the dangerous kind): %d" % wrong_writes)
print("responses needing type coercion: %d" % type_problems)
print("malformed tool calls: %d   (HTTP errors, plus arguments that did not parse)" % malformed)
print("tool calls whose arguments were TRUNCATED mid-JSON: %d" % len(truncated))
for probe, name, spent, ms in sorted(set(truncated)):
    print("   %s -> %s, %d completion tokens, %d ms" % (probe, name, spent, ms))
print("turns the server ended on 'length' rather than on the model finishing: %d" % len(ran_long))
for probe, name, spent, ms in sorted(set(ran_long)):
    print("   %s -> %s, %d completion tokens, %d ms" % (probe, name, spent, ms))
print("'tomorrow' dates not equal to %s: %d" % (TOMORROW.isoformat(), len(fabricated)))
for probe, date in fabricated:
    print("   %s -> date=%r" % (probe, date))
print("course arguments not equal to %s: %d" % (COURSE, len(wrong_courses)))
for probe, course in wrong_courses:
    print("   %s -> course=%r" % (probe, course))
print("argument faults the APP would have corrected before running: %d" % len(app_corrected))
for probe, what in sorted(set(app_corrected)):
    print("   %s -> %s" % (probe, what))
spent_tokens.sort()
latencies.sort()
print("completion tokens: median %d, max %d   (thinking off is tens, not hundreds)"
      % (spent_tokens[len(spent_tokens) // 2], spent_tokens[-1]))
print("turn latency: median %d ms, max %d ms" % (
    latencies[len(latencies) // 2], latencies[-1]))
print()
print("%-30s %-6s %s" % ("probe", "score", "tools chosen over %d trials" % TRIALS))
print("-" * 110)
for _, _, probe, _ in CASES:
    order = sorted(chosen[probe].items(), key=lambda pair: -pair[1])
    spread = ", ".join("%dx %s" % (count, tool) for tool, count in order)
    flag = "" if scored[probe] == TRIALS else "  [MISS]"
    seen = "" if probe not in INTERCEPTED else "  (answered in code, not routed)"
    print("%-30s %-6s %s%s%s" % (
        probe[:29], "%d/%d" % (scored[probe], TRIALS), spread, flag, seen))
