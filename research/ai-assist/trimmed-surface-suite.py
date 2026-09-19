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
                     tool_choice "auto", no max_tokens. Greedy decoding makes
                     repeated trials near-deterministic, so a trial count is
                     not a failure rate — see the note in the report.
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
TEMPERATURE = float(args[args.index("--temperature") + 1]) if "--temperature" in args else 0.1
if APP_BODY:
    # AssistModelClient.reply: temperature 0, tool_choice auto, no max_tokens.
    TEMPERATURE = 0.0
INTERCEPT_ONLY = "--intercept-only" in args
# The MAC's shelf instead of Windows' ExampleRequests — see MAC_SHELF below.
MAC_SHELF_ONLY = "--mac-shelf" in args

ROOT = pathlib.Path(__file__).resolve().parents[2]
AGENT_SWIFT = "mac-app/QuartzTeachers/Models/Assist/AssistAgent.swift"
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
# them, because the window names it in the system prompt. Five of them never
# reach the model in the app; they are measured anyway, for the
# bring-your-own-assistant path, and the run reports them separately.
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


def intercepted(message):
    """The tool `AssistCardCommand.matching` would run without the model.

    A probe the app answers in code measures nothing about routing, so the
    suite has to know which ones those are — and it has to know it from the
    CONTRACT rather than from a hand-copied list, which is how
    `narrow-tools.py` went stale for three days without anyone noticing.
    Same tidying as the Swift: trim, strip leading and trailing `.` and `!`,
    lower-case, then EQUALITY — never a substring. Then the six parsed
    families, which cannot be listed because the number, title or TIME in them
    is unbounded. The sixth — "deploy at <time>" — is checked against the
    contract's own accepted and refused rows before any probe is sent, by
    `assert_deploy_at_a_time_matches_contract()` below: this guard went one
    family stale once already, and a stale guard scores a routing result for a
    sentence the app never routes.
    """
    with open(ROOT / "contracts" / "assist-cases.json", encoding="utf-8") as handle:
        phrasings = json.load(handle)["cardPhrasings"]["matches"]
    tidied = message.strip().strip(".!").lower()
    for entry in phrasings:
        if tidied == entry["phrasing"]:
            return entry["tool"]
    if re.fullmatch(r"(un)?publish unit \d+", tidied):
        return "unpublish_pages" if tidied.startswith("un") else "publish_pages"
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
    if re.fullmatch(r"duplicate .+ as (my next class|the next class|my next lesson)", tidied):
        return "add_next_class"
    return None


def deploy_at_a_time(tidied):
    """Whether "deploy at 6:30 am" and its spellings are answered in code.

    Mirrors `AssistCardCommand.deployAtATime`. It answers only WHETHER, not
    which minute: the suite measures what reaches the model, and the settling
    into a whole moment happens later, in the app, against a clock.
    """
    frame = tidied.rstrip("?").strip()
    words = frame.split()
    if words[:1] == ["please"]:
        words = words[1:]
    if words[-1:] == ["please"]:
        words = words[:-1]
    if words[:1] != ["deploy"]:
        return False
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
        return False
    words = words[1:]
    if words[-1:] and words[-1] in ("today", "tomorrow"):
        if day is not None:
            return False
        words = words[:-1]
    return time_of_day(words) is not None


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
        if intercepted(row["input"]) == "schedule_deploy":
            wrong.append("refused and intercepted anyway: %r" % row["input"])
    if wrong:
        sys.exit(
            "deploy_at_a_time() no longer agrees with contracts/assist-cases.json "
            "-> deployAtATime:\n  %s\nFix it before quoting a number from this suite."
            % "\n  ".join(wrong)
        )
    return len(family["accepted"]) + len(family["refused"])


def ask(prompt):
    payload = {
        "model": "local", "temperature": TEMPERATURE,
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": prompt}],
        "tools": TOOLS,
    }
    if APP_BODY:
        # What AssistModelClient sends, and nothing else: no max_tokens, and
        # tool_choice named rather than left to the server's default.
        payload["tool_choice"] = "auto"
        payload["stream"] = False
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
INTERCEPTED = {}
for acceptable, prompt, probe, needs_date in CASES:
    tool = intercepted(prompt.replace("EXC2O", COURSE).replace("exc2o", COURSE.lower()))
    if tool is not None:
        INTERCEPTED[probe] = tool

print("### date-appended=%s date-prepended=%s real-course=%s" % (
    DATE_APPENDED, DATE_PREPENDED, REAL_COURSE))
print("### prompt=%s temperature=%s app-body=%s trials=%s course=%s" % (
    PROMPT_FORM, TEMPERATURE, APP_BODY, TRIALS, COURSE))
print("### em-dashes in the shipped literal, folded for the hyphen form: %d"
      % assert_forms_agree())
if MAC_SHELF_ONLY:
    print("### mac shelf: %d phrasings, checked against %s"
          % (assert_shelf_is_current(), SHELF_SWIFT))
print("### deploy-at-a-time guard agrees with %d contract rows"
      % DEPLOY_ROWS_CHECKED)
print("### intercepted in code before the model (%d of %d probes): %s" % (
    len(INTERCEPTED), len(CASES),
    ", ".join("%s -> %s" % (p, t) for p, t in INTERCEPTED.items())))
if INTERCEPT_ONLY:
    sys.exit(0)

SYSTEM = system_prompt(PROMPT_FORM, COURSE, SECTION)

right = total = malformed = type_problems = wrong_writes = 0
inversions, narrow_inversions, fabricated, wrong_courses = [], [], [], []
# What `boundToThisSection` and `withTheDaySettled` would have put right
# before the call ran — counted apart, because a suite that reports them as
# faults is stricter than the product a teacher uses.
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
            app_corrected.append((probe, "course %r rewritten by the app" % arguments["course"]))
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
