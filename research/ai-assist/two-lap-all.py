#!/usr/bin/env python3
"""#197 reproduction: the two-lap list_pages -> publish_pages shape, on the
shipping 13-tool local surface read from contracts/assist-cases.json, the
shipped system prompt read out of AssistAgent.swift, the app's request body
(temperature 0, tool_choice auto, max_tokens 512), dateline appended.
Paths come from support/example_content/ICS3U laid out the way the installer
lays them out (shared/ -> courses/ICS3U/, per_section/ -> courses/ICS3U/section1/),
sorted the way ClassPages.pagesOfSection sorts them.
Usage: twolap.py PORT TRIALS [tools.json]
"""
import json, sys, pathlib, urllib.request, re, datetime
ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
PORT = sys.argv[1]; TRIALS = int(sys.argv[2])
TOOLS_FILE = sys.argv[3] if len(sys.argv) > 3 else None
COURSE = "ICS3U"; SECTION = 1
if TOOLS_FILE:
    TOOLS = json.load(open(TOOLS_FILE))
else:
    TOOLS = json.load(open(ROOT / "contracts/assist-cases.json"))["toolSchemas"]["local"]
def real(node):
    if isinstance(node, dict): return {k: real(v) for k, v in node.items()}
    if isinstance(node, list): return [real(v) for v in node]
    if isinstance(node, str): return node.replace("ICS3U", COURSE)
    return node
TOOLS = real(TOOLS)
src = (ROOT / "mac-app/QuartzTeachers/Models/Assist/AssistAgent.swift").read_text()
marker = "static func systemPrompt(course: String, section: Int) -> String {"
start = src.index(marker); opening = src.index('"""', start) + 3; closing = src.index('"""', opening)
indent = len(src[:closing].rsplit("\n", 1)[1]); text = ""
for line in src[opening:closing].split("\n")[1:-1]:
    body = line[indent:] if line.startswith(" " * indent) else line.lstrip()
    text += body[:-1] if body.endswith("\\") else body + "\n"
SYSTEM = text.rstrip("\n").replace("\\(course)", COURSE).replace("\\(section)", str(SECTION))
cap = int(re.search(r"static let mostTokensPerReply:\s*Int\s*=\s*(\d+)",
      (ROOT / "mac-app/QuartzTeachers/Models/Assist/AssistModelClient.swift").read_text()).group(1))
today = datetime.date(2026, 9, 26)
DATELINE = "(Today is %s, a %s.)" % (today.isoformat(), today.strftime("%A"))

base = ROOT / "support/example_content/ICS3U"
paths = []
for f in (base / "shared").rglob("*.md"):
    paths.append("courses/ICS3U/" + str(f.relative_to(base / "shared")))
for f in (base / "per_section").rglob("*.md"):
    paths.append("courses/ICS3U/section1/" + str(f.relative_to(base / "per_section")))
paths.sort(key=lambda p: p.lower())

def listing(filter_text):
    hits = [p for p in paths if (not filter_text) or filter_text.lower() in p.lower()]
    where = "%s Section %d" % (COURSE, SECTION)
    if not hits:
        return "No page in %s matches “%s”." % (where, filter_text)
    shown = hits[:60]
    detail = "\n".join(shown)
    if len(hits) > len(shown):
        detail += "\n\n…and %d more of %d. Pass `matching` to narrow this down." % (len(hits) - len(shown), len(hits))
    return detail

def ask(messages):
    payload = {"model": "local", "temperature": 0.0, "messages": messages, "tools": TOOLS,
               "tool_choice": "auto", "stream": False, "max_tokens": cap}
    req = urllib.request.Request("http://127.0.0.1:%s/v1/chat/completions" % PORT,
          data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    data = json.loads(urllib.request.urlopen(req, timeout=600).read())
    msg = data["choices"][0]["message"]; calls = msg.get("tool_calls") or []
    usage = data.get("usage", {})
    return msg, calls, usage.get("completion_tokens"), usage.get("prompt_tokens"), data["choices"][0].get("finish_reason")

def show(tag, calls, ct, pt, fr, msg):
    if calls:
        c = calls[0]["function"]; a = c["arguments"]
        print("  %-10s %s %s  [prompt %s, completion %s, %s]" % (tag, c["name"], a[:300], pt, ct, fr))
    else:
        print("  %-10s NO TOOL: %r  [completion %s]" % (tag, (msg.get("content") or "")[:200], ct))

FIRST_ASKS = [
    "Publish everything in Unit 3 for ICS3U section 1.",
    "Publish everything in Unit 3.",
    "Publish all of Unit 3.",
    "Publish all the Unit 3 pages.",
    "Publish every page in unit 3",
    "Publish all the classes in Unit 2.",
]
print("### %d paths in section; system prompt %d chars; max_tokens %d; tools %d" % (len(paths), len(SYSTEM), cap, len(TOOLS)))

print("\n## A. Issue shape: scripted list_pages (unfiltered), then 'Publish all of those.'")
for t in range(TRIALS):
    call = {"id": "c1", "type": "function", "function": {"name": "list_pages", "arguments": json.dumps({"course": COURSE, "section": SECTION})}}
    msgs = [{"role": "system", "content": SYSTEM},
            {"role": "user", "content": FIRST_ASKS[0] + " " + DATELINE},
            {"role": "assistant", "content": "", "tool_calls": [call]},
            {"role": "tool", "tool_call_id": "c1", "name": "list_pages", "content": listing("")},
            {"role": "user", "content": "Publish all of those. " + DATELINE}]
    m, c, ct, pt, fr = ask(msgs); show("trial %d" % t, c, ct, pt, fr, m)

print("\n## B. As the app runs it: lap 1 generated; if a read, lap 2 generated with no new user turn")
for first in FIRST_ASKS:
    print(" >", first)
    for t in range(TRIALS):
        msgs = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": first + " " + DATELINE}]
        m, c, ct, pt, fr = ask(msgs); show("lap1 t%d" % t, c, ct, pt, fr, m)
        if c and c[0]["function"]["name"] == "list_pages":
            args = json.loads(c[0]["function"]["arguments"])
            call = {"id": "c1", "type": "function", "function": c[0]["function"]}
            msgs += [{"role": "assistant", "content": "", "tool_calls": [call]},
                     {"role": "tool", "tool_call_id": "c1", "name": "list_pages", "content": listing(args.get("matching", ""))}]
            m2, c2, ct2, pt2, fr2 = ask(msgs); show("lap2 t%d" % t, c2, ct2, pt2, fr2, m2)
            if c2 and c2[0]["function"]["name"] == "list_pages":
                pass

print("\n## C. Scripted list_pages(matching 'Unit 3'), then 'Publish all of those.'")
for t in range(TRIALS):
    call = {"id": "c1", "type": "function", "function": {"name": "list_pages", "arguments": json.dumps({"course": COURSE, "section": SECTION, "matching": "Unit 3"})}}
    msgs = [{"role": "system", "content": SYSTEM},
            {"role": "user", "content": FIRST_ASKS[0] + " " + DATELINE},
            {"role": "assistant", "content": "", "tool_calls": [call]},
            {"role": "tool", "tool_call_id": "c1", "name": "list_pages", "content": listing("Unit 3")},
            {"role": "user", "content": "Publish all of those. " + DATELINE}]
    m, c, ct, pt, fr = ask(msgs); show("trial %d" % t, c, ct, pt, fr, m)
