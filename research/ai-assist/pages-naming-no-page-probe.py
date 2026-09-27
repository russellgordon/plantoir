#!/usr/bin/env python3
"""#197's two follow-up measurements, on the shipping 13-tool local surface.

Same conditions as two-lap-all.py beside it (read from the repository, never
typed): the surface from contracts/assist-cases.json -> toolSchemas.local with
the example course rewritten to the window's, the system prompt read out of
AssistAgent.swift, the app's request body (temperature 0, tool_choice auto,
max_tokens read from AssistModelClient.swift), the date line appended.

  U  "Publish all the classes in Unit 2." and its neighbours, ONE lap, as the
     MODEL answers them. The first went to publish_class_on with today's date
     3 times in 3 on 2026-09-26. Since #197 the app answers the two measured
     openings in CODE (AssistCardCommand.wholeUnitToPublish), so the model
     never sees them in the app; this arm is the model alone, to show the
     surface did not move and that the fix is the code's. The neighbours that
     still reach the model (a course named, a question mark) are here so the
     record says what they do.
  R  Risk R4 of the plan: the scripted two-lap shape, then the model's
     `publish_pages {"pages": "all"}`, then the NEW refusal in the tool
     message (plan mode's twin answers couldNotRead, so the model gets
     another lap). What does it write next?

Usage: pages-naming-no-page-probe.py PORT TRIALS
"""
import datetime
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
PORT = sys.argv[1]
TRIALS = int(sys.argv[2])
COURSE = "ICS3U"
SECTION = 1


def real(node):
    if isinstance(node, dict):
        return {key: real(value) for key, value in node.items()}
    if isinstance(node, list):
        return [real(value) for value in node]
    if isinstance(node, str):
        return node.replace("ICS3U", COURSE)
    return node


TOOLS = real(json.load(open(ROOT / "contracts/assist-cases.json"))["toolSchemas"]["local"])
WORDING = json.load(open(ROOT / "contracts/assist-wording.json"))["wording"]
source = (ROOT / "mac-app/QuartzTeachers/Models/Assist/AssistAgent.swift").read_text()
marker = "static func systemPrompt(course: String, section: Int) -> String {"
start = source.index(marker)
opening = source.index('"""', start) + 3
closing = source.index('"""', opening)
indent = len(source[:closing].rsplit("\n", 1)[1])
text = ""
for line in source[opening:closing].split("\n")[1:-1]:
    body = line[indent:] if line.startswith(" " * indent) else line.lstrip()
    text += body[:-1] if body.endswith("\\") else body + "\n"
SYSTEM = text.rstrip("\n").replace("\\(course)", COURSE).replace("\\(section)", str(SECTION))
CAP = int(re.search(r"static let mostTokensPerReply:\s*Int\s*=\s*(\d+)",
          (ROOT / "mac-app/QuartzTeachers/Models/Assist/AssistModelClient.swift").read_text()).group(1))
TODAY = datetime.date(2026, 9, 26)
DATELINE = "(Today is %s, a %s.)" % (TODAY.isoformat(), TODAY.strftime("%A"))


def ask(messages):
    payload = {"model": "local", "temperature": 0.0, "messages": messages, "tools": TOOLS,
               "tool_choice": "auto", "stream": False, "max_tokens": CAP}
    request = urllib.request.Request("http://127.0.0.1:%s/v1/chat/completions" % PORT,
                                     data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"})
    data = json.loads(urllib.request.urlopen(request, timeout=600).read())
    choice = data["choices"][0]
    calls = choice["message"].get("tool_calls") or []
    tokens = data.get("usage", {}).get("completion_tokens")
    if calls:
        function = calls[0]["function"]
        return function["name"], function["arguments"].replace("\n", " "), tokens, choice.get("finish_reason")
    return None, (choice["message"].get("content") or "").replace("\n", " "), tokens, choice.get("finish_reason")


print("### surface %d tools; system prompt %d chars; max_tokens %d; %s" % (len(TOOLS), len(SYSTEM), CAP, DATELINE))

print("\n## U. One lap, the model alone")
tally = {}
for sentence in ["Publish all the classes in Unit 2.",
                 "Publish everything in Unit 2.",
                 "Publish all the classes in Unit 2 for ICS3U section 1.",
                 "Publish all the classes in Unit 2?",
                 "Publish all classes in Unit 2."]:
    print(" >", sentence)
    for trial in range(TRIALS):
        name, arguments, tokens, finish = ask([{"role": "system", "content": SYSTEM},
                                               {"role": "user", "content": sentence + " " + DATELINE}])
        print("   t%d %s %s [completion %s, %s]" % (trial, name or "NO TOOL", arguments[:160], tokens, finish))
        tally.setdefault(sentence, {}).setdefault(name or "none", 0)
        tally[sentence][name or "none"] += 1
print("TALLY U", json.dumps(tally))

print("\n## R. Plan mode's lap after the new refusal (risk R4)")
base = ROOT / "support/example_content/ICS3U"
paths = []
for page in (base / "shared").rglob("*.md"):
    paths.append("courses/ICS3U/" + str(page.relative_to(base / "shared")))
for page in (base / "per_section").rglob("*.md"):
    paths.append("courses/ICS3U/section1/" + str(page.relative_to(base / "per_section")))
paths.sort(key=lambda path: path.lower())
listing = "\n".join(paths[:60])
if len(paths) > 60:
    listing += "\n\n…and %d more of %d. Pass `matching` to narrow this down." % (len(paths) - 60, len(paths))
refusal = WORDING["everyPageIsNotAPageToPublish"].replace("{example}", "Publish Unit 1")
tally = {}
for trial in range(TRIALS):
    listed = {"id": "c1", "type": "function",
              "function": {"name": "list_pages", "arguments": json.dumps({"course": COURSE, "section": SECTION})}}
    published = {"id": "c2", "type": "function",
                 "function": {"name": "publish_pages",
                              "arguments": json.dumps({"course": COURSE, "section": SECTION, "pages": "all"})}}
    messages = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": "Publish everything in Unit 3 for ICS3U section 1. " + DATELINE},
                {"role": "assistant", "content": "", "tool_calls": [listed]},
                {"role": "tool", "tool_call_id": "c1", "name": "list_pages", "content": listing},
                {"role": "user", "content": "Publish all of those. " + DATELINE},
                {"role": "assistant", "content": "", "tool_calls": [published]},
                {"role": "tool", "tool_call_id": "c2", "name": "publish_pages", "content": refusal}]
    name, arguments, tokens, finish = ask(messages)
    kind = name or "no tool (text)"
    if finish == "length":
        kind += ", cut off"
    tally[kind] = tally.get(kind, 0) + 1
    print("   t%d %s %s [completion %s, %s]" % (trial, name or "NO TOOL", arguments[:220], tokens, finish))
print("TALLY R", json.dumps(tally))
