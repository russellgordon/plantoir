#!/usr/bin/env python3
"""Build the arms of #420's Windows measurement (parity bundle 10, step b).

#352 (bundle 9) moved every Windows tool description to the contract's one
description per tool EXCEPT publish_pages and unpublish_pages, held because
their contract sentences promise behaviour Windows did not have: linked pages
came along only when the model set `includeLinked`, which defaulted to false.
#420 step (a) made the behaviour unconditional and took the flag off the four
tools. Step (b) - this measurement - decides whether the two descriptions now
move to the contract's text.

BEFORE is the local surface on `dev` e313e770 as shipped: plantoir-mcp's
tools/list narrowed by narrow-tools.py (STILL_SHORTENED = publish_pages,
unpublish_pages), so those two read Briefly() of their Windows text and still
declare `includeLinked` (boolean, default false).

AFTER is what the local model will read once both steps are in: the SAME
narrowed schemas, byte for byte, except on publish_pages and unpublish_pages,
where (i) the `includeLinked` property is removed (and from `required`, were
it there), and (ii) the description is the contract's
toolDescriptions.descriptions[name] in full (no Briefly()), the example
course rewritten exactly as NarrowToLocal rewrites it (in the description
only).

MIDDLE (registered as CONDITIONAL - run only if AFTER fails a criterion) is
(i) alone: the flag gone, the held descriptions kept. It decides nothing: the
behaviour half lands either way (bundle 10 ruling Q3); it says, for the
record, which half of the change a failure came from.

Usage:
    python research/ai-assist/windows-description-arms-420.py BEFORE.json AFTER.json MIDDLE.json [COURSE]

COURSE: pass it when BEFORE was narrowed with a course (teachers-say runs);
leave it off when BEFORE kept ICS3U (trimmed-surface runs with --real-course).
"""
import copy
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHANGED = ("publish_pages", "unpublish_pages")
EXAMPLE_COURSE = "ICS3U"


def without_the_flag(function):
    parameters = function["parameters"]
    if "includeLinked" not in parameters.get("properties", {}):
        sys.exit("%s declares no includeLinked in BEFORE - this is not dev's surface; measure nothing" % function["name"])
    del parameters["properties"]["includeLinked"]
    if "required" in parameters:
        parameters["required"] = [name for name in parameters["required"] if name != "includeLinked"]


def main():
    before_path, after_path, middle_path = sys.argv[1], sys.argv[2], sys.argv[3]
    course = sys.argv[4] if len(sys.argv) > 4 else None
    before = json.load(open(before_path, encoding="utf-8-sig"))
    pinned = json.load(open(ROOT / "contracts/assist-cases.json", encoding="utf-8"))["toolDescriptions"]["descriptions"]

    after, middle = copy.deepcopy(before), copy.deepcopy(before)
    seen = set()
    for arm, converge in ((after, True), (middle, False)):
        for tool in arm:
            function = tool["function"]
            if function["name"] not in CHANGED:
                continue
            seen.add(function["name"])
            without_the_flag(function)
            if converge:
                text = pinned[function["name"]]
                if course:
                    text = text.replace(EXAMPLE_COURSE, course)
                function["description"] = text
    if seen != set(CHANGED):
        sys.exit("BEFORE lacks %s; measure nothing" % (set(CHANGED) - seen))

    for path, arm in ((after_path, after), (middle_path, middle)):
        with open(path, "w", encoding="utf-8") as out:
            json.dump(arm, out, ensure_ascii=False, indent=1)
    differing = [b["function"]["name"] for b, a in zip(before, after) if b != a]
    print("AFTER and MIDDLE: %d tools; differ from BEFORE on: %s" % (len(after), ", ".join(differing)))


if __name__ == "__main__":
    main()
