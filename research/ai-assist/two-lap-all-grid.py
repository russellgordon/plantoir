"""Arm A of twolap.py across courses and dates: scripted unfiltered list_pages
(first 60 real relative paths of that course's example payload, laid out as
installed), then 'Publish all of those.' One greedy trial per cell."""
import json, sys, pathlib, urllib.request, re, datetime
ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
PORT = sys.argv[1]
TOOLS0 = json.load(open(ROOT / "contracts/assist-cases.json"))["toolSchemas"]["local"]
src = (ROOT / "mac-app/QuartzTeachers/Models/Assist/AssistAgent.swift").read_text()
marker = "static func systemPrompt(course: String, section: Int) -> String {"
start = src.index(marker); opening = src.index('"""', start) + 3; closing = src.index('"""', opening)
indent = len(src[:closing].rsplit("\n", 1)[1]); T = ""
for line in src[opening:closing].split("\n")[1:-1]:
    body = line[indent:] if line.startswith(" " * indent) else line.lstrip()
    T += body[:-1] if body.endswith("\\") else body + "\n"
def real(node, c):
    if isinstance(node, dict): return {k: real(v, c) for k, v in node.items()}
    if isinstance(node, list): return [real(v, c) for v in node]
    if isinstance(node, str): return node.replace("ICS3U", c)
    return node
def paths_for(code, shown_as):
    base = ROOT / "support/example_content" / code; out = []
    for f in (base / "shared").rglob("*.md"): out.append("courses/%s/%s" % (shown_as, f.relative_to(base / "shared")))
    for f in (base / "per_section").rglob("*.md"): out.append("courses/%s/section1/%s" % (shown_as, f.relative_to(base / "per_section")))
    out.sort(key=lambda p: p.lower()); return out
def ask(msgs, tools):
    p = {"model": "local", "temperature": 0.0, "messages": msgs, "tools": tools, "tool_choice": "auto", "stream": False, "max_tokens": 512}
    d = json.loads(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:%s/v1/chat/completions" % PORT, data=json.dumps(p).encode(), headers={"Content-Type": "application/json"}), timeout=600).read())
    m = d["choices"][0]["message"]; c = m.get("tool_calls") or []
    return (c[0]["function"]["name"], c[0]["function"]["arguments"]) if c else (None, m.get("content")), d["usage"]["completion_tokens"], d["choices"][0]["finish_reason"]
courses = sys.argv[2].split(",") if len(sys.argv) > 2 else ["ICS3U", "MCR3U", "SBI3U", "ENG2D", "TEJ3M", "CHC2D"]
dates = [datetime.date(2026, 9, 19), datetime.date(2026, 9, 26), datetime.date(2026, 10, 7)]
followups = ["Publish all of those.", "Publish them all.", "Yes, publish everything in that list."]
tally = {}
for code in courses:
    for shown in (code, "VVH2O"):
        ps = paths_for(code, shown); tools = real(TOOLS0, shown)
        system = T.rstrip("\n").replace("\\(course)", shown).replace("\\(section)", "1")
        detail = "\n".join(ps[:60]) + ("\n\n…and %d more of %d. Pass `matching` to narrow this down." % (len(ps) - 60, len(ps)) if len(ps) > 60 else "")
        for day in dates:
            dl = "(Today is %s, a %s.)" % (day.isoformat(), day.strftime("%A"))
            for fu in followups:
                call = {"id": "c1", "type": "function", "function": {"name": "list_pages", "arguments": json.dumps({"course": shown, "section": 1})}}
                msgs = [{"role": "system", "content": system},
                        {"role": "user", "content": "Publish everything in Unit 3 for %s section 1. %s" % (shown, dl)},
                        {"role": "assistant", "content": "", "tool_calls": [call]},
                        {"role": "tool", "tool_call_id": "c1", "name": "list_pages", "content": detail},
                        {"role": "user", "content": fu + " " + dl}]
                (name, args), ct, fr = ask(msgs, tools)
                if name == "publish_pages":
                    try: pages = json.loads(args).get("pages")
                    except Exception: pages = "<unparsed>"
                    if isinstance(pages, str) and pages.strip().lower() in ("all", "everything", "*", "all pages", "all of those", "all of them"):
                        kind = "ALL-WORD:" + pages
                    elif fr == "length": kind = "cut-off list"
                    elif isinstance(pages, str) and ";" in pages: kind = "listed titles"
                    else: kind = "other:" + str(pages)[:40]
                else:
                    kind = "tool=%s" % name
                tally[kind] = tally.get(kind, 0) + 1
                print("%s as %s %s %-40s -> %-24s %s tok=%s %s" % (code, shown, day, fu, kind, "" if name else "", ct, fr), flush=True)
print("\nTALLY", json.dumps(tally, indent=1))
