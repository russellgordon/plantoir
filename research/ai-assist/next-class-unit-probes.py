#!/usr/bin/env python3
"""
#440 M2: what the local model sends for sentences about units and counts.

Settler S3 (`AssistNextClassUnits`, mac) stops a model's add_next_class when
the TEACHER'S sentence asked for a new unit, a unit or day other than the next
one, or several pages. S3 is deterministic Swift and pinned by the contract;
what it ASSUMES is a model fact, and this measures it: that each such
sentence reaches add_next_class (or is declined) and never another write
tool, and that the model sends no `unit`/`days` key of its own. A sentence
that reached publish_pages instead would never meet S3 at all.

The sentences are READ from contracts/assist-cases.json -> nextClassUnits,
never retyped: every `pointed` row (all reach the model; the mac's
NextClassUnitsTests pins that no card matches them) and every `runs` row
marked `reachesModel`. Rows marked `measuredAsControl` are the plain controls.

Mirrors the mac app's request, as trimmed-surface-suite.py --prompt shipped
--app-body --date-appended --real-course does: the system prompt read out of
AssistAgent.swift for the course given, the dateline appended in the mac's
form, temperature 0, tool_choice auto, stream false, the reply cap read out of
AssistModelClient.swift. add_next_class's arguments are printed IN FULL (#411:
44 characters hid unit "next").

    python3 tools-from-contract.py local > local.json
    python3 next-class-unit-probes.py <port> <trials> local.json [--course VVH2O]

A tools file that declares more on add_next_class (the A' arm of #440: a
boolean newUnit and integer unit/days) is measured the same way; the summary
then also counts which of those keys each sentence was sent with.
"""
import datetime
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
FLAGS = [a for a in sys.argv[1:] if a.startswith("--")]
POSITIONAL = [a for a in sys.argv[1:] if not a.startswith("--")]
ARGS = sys.argv[1:]
PORT = POSITIONAL[0] if len(POSITIONAL) > 0 else "8099"
TRIALS = int(POSITIONAL[1]) if len(POSITIONAL) > 1 else 10
TOOLS_PATH = POSITIONAL[2] if len(POSITIONAL) > 2 else "local.json"
COURSE = ARGS[ARGS.index("--course") + 1] if "--course" in ARGS else "VVH2O"
SECTION = 1
ENDPOINT = "http://127.0.0.1:%s/v1/chat/completions" % PORT

TODAY = datetime.date.today()
WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
DATELINE = "(Today is %s, a %s.)" % (TODAY.isoformat(), WEEKDAYS[TODAY.weekday()])

READS = {"list_pages", "read_page", "check_section", "read_remembered_timetable"}


def swift_system_prompt(course, section):
    """`AssistAgent.systemPrompt(course:section:)`, read out of the Swift the
    way trimmed-surface-suite.py reads it (the closing delimiter's indent is
    stripped, a trailing backslash joins lines)."""
    source = (ROOT / "mac-app/QuartzTeachers/Models/Assist/AssistAgent.swift").read_text(encoding="utf-8")
    marker = "static func systemPrompt(course: String, section: Int) -> String {"
    start = source.index(marker)
    opening = source.index('"""', start) + 3
    closing = source.index('"""', opening)
    indent = len(source[:closing].rsplit("\n", 1)[1])
    text = ""
    for line in source[opening:closing].split("\n")[1:-1]:
        body = line[indent:] if line.startswith(" " * indent) else line.lstrip()
        text += body[:-1] if body.endswith("\\") else body + "\n"
    return text.rstrip("\n").replace("\\(course)", course).replace("\\(section)", str(section))


def swift_cap():
    source = (ROOT / "mac-app/QuartzTeachers/Models/Assist/AssistModelClient.swift").read_text(encoding="utf-8")
    found = re.search(r"static let mostTokensPerReply:\s*Int\s*=\s*(\d+)", source)
    if not found:
        sys.exit("Could not read mostTokensPerReply from AssistModelClient.swift.")
    return int(found.group(1))


SYSTEM = swift_system_prompt(COURSE, SECTION)
CAP = swift_cap()
with open(TOOLS_PATH, encoding="utf-8-sig") as handle:
    TOOLS = json.load(handle)
