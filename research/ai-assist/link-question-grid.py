#!/usr/bin/env python3
"""#167 grid: the link-question family on the SHIPPED local surface, per course x date.

Reuses trimmed-surface-suite.py's own system prompt reader and request body
(exec'd with --intercept-only so nothing is re-typed here). Greedy decoding
(the app's body: temperature 0, tool_choice auto, max_tokens from the Swift),
so ONE trial per cell: repeated trials at temperature 0 are near-identical and
a trial count would not be a failure rate.
Usage (from the repository root): python3 research/ai-assist/link-question-grid.py TOOLS.json PORT TIER-LABEL
TOOLS.json is the local surface as `tools-from-contract.py` writes it.
"""
import datetime, json, sys, urllib.request, copy
TOOLS_PATH, PORT, LABEL = sys.argv[1], sys.argv[2], sys.argv[3]
HARNESS = "research/ai-assist/trimmed-surface-suite.py"
g = {"__name__": "harness", "__file__": HARNESS}
sys.argv = [HARNESS, TOOLS_PATH, "1", "--app-body", "--prompt", "shipped", "--intercept-only"]
try:
    exec(compile(open(HARNESS).read(), HARNESS, "exec"), g)
except SystemExit:
    pass
CAP = g["swift_most_tokens_per_reply"]()
BASE_TOOLS = json.load(open(TOOLS_PATH))
COURSES = ["VVH2O", "EXC2O", "ICS3U", "SPH3U", "MPM2D", "ENG4U"]
START = datetime.date(2026, 9, 21)
DATES = [START + datetime.timedelta(days=i) for i in range(14)]
PROBES = [
    ("verbatim #167", 'What does "Unit 2, Day 3" in {C} section 1 link to?'),
    ("quoted, bare", 'What does "Unit 2, Day 3" link to?'),
    ("unquoted, bare", "What does Unit 2, Day 3 link to?"),
    ("which pages", "Which pages does Unit 2, Day 3 link to?"),
    ("what links are on", "What links are on Unit 2, Day 3?"),
    ("links from", "Show me the links from Unit 2, Day 3"),
    ("where does it point", "Where does Unit 2, Day 3 point to?"),
]
def tools_for(course):
    text = json.dumps(BASE_TOOLS).replace("ICS3U", course)
    return json.loads(text)
def ask(system, tools, user):
    body = {"model": "local", "temperature": 0.0, "tool_choice": "auto", "stream": False,
            "max_tokens": CAP,
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            "tools": tools}
    req = urllib.request.Request("http://127.0.0.1:%s/v1/chat/completions" % PORT,
                                 data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    data = json.loads(urllib.request.urlopen(req, timeout=600).read())
    calls = data["choices"][0]["message"].get("tool_calls") or []
    return calls[0]["function"]["name"] if calls else "(declined)"
results = {}
for course in COURSES:
    system = g["system_prompt"]("shipped", course, 1)
    tools = tools_for(course)
    for day in DATES:
        line = "(Today is %s, a %s.)" % (day.isoformat(), day.strftime("%A"))
        for label, probe in PROBES:
            chose = ask(system, tools, "%s %s" % (probe.replace("{C}", course), line))
            results.setdefault(label, {}).setdefault(chose, 0)
            results[label][chose] += 1
            print("%s\t%s\t%s\t%s\t%s" % (LABEL, course, day.isoformat(), label, chose), flush=True)
print()
print("## %s: %d courses x %d dates (%s..%s), one greedy trial per cell" % (
    LABEL, len(COURSES), len(DATES), DATES[0], DATES[-1]))
for label, _ in PROBES:
    spread = sorted(results[label].items(), key=lambda kv: -kv[1])
    ok = results[label].get("read_page", 0) + results[label].get("list_pages", 0)
    print("%-20s %3d/%d  %s" % (label, ok, len(COURSES) * len(DATES),
          ", ".join("%dx %s" % (n, t) for t, n in spread)))
