#!/usr/bin/env python3
"""
What the four missing TEACHERS SAY: clauses are worth, measured on Windows.

`AssistToolSurface`'s own comment says the trigger phrasings "are what took
routing from 69% to 91%", and `AssistAgent.Briefly()` puts that clause FIRST in
the description the local model reads. Windows' `PlantoirTools` was missing the
clause entirely on four tools; two of those four - `add_next_class` and
`read_remembered_timetable` - are in `AssistAgent.ForTheLocalModel`, so adding
their ten phrasings changes what the router reads. That is a routing change, and
a routing change nobody measured is one nobody chose.

So: the same probes, the same server, run once BEFORE the clauses are added and
once AFTER.

  * The ten UNDER TEST are the mac's own phrasings for those two tools, said
    bare - no course, no section - because the app's system prompt already names
    both and that is how a teacher types.
  * The CONTROLS are one probe per other tool the local model can see, plus the
    two declines and the undo/unpublish residue case. They are here because
    adding a sentence has broken unrelated probes before: one clarifying
    sentence in `publish_pages` took a promise-card score from 110/110 to
    90/110. A gain on the ten that costs more than it buys on the fifteen is
    not a gain.

Every probe here really does reach the model, and checking that is harder than
it looks: `AssistAgent.Say` runs THREE interception layers before the model is
consulted, not one.

  1. `PreviewAskedForPlainly` - the thirteen sentences in `PreviewCommands`
     (`AssistAgent.cs:825`), answered without a model at all.
  2. `AssistCardCommand.Matching` - `FixedShapes`, plus its `WholeUnit`,
     `MoreDays` and `DuplicateClass` parsers.
  3. Four inline regexes in `AssistAgent.CardCommand` itself
     (`AssistAgent.cs:590-601`): publish/unpublish "and everything it links
     to", "publish unit N, day M", "what would publishing X change", and
     "deploy tomorrow's class at H:MM am/pm".

The first draft of this file checked only layer 2 and lost three controls to
the other two - "Show me the preview", "Publish Unit 2, Day 3" and "Deploy
tomorrow's class at 6:30 AM" are all answered without the model, so measuring
the router on them measures nothing. Their replacements below are the same
intent said a way the app really does route.

    python research/ai-assist/narrow-tools.py tools.json narrowed.json EXC2O
    python research/ai-assist/teachers-say-suite.py 8099 5 narrowed.json

The system prompt is `AssistAgent.SystemPrompt("EXC2O", 1)` verbatim, the
request is shaped like `LocalModel`'s (temperature 0, max_tokens 512), and the
DATELINE is appended to every prompt exactly as `AssistAgent.Say` appends it.
That last one is not a detail: `trimmed-surface-results.txt` records the same
line costing fifteen points of accuracy when PREPENDED instead, and appended
is what ships. A score taken without it is a score for a request the app never
sends.
"""
import datetime
import json
import sys
import time
import urllib.request
import urllib.error

PORT = sys.argv[1] if len(sys.argv) > 1 else "8099"
TRIALS = int(sys.argv[2]) if len(sys.argv) > 2 else 10
TOOLS_PATH = sys.argv[3] if len(sys.argv) > 3 else "narrowed.json"
ENDPOINT = "http://127.0.0.1:%s/v1/chat/completions" % PORT

COURSE = "EXC2O"
SECTION = 1

# MIRROR of AssistAgent.Say: `_dateline = $" (Today is {today:yyyy-MM-dd}, a
# {today.DayOfWeek}.)"`, appended to every user message the model sees.
# The weekday is spelled out rather than taken from strftime("%A"), which
# follows LC_TIME; C#'s DayOfWeek.ToString() is invariant English, and a
# harness that stops mirroring the app under a different locale is the exact
# fault this suite exists to avoid.
WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
            "Saturday", "Sunday")
TODAY = datetime.date.today()
DATELINE = " (Today is %s, a %s.)" % (TODAY.isoformat(), WEEKDAYS[TODAY.weekday()])

