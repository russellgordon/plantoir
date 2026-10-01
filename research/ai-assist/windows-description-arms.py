#!/usr/bin/env python3
"""Build the AFTER arm of #352's Windows measurement (the #114 half).

BEFORE is what Windows' local model reads today: plantoir-mcp's live
tools/list (dump-tools.ps1) narrowed by narrow-tools.py, which mirrors
AssistAgent.NarrowToLocal - Briefly() of each Windows description, with the
example course rewritten.

AFTER is the SAME narrowed schemas - every parameter, every argument the
window hides, byte for byte - with ONLY the description of each tool replaced
by contracts/assist-cases.json -> toolDescriptions.descriptions[name], in
full (no Briefly()), the example course rewritten exactly as NarrowToLocal
rewrites it (ICS3U -> the course, in the description only).

Two tools are deliberately LEFT at their BEFORE text, and the reason is
behaviour, not routing (#352 step 1, "behaviour before text"): the pinned
publish_pages sentence says the linked pages come "by themselves - there is
nothing to ask for and no way to leave them out", and unpublish_pages' says
pages ONLY they link to go with them. Windows' tools take an includeLinked
argument that defaults to FALSE, so neither sentence is true here today. A
description that lies to the router lies to Claude Code too; those two wait
for the behaviour (#420).

Usage:
    python research/ai-assist/windows-description-arms.py BEFORE.json AFTER.json [COURSE]

COURSE: pass it when BEFORE was narrowed with a course (teachers-say runs);
leave it off when BEFORE kept ICS3U (trimmed-surface runs with --real-course).
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BEHAVIOUR_BLOCKED = {"publish_pages", "unpublish_pages"}
EXAMPLE_COURSE = "ICS3U"


def main():
    before_path, after_path = sys.argv[1], sys.argv[2]
    course = sys.argv[3] if len(sys.argv) > 3 else None
    tools = json.load(open(before_path, encoding="utf-8-sig"))
    pinned = json.load(open(ROOT / "contracts/assist-cases.json", encoding="utf-8"))["toolDescriptions"]["descriptions"]
    changed, kept, missing = [], [], []
    for tool in tools:
        function = tool["function"]
        name = function["name"]
        if name in BEHAVIOUR_BLOCKED:
            kept.append(name)
            continue
        if name not in pinned:
            missing.append(name)
            continue
        text = pinned[name]
        if course:
            text = text.replace(EXAMPLE_COURSE, course)
        if function["description"] != text:
            changed.append(name)
        function["description"] = text
    if missing:
        sys.exit("no pinned description for %s - the contract and the surface disagree; measure nothing" % missing)
    with open(after_path, "w", encoding="utf-8") as out:
        json.dump(tools, out, ensure_ascii=False, indent=1)
    print("AFTER arm: %d tools; description changed on %d: %s" % (len(tools), len(changed), ", ".join(changed)))
    print("left at BEFORE text (behaviour first): %s" % ", ".join(kept))


if __name__ == "__main__":
    main()
