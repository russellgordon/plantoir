#!/usr/bin/env python3
"""
The shipped tool surface, tested against the model it was designed for.

**HISTORICAL — the title is no longer true, noted 2026-09-18.** The probes
below accept `publish_class` and `hide_class`; the app split those into
`publish_pages` / `publish_class_on` and `unpublish_pages` long ago, so every
probe here misses whatever the model does, and a run reads as a routing
collapse that is really a stale accept-list. Two other files pointed here as
the way to measure the shipping surface and have been corrected to name
`trimmed-surface-suite.py` instead. Kept unchanged because its results are
dated records and rewriting it would make them unreproducible.

The earlier suites used hand-written tool definitions. These are the schemas
plantoir-mcp actually publishes over tools/list, so this measures the thing
that will really be in front of a model — including the two design changes the
investigation forced: coarse publish_class instead of separate link/draft
tools, and separate publish/hide verbs instead of one polarity flag.

The case that matters most is the hide one. In the earlier run, "hide
tomorrow's class" produced publish_class(include_linked=true) — the exact
inverse of the request. If splitting the verb fixed that, it shows here.
"""
import json
import sys
import time
import urllib.request
import urllib.error

PORT = sys.argv[1] if len(sys.argv) > 1 else "8099"
TRIALS = int(sys.argv[2]) if len(sys.argv) > 2 else 3
TOOLS_PATH = sys.argv[3] if len(sys.argv) > 3 else "/tmp/real-tools.json"
ENDPOINT = "http://127.0.0.1:%s/v1/chat/completions" % PORT

with open(TOOLS_PATH, encoding="utf-8-sig") as handle:
    TOOLS = json.load(handle)

SYSTEM = (
    "You are Plantoir's assistant, helping a teacher manage their class website. "
    "Choose exactly one tool and fill in its arguments from what the teacher said. "
    "Prefer a plan_ tool when one fits, so the teacher can confirm before anything changes. "
    "If no tool fits, say so plainly instead of guessing."
)

# (acceptable tool names, prompt, what is being probed)
# None in the tuple means "declining is acceptable".
CASES = [
    (("plan_publish_class", "publish_class"),
     'Publish tomorrow\'s class for EXC2O section 1. It is the page called "Unit 2, Day 3". '
     'Also make sure every page it links to is published rather than left as a draft.',
     "publish, with links"),

    (("plan_publish_class", "publish_class"),
     "Put up Unit 3, Day 2 for EXC2O section 2, along with everything it points at.",
     "publish, informal"),

    (("plan_hide_class", "hide_class"),
     'Hide tomorrow\'s class again in EXC2O section 1 - the page is "Ohm\'s Law".',
     "HIDE - the inversion case"),

    (("plan_hide_class", "hide_class"),
     "Take Unit 4, Day 5 back down in EXC2O section 1, students shouldn't see it yet.",
     "hide, different wording"),

    (("plan_hide_class", "hide_class"),
     "I posted Unit 2, Day 3 in EXC2O section 1 by mistake. Make it a draft again.",
     "hide, phrased as a mistake"),

    (("list_courses",), "What courses do I have set up?", "list"),

    (("list_pages", "list_courses"),
     "What pages are in section 1 of EXC2O?", "list pages"),

    (("back_up_course",), "Before I let an AI loose on my notes, take a full backup of EXC2O.",
     "backup"),

    (("read_page", "list_pages"),
     'What does "Unit 2, Day 3" in EXC2O section 1 link to?', "read"),

    ((None,), "Delete the Unit 1 folder in EXC2O.", "deletion - no such tool"),
    ((None,), "Remove all the old classes from last semester in EXC2O.", "destructive - no such tool"),
    ((None, "list_courses"), "Can you clean up my course?", "vague - must not invent a course"),
    ((None,), "What's the weather going to be like tomorrow?", "out of scope"),
    ((None,), "What did I change last week?", "no tool can answer"),

    (("plan_publish_class", "publish_class"),
     "publsh tomorows class for exc2o sec 1, its unit 2 day 3, and the stuff it links to",
     "typos"),
]


def ask(prompt):
    payload = {
        "model": "local",
        "temperature": 0.1,
        "max_tokens": 256,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": prompt},
        ],
        "tools": TOOLS,
    }
    request = urllib.request.Request(
        ENDPOINT, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
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
        args = json.loads(call["arguments"])
    except Exception:
        args = {}
    return call["name"], args, elapsed


def main():
    right = total = malformed = type_problems = 0
    inversions = []
    print("%-32s %-20s %-5s %-6s %s" % ("probe", "chose", "ok", "ms", "arguments"))
    print("-" * 118)
    for acceptable, prompt, probe in CASES:
        for _ in range(TRIALS):
            name, args, ms = ask(prompt)
            total += 1
            if name == "__MALFORMED__":
                malformed += 1
            ok = name in acceptable
            if ok:
                right += 1
            # A hide request answered with a publish tool is the specific
            # failure this design change exists to prevent.
            if "HIDE" in probe or probe.startswith("hide"):
                if name in ("publish_class", "plan_publish_class"):
                    inversions.append((probe, name, args))
            for key, value in args.items():
                if key == "section" and not isinstance(value, int):
                    type_problems += 1
                if key == "includeLinked" and not isinstance(value, bool):
                    type_problems += 1
            print("%-32s %-20s %-5s %-6s %s" % (
                probe[:31], name or "(declined)", "OK" if ok else "MISS", ms,
                json.dumps(args)[:52]))
    print("-" * 118)
    print("routing accuracy: %d/%d (%.0f%%)" % (right, total, 100.0 * right / total))
    print("responses needing type coercion: %d" % type_problems)
    print("malformed tool calls: %d" % malformed)
    print("POLARITY INVERSIONS (hide answered with publish): %d" % len(inversions))
    for probe, name, args in inversions:
        print("   %s -> %s %s" % (probe, name, json.dumps(args)))


main()
