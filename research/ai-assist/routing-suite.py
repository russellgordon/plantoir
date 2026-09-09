#!/usr/bin/env python3
"""
Routing accuracy for a small local model against a Plantoir-shaped tool set.

The premise under test: if the TOOLS do the work, the model only has to pick
one and fill its arguments. This measures how often it picks correctly, and
whether the arguments are usable after type coercion.

**HISTORICAL — do not run this to measure the shipping surface.** The five
tools below are hand-written and were the surface as it stood when this ran;
the app's real surface has thirteen. Kept unchanged because its results are
dated records and rewriting it would make them unreproducible.

For a measurement of what actually ships:

    python3 research/ai-assist/tools-from-contract.py local > /tmp/real-tools.json
    python3 research/ai-assist/shipped-surface-suite.py 8099 10 /tmp/real-tools.json

On WINDOWS, do NOT start from the contract: it is generated from the mac, so
its descriptions are the mac's and not the ones Windows' server publishes. Dump
the live surface with `dump-tools.ps1` and narrow it with `narrow-tools.py`.
See the note in `tools-from-contract.py`.

A routing score measured against tools the app does not ship is worse than no
score, because it reads as evidence.
"""
import json
import sys
import time
import urllib.request

ENDPOINT = "http://127.0.0.1:8099/v1/chat/completions"

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "publish_class",
            "description": "Publish one class page and optionally every page it links to. Handles un-drafting linked pages and republishing the section website.",
            "parameters": {
                "type": "object",
                "properties": {
                    "course": {"type": "string", "description": "Course code, e.g. MCV4U"},
                    "section": {"type": "integer"},
                    "page": {"type": "string", "description": "Class page title"},
                    "include_linked": {"type": "boolean"},
                },
                "required": ["course", "section", "page", "include_linked"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "reschedule_classes",
            "description": "Change the dates of upcoming classes from a CSV of new dates, renumbering classes and updating linked activities.",
            "parameters": {
                "type": "object",
                "properties": {
                    "course": {"type": "string"},
                    "section": {"type": "integer"},
                    "csv_path": {"type": "string"},
                },
                "required": ["course", "section", "csv_path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "back_up_course",
            "description": "Make a full backup of a course before risky changes.",
            "parameters": {
                "type": "object",
                "properties": {"course": {"type": "string"}},
                "required": ["course"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "set_draft",
            "description": "Set the draft flag on ONE named page. draft=false publishes just that page.",
            "parameters": {
                "type": "object",
                "properties": {
                    "course": {"type": "string"},
                    "page": {"type": "string"},
                    "draft": {"type": "boolean"},
                },
                "required": ["course", "page", "draft"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "list_courses",
            "description": "List the teacher's courses and sections.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
]

SYSTEM = (
    "You are Plantoir's assistant, helping a teacher manage their class website. "
    "Choose exactly one tool and fill in its arguments from what the teacher said. "
    "If no tool fits, say so plainly instead of guessing."
)

CASES = [
    ("publish_class", "Publish tomorrow's class for MCV4U section 1. It is the page called \"Unit 2, Day 3\". Also make sure every page it links to is published rather than left as a draft."),
    ("publish_class", "Put up Unit 3, Day 2 for ICS3U section 4, along with everything it points at."),
    ("publish_class", "Can you make tomorrow's lesson visible to students? It's \"Unit 1, Day 5\" in MPM2D section 2, and the worksheets it links to should go up too."),
    ("reschedule_classes", "My teaching schedule changed. Here is a CSV with the new dates for the next two weeks: /Users/me/newdates.csv. Fix MCV4U section 1."),
    ("reschedule_classes", "Snow day pushed everything back. Use ~/Desktop/revised.csv to redo the class dates for SNC1W section 3."),
    ("back_up_course", "Before I let an AI loose on my notes, take a full backup of TGJ2O."),
    ("set_draft", "Just un-draft the page called \"Ohm's Law\" in SNC1W, nothing else."),
    ("list_courses", "What courses do I have set up?"),
    (None, "What's the weather going to be like tomorrow?"),
]

TRIALS = int(sys.argv[1]) if len(sys.argv) > 1 else 3


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
        ENDPOINT,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError as error:
        # A 500 here is the model emitting a tool call the runtime cannot
        # parse — a malformed-output failure, not a routing failure.
        elapsed = int((time.time() - started) * 1000)
        return "__MALFORMED__", {}, elapsed
    elapsed = int((time.time() - started) * 1000)
    message = data["choices"][0]["message"]
    calls = message.get("tool_calls") or []
    if not calls:
        return None, {}, elapsed
    call = calls[0]["function"]
    try:
        args = json.loads(call["arguments"])
    except Exception:
        args = {"__unparseable__": call["arguments"]}
    return call["name"], args, elapsed


def main():
    right = 0
    total = 0
    type_problems = 0
    malformed = 0
    print("expected            got                 ok   ms     arguments")
    print("-" * 100)
    for expected, prompt in CASES:
        for _ in range(TRIALS):
            name, args, ms = ask(prompt)
            total += 1
            if name == "__MALFORMED__":
                malformed += 1
            ok = (name == expected)
            if ok:
                right += 1
            # Would the arguments survive a strict schema without coercion?
            for key, value in args.items():
                if key in ("section",) and not isinstance(value, int):
                    type_problems += 1
                if key in ("include_linked", "draft") and not isinstance(value, bool):
                    type_problems += 1
            print("%-19s %-19s %-4s %-6s %s" % (
                expected or "(none)", name or "(none)", "OK" if ok else "MISS", ms,
                json.dumps(args)[:60]))
    print("-" * 100)
    print("routing accuracy: %d/%d (%.0f%%)" % (right, total, 100.0 * right / total))
    print("responses needing type coercion: %d" % type_problems)
    print("malformed tool calls (runtime rejected): %d" % malformed)


main()
