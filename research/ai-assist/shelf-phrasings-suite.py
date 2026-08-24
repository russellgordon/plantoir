#!/usr/bin/env python3
"""Every phrasing the assistant window offers, word for word, against the
shipped 13-tool surface — with the app's own system prompt AND its dateline.

The dateline is the part a first attempt at this got wrong, and the mistake is
worth keeping: measured WITHOUT it, "Publish the class on Monday" resolved to a
date a month away in all ten trials, and the card was nearly dropped for a
fault that belonged to the harness. `AssistAgent.say` appends
`AssistAgent.dateline()` to the user message; a probe that leaves it off is not
measuring the shipping configuration.
"""
import datetime, json, sys, time, urllib.request

TRIALS = int(sys.argv[1]) if len(sys.argv) > 1 else 10
TOOLS = json.load(open(sys.argv[2]))
TODAY = datetime.date(2026, 8, 16)
DATELINE = "(Today is %s, a %s.)" % (TODAY.isoformat(), TODAY.strftime("%A"))
ENDPOINT = "http://127.0.0.1:8099/v1/chat/completions"

# STALE, 2026-08-24: AssistAgent's system prompt gained two sentences
# (undo_last_change scope, no-delete-tool) after this suite's last real run —
# see conversational-residue-results.txt. Frozen here on purpose, matching
# the shelf-phrasings-results.txt this SYSTEM produced; edit both together
# if this suite is ever re-run, rather than silently drifting from either.
SYSTEM = ("You are Plantoir's assistant, helping a teacher with ICS3U section 1. "
 "Choose exactly one tool at a time and fill in its arguments from what the teacher said. "
 "Publishing and unpublishing are safe to do straight away — every change is backed up "
 "and undo_last_change takes it back — so do what was asked without asking permission first. "
 "Never guess a course, a section, a page title or a date — if you are not certain, look it "
 "up or ask. If no tool fits, say so plainly instead of inventing one.\n"
 "PUBLISHING a page decides whether students can see it in the site. "
 "DEPLOYING sends the whole site to the web. They are different acts. "
 "After a change, Plantoir opens the preview by itself so the teacher can look it over. "
 "Do not offer to deploy unless they ask; when they do ask, say plainly that deploying puts "
 "the change in front of students immediately and that reviewing the preview first is the "
 "safer order — then do as they decide.")

# (tool, phrasing, matched-in-code?, expected argument fragment or None)
CASES = [
    ("publish_pages",              "Publish Unit 2, Day 3",                        False, "Unit 2, Day 3"),
    ("publish_class_on",           "Publish tomorrow's class",                     True,  "2026-08-17"),
    ("publish_class_on",           "Publish the class on Monday",                  False, "2026-08-17"),
    ("unpublish_pages",            "Unpublish Unit 2, Day 3",                      False, "Unit 2, Day 3"),
    ("undo_last_change",           "Undo that",                                    True,  None),
    ("check_section",              "What would students see in this section right now?", True, None),
    ("rebuild_preview",            "Preview",                                      True,  None),
    ("add_next_class",             "Add the next class page",                      True,  None),
    ("read_remembered_timetable",  "What dates am I teaching?",                    True,  None),
    ("deploy_section",             "Deploy now",                                   True,  None),
    ("schedule_deploy",            "Deploy at 6:30 AM",                            False, "06:30"),
    ("cancel_scheduled_deploy",    "Cancel scheduled deploy",                      False, None),
]

def ask(prompt):
    body = json.dumps({"messages":[{"role":"system","content":SYSTEM},
            {"role":"user","content":"%s %s" % (prompt, DATELINE)}],
        "tools":TOOLS,"tool_choice":"auto","temperature":0.0,"max_tokens":400}).encode()
    req = urllib.request.Request(ENDPOINT, data=body, headers={"Content-Type":"application/json"})
    started = time.time()
    with urllib.request.urlopen(req, timeout=180) as r:
        d = json.load(r)
    c = (d["choices"][0]["message"].get("tool_calls") or [{}])[0].get("function", {})
    return c.get("name"), c.get("arguments", ""), time.time() - started

print("EVERY SHELF PHRASING, AGAINST THE SHIPPED SURFACE")
print("Qwen3-4B Q4_K_M, ctx 16384, --reasoning off --reasoning-budget 0, temp 0, M4 Pro 48 GB")
print("System prompt and dateline as AssistAgent sends them. %d trials each.\n" % TRIALS)
tot = totok = argtot = argok = 0
for want, prompt, incode, wantArg in CASES:
    ok = aok = 0; secs = []; wrong = {}
    for _ in range(TRIALS):
        name, args, took = ask(prompt)
        secs.append(took)
        if name == want:
            ok += 1
            if wantArg is None or wantArg.lower() in args.lower():
                aok += 1
        else:
            wrong[name] = wrong.get(name, 0) + 1
    tot += TRIALS; totok += ok
    if wantArg is not None:
        argtot += TRIALS; argok += aok
    mark = "code" if incode else "    "
    argnote = "" if wantArg is None else "  args %2d/%d" % (aok, TRIALS)
    print("[%s] %-28s %2d/%d %5.1fs%s%s" % (mark, want, ok, TRIALS, sum(secs)/len(secs), argnote,
          "" if not wrong else "  WRONG: %s" % wrong))
    print("       “%s”" % prompt)
print("\nROUTING %d/%d   ARGUMENTS %d/%d" % (totok, tot, argok, argtot))
print("[code] = matched in AssistCardCommand and never sent to the model;")
print("         probed anyway, to record what would happen if it were.")