# The contract's examples name ICS3U; the probes name the measured course.
TOOLS = json.loads(json.dumps(TOOLS).replace("ICS3U", COURSE))

with open(ROOT / "contracts" / "assist-cases.json", encoding="utf-8") as handle:
    FAMILY = json.load(handle)["nextClassUnits"]
CASES = []
for row in FAMILY["pointed"]:
    CASES.append(("pointed-" + row["kind"], row["input"]))
for row in FAMILY["runs"]:
    if row.get("reachesModel"):
        CASES.append(("control" if row.get("measuredAsControl") else "runs", row["input"]))


def ask(prompt):
    payload = {
        "model": "local", "temperature": 0, "tool_choice": "auto", "stream": False, "max_tokens": CAP,
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": prompt + " " + DATELINE}],
        "tools": TOOLS,
    }
    request = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError:
        return "__MALFORMED__", {}, int((time.time() - started) * 1000), 0
    elapsed = int((time.time() - started) * 1000)
    spent = (data.get("usage") or {}).get("completion_tokens", 0)
    if data["choices"][0].get("finish_reason") == "length":
        return "__CUT_OFF__", {}, elapsed, spent
    calls = data["choices"][0]["message"].get("tool_calls") or []
    if not calls:
        return None, {}, elapsed, spent
    call = calls[0]["function"]
    try:
        arguments = json.loads(call["arguments"])
    except Exception:
        arguments = {"__unparsed__": call["arguments"][:60]}
    return call["name"], arguments, elapsed, spent


def extra_keys(arguments):
    keys = []
    for key in sorted(arguments):
        if key not in ("course", "section"):
            keys.append("%s=%s" % (key, json.dumps(arguments[key])))
    return keys


def main():
    print("### tools=%s trials=%d course=%s dateline=%r cap=%d" % (TOOLS_PATH, TRIALS, COURSE, DATELINE, CAP))
    print("%-10s %-52s %-24s %-6s %-5s %s" % ("group", "sentence", "chose", "ms", "tok", "arguments"))
    print("-" * 140)
    summary = []
    for group, sentence in CASES:
        tally = {}
        extras = {}
        for _ in range(TRIALS):
            name, arguments, ms, spent = ask(sentence)
            shown = name or "(declined)"
            tally[shown] = tally.get(shown, 0) + 1
            for key in extra_keys(arguments):
                extras[key] = extras.get(key, 0) + 1
            print("%-10s %-52s %-24s %-6d %-5d %s" % (
                group, sentence[:52], shown, ms, spent, json.dumps(arguments, ensure_ascii=False)))
        summary.append((group, sentence, tally, extras))
    print("-" * 140)
    failures = []
    for group, sentence, tally, extras in summary:
        to_next = tally.get("add_next_class", 0)
        declined = tally.get("(declined)", 0)
        other_writes = 0
        for name, count in tally.items():
            if name not in ("add_next_class", "(declined)") and name not in READS:
                other_writes += count
        extra_text = ", ".join("%s x%d" % (k, v) for k, v in sorted(extras.items())) or "none"
        verdict = "ok"
        if group.startswith("pointed") and (other_writes or extras):
            verdict = "FAILS (a write tool other than add_next_class, or unit/days sent)"
        if group == "control" and (to_next != TRIALS or extras):
            verdict = "FAILS (a control below %d/%d, or extra keys)" % (TRIALS, TRIALS)
        if verdict != "ok":
            failures.append(sentence)
        print("  %-10s %-52s add_next_class %2d  declined %2d  other write %2d  extra keys: %s  %s" % (
            group, sentence[:52], to_next, declined, other_writes, extra_text, verdict))
        others = ", ".join("%s x%d" % (k, v) for k, v in sorted(tally.items())
                           if k not in ("add_next_class", "(declined)"))
        if others:
            print("  %-10s %-52s   other choices: %s" % ("", "", others))
    print("-" * 140)
    print("sentences: %d   trials each: %d   failing the M2 rule: %d" % (len(summary), TRIALS, len(failures)))
    for sentence in failures:
        print("   FAILS: %s" % sentence)


main()
