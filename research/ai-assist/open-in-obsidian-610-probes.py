#!/usr/bin/env python3
"""
#610 M2: where sentences about Obsidian go, with and without open_in_obsidian.

The sentences are READ from contracts/assist-cases.json -> openInObsidian,
never retyped: `accepted` (they ask for the page on screen in Obsidian),
`nearMisses` (they must keep the tool they get without it) and
`recordedOnly` (measured, deciding nothing). The same script runs on every
arm, so the BEFORE arms show where these sentences go today.

Mirrors the mac app's request, as trimmed-surface-suite.py --prompt shipped
--app-body --date-appended --real-course does: the system prompt read out of
AssistAgent.swift for the course given, the dateline appended in the mac's
form, temperature 0, tool_choice auto, stream false, the reply cap read out of
AssistModelClient.swift. Every sentence is sent to the model, whether or not
the app would answer it in code first.

    python3 tools-from-contract.py local > local.json
    python3 open-in-obsidian-610-probes.py <port> <trials> local.json [--course VVH2O]

Pass rule: open-in-obsidian-610-preregistration.txt.
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
THE_TOOL = "open_in_obsidian"


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
    FAMILY = json.load(handle)["openInObsidian"]
CASES = []
for sentence in FAMILY["accepted"]:
    CASES.append(("accepted", sentence))
for sentence in FAMILY["nearMisses"]:
    CASES.append(("nearMiss", sentence))
for sentence in FAMILY.get("recordedOnly", []):
    CASES.append(("recorded", sentence))


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
        return "__MALFORMED__", {}, int((time.time() - started) * 1000), 0, 0
    elapsed = int((time.time() - started) * 1000)
    usage = data.get("usage") or {}
    spent = usage.get("completion_tokens", 0)
    prompt_tokens = usage.get("prompt_tokens", 0)
    if data["choices"][0].get("finish_reason") == "length":
        return "__CUT_OFF__", {}, elapsed, spent, prompt_tokens
    calls = data["choices"][0]["message"].get("tool_calls") or []
    if not calls:
        return None, {}, elapsed, spent, prompt_tokens
    call = calls[0]["function"]
    try:
        arguments = json.loads(call["arguments"])
    except Exception:
        arguments = {"__unparsed__": call["arguments"][:60]}
    return call["name"], arguments, elapsed, spent, prompt_tokens


def kind_of(name):
    if name is None:
        return "declined"
    if name == THE_TOOL:
        return "the tool"
    if name in READS:
        return "read"
    return "other"


def main():
    names = []
    for tool in TOOLS:
        names.append(tool["function"]["name"])
    print("### tools=%s (%d: %s) trials=%d course=%s dateline=%r cap=%d" % (
        TOOLS_PATH, len(names), ", ".join(names), TRIALS, COURSE, DATELINE, CAP))
    print("%-9s %-46s %-24s %-6s %-5s %-6s %s" % ("group", "sentence", "chose", "ms", "tok", "prompt", "arguments"))
    print("-" * 140)
    summary = []
    prompt_sizes = []
    latencies = []
    for group, sentence in CASES:
        tally = {}
        for _ in range(TRIALS):
            name, arguments, ms, spent, prompt_tokens = ask(sentence)
            shown = name or "(declined)"
            tally[shown] = tally.get(shown, 0) + 1
            prompt_sizes.append(prompt_tokens)
            latencies.append(ms)
            print("%-9s %-46s %-24s %-6d %-5d %-6d %s" % (
                group, sentence[:46], shown, ms, spent, prompt_tokens, json.dumps(arguments, ensure_ascii=False)))
        summary.append((group, sentence, tally))
    print("-" * 140)
    accepted_to_tool = 0
    accepted_trials = 0
    for group, sentence, tally in summary:
        to_tool = tally.get(THE_TOOL, 0)
        declined = tally.get("(declined)", 0)
        reads = 0
        others = 0
        for name, count in tally.items():
            kind = kind_of(None if name == "(declined)" else name)
            if kind == "read":
                reads += count
            if kind == "other":
                others += count
        verdict = ""
        if group == "accepted":
            accepted_to_tool += to_tool
            accepted_trials += TRIALS
            if others:
                verdict = "FAILS rule (e): a tool other than open_in_obsidian, a decline or a read"
        if group == "nearMiss" and to_tool:
            verdict = "FAILS rule (c): open_in_obsidian chosen"
        choices = ", ".join("%s x%d" % (k, v) for k, v in sorted(tally.items()))
        print("  %-9s %-46s %s %2d  declined %2d  read %2d  other %2d   [%s]  %s" % (
            group, sentence[:46], THE_TOOL, to_tool, declined, reads, others, choices, verdict))
    print("-" * 140)
    print("accepted set to %s: %d/%d" % (THE_TOOL, accepted_to_tool, accepted_trials))
    prompt_sizes.sort()
    latencies.sort()
    if prompt_sizes:
        print("prompt tokens: median %d   turn latency: median %d ms, max %d ms" % (
            prompt_sizes[len(prompt_sizes) // 2], latencies[len(latencies) // 2], latencies[-1]))


main()