with open(TOOLS_PATH, encoding="utf-8-sig") as handle:
    TOOLS = json.load(handle)

# Verbatim from AssistAgent.SystemPrompt(courseCode, section).
SYSTEM = (
    "You are Plantoir's assistant, helping a teacher with %s section %d. " % (COURSE, SECTION) +
    "Choose exactly one tool at a time and fill in its arguments from what the teacher said. "
    "Publishing and unpublishing are safe to do straight away — every change is backed up "
    "and undo_last_change takes it back — so do what was asked without asking permission first. "
    "Never guess a course, a section, a page title "
    "or a date — if you are not certain, look it up or ask. "
    "If no tool fits, say so plainly instead of inventing one. "
    "undo_last_change reverses only the assistant's own most recent action — a "
    "teacher describing something THEY did earlier, even calling it a mistake, is "
    "asking to publish or unpublish, not to undo. There is no tool to delete, "
    "remove or rename a page or a folder — if asked for that, say so plainly "
    "instead of choosing a tool that does something else.\n"
    "PUBLISHING a page decides whether students can see it in the site. "
    "DEPLOYING sends the whole site to the web. They are different acts. "
    "After a change, Plantoir opens the preview by itself so the teacher can look it over. "
    "Do not offer to deploy unless they ask; when they do ask, say plainly that "
    "deploying puts the change in front of students immediately and that reviewing "
    "the preview first is the safer order — then do as they decide."
)

# (group, acceptable tool names, prompt, label). None means declining is right.
CASES = [
    # ---- Under test: add_next_class, the mac's six phrasings.
    ("test", ("add_next_class",), "Add an entry for the next class", "next: an entry"),
    ("test", ("add_next_class",), "Add tomorrow's class page", "next: tomorrow's page"),
    ("test", ("add_next_class",), "Start the next class", "next: start"),
    ("test", ("add_next_class",), "Add the next class", "next: add"),
    ("test", ("add_next_class",), "Make a page for our next class", "next: make a page"),
    ("test", ("add_next_class",), "Set up next day's lesson", "next: next day's lesson"),

    # ---- Under test: read_remembered_timetable, the mac's four.
    ("test", ("read_remembered_timetable",), "When does this class meet?", "dates: when meet"),
    ("test", ("read_remembered_timetable",), "What dates do you have for us?", "dates: what dates"),
    ("test", ("read_remembered_timetable",), "Do you know our timetable?", "dates: know timetable"),
    ("test", ("read_remembered_timetable",), "How many class days are left?", "dates: days left"),

    # ---- Controls: one per other tool the local model can see.
    ("control", ("list_pages",), "Show me everything in this section", "ctl list_pages"),
    ("control", ("read_page", "list_pages"),
     'What does "Unit 2, Day 3" link to?', "ctl read_page"),
    ("control", ("check_section",), "Is anything broken?", "ctl check_section"),
    ("control", ("publish_class_on",), "Put up Monday's lesson", "ctl publish_class_on"),
    # Said as "Publish Unit 2, Day 3" this is layer 3's `named` regex, so it
    # never reaches the model.
    ("control", ("publish_pages", "publish_class_on"),
     "Publish the page called Unit 2, Day 3", "ctl publish_pages"),
    ("control", ("unpublish_pages",),
     "Take Unit 4, Day 5 back down, students shouldn't see it yet", "ctl unpublish_pages"),
    # "Show me the preview" is one of the thirteen PreviewCommands.
    ("control", ("rebuild_preview",),
     "Build the preview again so I can look at it", "ctl rebuild_preview"),
    ("control", ("undo_last_change",), "That was wrong, revert it", "ctl undo_last_change"),
    ("control", ("deploy_section",), "Put it online", "ctl deploy_section"),
    # "Deploy tomorrow's class at 6:30 AM" is layer 3's `scheduled` regex.
    ("control", ("schedule_deploy",),
     "Put it online tomorrow morning at 6:30", "ctl schedule_deploy"),
    ("control", ("cancel_scheduled_deploy",),
     "Don't send it in the morning after all", "ctl cancel_scheduled"),

    # ---- Controls: the cases earlier measurements found fragile.
    ("control", ("unpublish_pages",),
     "I posted Unit 2, Day 3 by mistake. Make it a draft again",
     "ctl residue: not undo"),
    ("control", (None,), "Delete the Unit 1 folder", "ctl decline: delete"),
    ("control", (None,), "What's the weather going to be like tomorrow?", "ctl decline: weather"),
    ("control", (None, "read_remembered_timetable", "list_pages"),
     "Can you tidy this course up for me?", "ctl vague"),
]


