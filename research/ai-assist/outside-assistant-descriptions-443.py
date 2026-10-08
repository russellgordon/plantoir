#!/usr/bin/env python3
"""#443: the five outside-assistant strings that moved from "publish" to
"deploy", measured before they ship.

WHAT MOVED (all five are shown to OUTSIDE assistants only):
  - list_courses' description: "...and where each publishes to." -> "deploys to."
  - re_date_classes' description: "so publishing no longer replaces last
    year's site" -> "so deploying no longer replaces..."
  - make_room_for_classes' description: "...before publishing anything." ->
    "before deploying anything."
  - plan_scheduled_deploy's `classes` argument: "The class pages this deploy
    is meant to publish" -> "...meant to carry"
  - list_courses' RESULT line "  publishes to: " -> "  deploys to: " (a
    result, not a description: no model routes on it, so it is not measured
    here).

WHO READS THEM. Neither platform's LOCAL model: the mac's
`AssistToolRunner.localTools` and Windows' `AssistAgent.ForTheLocalModel`
(mirrored in narrow-tools.py) contain none of these four tools, and the mac's
local digest is pinned unchanged by scripts/test_tool_surface_digest.py. The
readers are Claude Code and Codex over MCP, which cannot be run as a
controlled routing suite on this Mac. So this is the measurement that CAN be
taken here, as a PROXY: the smaller assistant's weights, shown the WHOLE
37-tool MCP surface (toolSchemas.mcp), before and after, asked the sentences
whose expected tool is one of the four, plus controls whose expected tool
says publish or deploy in its own sense - the place a word change could
pull a request the wrong way.

The veto doc 10 ("One description per tool") sets for a description change,
applied per tool: (a) any polarity inversion AFTER that BEFORE did not have
vetoes; (b) a net loss of 3 trials or more on a tool's probes keeps that
tool's old text; (c) a fall of more than 5 percentage points overall stops
and reports.

Usage:
    python3 research/ai-assist/tools-from-contract.py mcp > before.json   # at origin/dev
    python3 research/ai-assist/tools-from-contract.py mcp > after.json    # on the branch
    python3 research/ai-assist/outside-assistant-descriptions-443.py before.json after.json 10 [--port 8099]

Needs a llama-server already running on the port with the weights loaded.
"""
import datetime
import json
import sys
import urllib.request

ARGS = sys.argv[1:]
BEFORE_PATH = ARGS[0]
AFTER_PATH = ARGS[1]
TRIALS = int(ARGS[2]) if len(ARGS) > 2 and not ARGS[2].startswith("--") else 10
PORT = ARGS[ARGS.index("--port") + 1] if "--port" in ARGS else "8099"
ENDPOINT = "http://127.0.0.1:%s/v1/chat/completions" % PORT

TODAY = datetime.date.today()
DATELINE = "(Today is %s, a %s.)" % (TODAY.isoformat(), TODAY.strftime("%A"))

# An outside assistant's own system prompt is its own; this is a neutral one,
# the same in both arms, so only the descriptions differ.
SYSTEM = ("You are an assistant connected to Plantoir, which builds a class website for each "
          "section of a teacher's course. Answer by calling one of the tools. The course is "
          "EXC2O, section 1, unless the teacher says otherwise.")

# (label, sentence, accepted tools, tool whose OPPOSITE would be an inversion)
PROBES = [
    ("list_courses: what courses", "What courses do I have?", {"list_courses"}, None),
    ("list_courses: where online", "Which courses are in this folder, and where does each one go online?",
     {"list_courses"}, None),
    ("list_courses: deploys where", "List my courses and where each of them deploys to.", {"list_courses"}, None),
    ("re_date: new year, new site", "Roll EXC2O section 1 over to the new school year and start a new website for it.",
     {"re_date_classes"}, None),
    ("re_date: same site", "Re-date my classes for EXC2O section 1 for next year and keep the same website.",
     {"re_date_classes"}, None),
    ("make_room: insert", "Make room for two classes at Unit 3, Day 4 in EXC2O section 1.",
     {"make_room_for_classes", "plan_make_room_for_classes"}, None),
    ("schedule: carry pages", "Deploy EXC2O section 1 tomorrow at 6:30 in the morning, with Unit 2, Day 3 on it.",
     {"plan_scheduled_deploy", "schedule_deploy"}, None),
    ("control: publish a page", "Publish Unit 2, Day 3 for EXC2O section 1.",
     {"publish_pages", "plan_publish_pages"}, {"unpublish_pages", "plan_unpublish_pages"}),
    ("control: hide a page", "Hide Unit 4, Day 12 in EXC2O section 1.",
     {"unpublish_pages", "plan_unpublish_pages"}, {"publish_pages", "plan_publish_pages"}),
    ("control: deploy now", "Deploy EXC2O section 1 now.", {"deploy_section"}, None),
    ("control: what is publishing", "What is the difference between publishing and deploying?",
     {"explain_publishing"}, None),
]


def ask(tools, sentence):
    body = {
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": sentence + " " + DATELINE},
        ],
        "tools": tools,
        "tool_choice": "auto",
        "temperature": 0,
        "max_tokens": 512,
    }
    request = urllib.request.Request(ENDPOINT, data=json.dumps(body).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=600) as response:
        answer = json.loads(response.read().decode("utf-8"))
    choice = answer["choices"][0]
    calls = choice["message"].get("tool_calls") or []
    cut_off = choice.get("finish_reason") == "length"
    if not calls:
        return None, cut_off
    return calls[0]["function"]["name"], cut_off


def run(label, tools):
    per_probe = {}
    for name, sentence, accepted, opposite in PROBES:
        ok = 0
        inversions = 0
        cut = 0
        chosen = {}
        for _ in range(TRIALS):
            tool, cut_off = ask(tools, sentence)
            chosen[tool] = chosen.get(tool, 0) + 1
            if cut_off:
                cut += 1
            elif tool in accepted:
                ok += 1
            if opposite is not None and tool in opposite:
                inversions += 1
        per_probe[name] = (ok, inversions, cut, chosen)
        print("%-6s %-32s %2d/%d  inversions %d  cut off %d  %s" % (label, name, ok, TRIALS, inversions, cut,
                                                                     json.dumps(chosen)), flush=True)
    return per_probe


def main():
    before = json.load(open(BEFORE_PATH, encoding="utf-8"))
    after = json.load(open(AFTER_PATH, encoding="utf-8"))
    print("tools: before %d, after %d; trials %d; %s" % (len(before), len(after), TRIALS, DATELINE))
    results = {"BEFORE": run("BEFORE", before), "AFTER": run("AFTER", after)}
    total = {}
    for arm, per_probe in results.items():
        total[arm] = sum(value[0] for value in per_probe.values())
    print("TOTAL  BEFORE %d/%d  AFTER %d/%d" % (total["BEFORE"], TRIALS * len(PROBES),
                                                total["AFTER"], TRIALS * len(PROBES)))


if __name__ == "__main__":
    main()
