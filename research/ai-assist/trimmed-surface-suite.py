#!/usr/bin/env python3
"""The TRIMMED surface (AssistAgent.NarrowToLocal, 15 tools), measured.

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

Usage:
  python trimmed-surface-suite.py TOOLS.json [trials] [--date-appended]
         [--date-prepended] [--real-course] [--port 8099]

TOOLS.json is the narrowed OpenAI-shaped surface - produce it with
dump-tools.ps1 (raw tools/list) piped through narrow-tools.py.
"""
import datetime
import json
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

# AssistAgent's system prompt, verbatim, for EXC2O section 1. Updated
# 2026-08-14 when the approval gate narrowed to deploys only (plan-first-and-
# wait removed); the 94% in trimmed-surface-results.txt was measured with the
# PREVIOUS wording and has not been re-run against this one.
#
# Updated again 2026-08-24 with the two sentences that fixed the "undo
# over-salient" and "hide inversion" clusters flagged in TODO.md — see
# conversational-residue-results.txt. Keep this in sync with
# AssistAgent.cs / AssistAgent.swift's SystemPrompt, by hand; nothing pins
# the three together automatically.
SYSTEM = (
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

WRITES = {"publish_class_on", "publish_pages", "unpublish_pages", "deploy_section",
          "schedule_deploy", "cancel_scheduled_deploy", "undo_last_change"}
PUBLISHERS = {"publish_class_on", "plan_publish_class_on", "publish_pages", "plan_publish_pages"}

# (acceptable tool names, prompt, probe label, needs_date)
# None in the tuple means declining is acceptable. "EXC2O" in a prompt is
# replaced by --course at run time.
#
# THE PROMISE CARD, verbatim. These eleven are what the assistant window
# tells a teacher it is good at (AssistAgent.ExampleRequests), so they are
# measured exactly as written — no course named, because the window names
# it in the system prompt. "Rebuild the preview" never reaches the model in
# the app (the fast path answers it); it is measured anyway for the
# bring-your-own-assistant path.
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


def ask(prompt):
    payload = {
        "model": "local", "temperature": 0.1, "max_tokens": 256,
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": prompt}],
        "tools": TOOLS,
    }
    request = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"})
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError:
        return "__MALFORMED__", {}, int((time.time() - started) * 1000)
    elapsed = int((time.time() - started) * 1000)
    message = data["choices"][0]["message"]
    calls = message.get("tool_calls") or []
    if not calls:
        return None, {}, elapsed
    call = calls[0]["function"]
    try:
        arguments = json.loads(call["arguments"])
    except Exception:
        arguments = {}
    return call["name"], arguments, elapsed


right = total = malformed = type_problems = wrong_writes = 0
inversions, fabricated, wrong_courses = [], [], []
print("### date-appended=%s date-prepended=%s real-course=%s" % (
    DATE_APPENDED, DATE_PREPENDED, REAL_COURSE))
print("%-30s %-24s %-5s %-6s %s" % ("probe", "chose", "ok", "ms", "arguments"))
print("-" * 118)
for acceptable, prompt, probe, needs_date in CASES:
    text = prompt.replace("EXC2O", COURSE).replace("exc2o", COURSE.lower())
    if DATE_APPENDED:
        text = "%s %s" % (text, DATELINE)
    elif DATE_PREPENDED:
        text = "%s %s" % (DATELINE, text)
    for _ in range(TRIALS):
        name, arguments, ms = ask(text)
        total += 1
        if name == "__MALFORMED__":
            malformed += 1
        ok = name in acceptable
        if ok:
            right += 1
        # A hide request answered with a publish tool is the failure the
        # separate verbs exist to prevent.
        if name in PUBLISHERS and (probe.startswith("hide") or "HIDE" in probe):
            inversions.append((probe, name, arguments))
        if not ok and name in WRITES:
            wrong_writes += 1
        if needs_date and name in ("publish_class_on", "plan_publish_class_on"):
            if arguments.get("date", "") != TOMORROW.isoformat():
                fabricated.append((probe, arguments.get("date", "")))
        if "course" in arguments and arguments["course"] != COURSE:
            wrong_courses.append((probe, arguments["course"]))
        for key, value in arguments.items():
            if key == "section" and not isinstance(value, int):
                type_problems += 1
            if key == "includeLinked" and not isinstance(value, bool):
                type_problems += 1
        print("%-30s %-24s %-5s %-6s %s" % (
            probe[:29], name or "(declined)", "OK" if ok else "MISS", ms,
            json.dumps(arguments)[:50]))
print("-" * 118)
print("routing accuracy: %d/%d (%.0f%%)" % (right, total, 100.0 * right / total))
print("misses that were a WRITE (the dangerous kind): %d" % wrong_writes)
print("polarity inversions (hide answered with publish): %d" % len(inversions))
for probe, name, arguments in inversions:
    print("   %s -> %s %s" % (probe, name, json.dumps(arguments)))
print("responses needing type coercion: %d" % type_problems)
print("malformed tool calls: %d" % malformed)
print("'tomorrow' dates not equal to %s: %d" % (TOMORROW.isoformat(), len(fabricated)))
for probe, date in fabricated:
    print("   %s -> date=%r" % (probe, date))
print("course arguments not equal to %s: %d" % (COURSE, len(wrong_courses)))
for probe, course in wrong_courses:
    print("   %s -> course=%r" % (probe, course))