def ask(prompt):
    payload = {
        "model": "local",
        "temperature": 0,
        "max_tokens": 512,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": prompt + DATELINE},
        ],
        "tools": TOOLS,
    }
    request = urllib.request.Request(
        ENDPOINT, data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"})
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError:
        return "__MALFORMED__", {}, 0, int((time.time() - started) * 1000)
    elapsed = int((time.time() - started) * 1000)
    message = data["choices"][0]["message"]
    completion = data.get("usage", {}).get("completion_tokens", 0)
    calls = message.get("tool_calls") or []
    if not calls:
        return None, {}, completion, elapsed
    call = calls[0]["function"]
    try:
        args = json.loads(call["arguments"])
    except Exception:
        args = {}
    return call["name"], args, completion, elapsed


def wrong_course_or_section(args):
    """The example-course substitution is measured behaviour; a probe that
    routes right and then names ICS3U is not a success."""
    course = args.get("course")
    section = args.get("section")
    if course is not None and str(course).upper() != COURSE:
        return True
    if section is not None and str(section) not in (str(SECTION), str(float(SECTION))):
        return True
    return False


def main():
    scores = {"test": [0, 0], "control": [0, 0]}
    misroutes = {}
    wrong_values = 0
    malformed = 0
    per_case = []
    print("### tools=%s trials=%d dateline=%r" % (TOOLS_PATH, TRIALS, DATELINE.strip()))
    print("%-26s %-28s %-5s %-6s %s" % ("probe", "chose", "ok", "ms", "arguments"))
    print("-" * 110)
    for group, acceptable, prompt, label in CASES:
        hits = 0
        for _ in range(TRIALS):
            name, args, completion, ms = ask(prompt)
            if name == "__MALFORMED__":
                malformed += 1
                name = None
            ok = name in acceptable
            scores[group][1] += 1
            if ok:
                scores[group][0] += 1
                hits += 1
            else:
                misroutes.setdefault(label, {}).setdefault(name or "(declined)", 0)
                misroutes[label][name or "(declined)"] += 1
            if name is not None and wrong_course_or_section(args):
                wrong_values += 1
            print("%-26s %-28s %-5s %-6s %s" % (
                label[:25], name or "(declined)", "OK" if ok else "MISS", ms,
                json.dumps(args)[:44]))
        per_case.append((group, label, hits, TRIALS))
    print("-" * 110)
    for group, label, hits, trials in per_case:
        flag = "" if hits == trials else "   <-- not clean"
        print("  %-8s %-26s %d/%d%s" % (group, label, hits, trials, flag))
    print("-" * 110)
    for group in ("test", "control"):
        right, total = scores[group]
        print("%s: %d/%d (%.0f%%)" % (group.upper(), right, total,
                                      100.0 * right / total if total else 0))
    right = scores["test"][0] + scores["control"][0]
    total = scores["test"][1] + scores["control"][1]
    print("OVERALL: %d/%d (%.0f%%)" % (right, total, 100.0 * right / total))
    print("wrong course or section in a routed call: %d" % wrong_values)
    print("malformed tool calls: %d" % malformed)
    if misroutes:
        print("misroutes, by probe:")
        for label in sorted(misroutes):
            parts = ", ".join("%s x%d" % (k, v) for k, v in sorted(misroutes[label].items()))
            print("   %-26s %s" % (label, parts))


main()
