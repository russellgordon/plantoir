#!/usr/bin/env python3
"""Convert plantoir-mcp tools/list output to the OpenAI-shaped, narrowed
surface the local model actually sees.

This MIRRORS three things in `AssistAgent` (windows-app/Plantoir.Core/Assist/
AssistAgent.cs), and is only worth running while it still does:

  * `ForTheLocalModel` - which tools survive the narrowing,
  * `Briefly()`        - the trigger phrasings plus one sentence of what it does,
  * `MakeExamplesReal()` + the description's own `.Replace(ExampleCourse, ...)`
                       - the schemas' example course becomes THIS window's
                         course, which was measured at fifty-four trials and
                         not one wrong course.

**The name list is pinned by a test**, because it has already drifted once and
the drift was invisible. The dates matter, so that the results files in this
folder are not tarred with it:

  * committed 2026-08-14 (18d24fa7) holding FIFTEEN names, which was correct
    then. `macos-native-results.txt`, `macos-native-10-trial-comparison.txt`
    and `trimmed-surface-results.txt` were measured through it in that window
    and are sound.
  * `AssistAgent.ForTheLocalModel` dropped to THIRTEEN on 2026-08-17
    (4089c752) - out went four `plan_` tools, in came
    `read_remembered_timetable` and `add_next_class` - and this file was not
    followed through.
  * so any score taken through it AFTER 2026-08-17 was a score for a surface
    the app does not ship, which routing-suite.py's own docstring calls worse
    than no score. Found 2026-09-08, by a change that wanted to measure the
    two tools the stale list happened to be missing.

`NarrowToolsMirrorTests` in Plantoir.Tests now fails if the two lists differ.

Usage:

    python research/ai-assist/narrow-tools.py <tools.json> <out.json> [COURSE]

The course code is OPTIONAL, and the default is deliberately the UNSUBSTITUTED
surface. `trimmed-surface-suite.py` does its own substitution behind
`--real-course`, and the finding in its docstring - a request naming no course
copied ICS3U out of the examples 9 trials out of 9 - needs the un-rewritten
surface as its control. Making it unconditional here would silently delete
that control and turn `--real-course` into a no-op. Pass the course when you
want the shipped surface; leave it off when you are measuring the difference.

(One divergence, noted rather than fixed: `trimmed-surface-suite.replace_examples`
rewrites EVERY string, where `MakeExamplesReal` and this file rewrite only
fields named `description`. It is left alone because its results are dated
records, the same reason routing-suite.py is marked historical.)
"""
import json
import sys

# MIRROR of AssistAgent.ForTheLocalModel. Pinned by NarrowToolsMirrorTests.
FOR_THE_LOCAL_MODEL = {
    # Finding your way about.
    "list_pages", "read_page", "check_section",
    # Publishing a class, which is the commonest request by a wide margin.
    "publish_class_on",
    # Publishing and unpublishing pages by name.
    "publish_pages", "unpublish_pages",
    # Seeing the result, and taking it back.
    "rebuild_preview", "undo_last_change",
    # Putting it in front of students, now or at half six tomorrow.
    "deploy_section", "schedule_deploy", "cancel_scheduled_deploy",
    # Timetable and next class.
    "read_remembered_timetable", "add_next_class",
}

# MIRROR of AssistAgent.ExampleCourse.
EXAMPLE_COURSE = "ICS3U"


def briefly(description):
    kept = []
    end = description.find('". ')
    if description.startswith("TEACHERS SAY:") and end > 0:
        kept.append(description[:end + 2])
        description = description[end + 3:]
    stop = description.find(". ")
    kept.append(description[:stop + 1] if stop > 0 else description)
    return " ".join(kept).strip()


def make_examples_real(node, course_code):
    """MIRROR of AssistAgent.MakeExamplesReal - only fields NAMED description."""
    if isinstance(node, dict):
        text = node.get("description")
        if isinstance(text, str) and EXAMPLE_COURSE in text:
            node["description"] = text.replace(EXAMPLE_COURSE, course_code)
        for value in node.values():
            make_examples_real(value, course_code)
    elif isinstance(node, list):
        for item in node:
            make_examples_real(item, course_code)


if len(sys.argv) < 3:
    sys.exit("usage: narrow-tools.py <tools.json> <out.json> [COURSE]")

tools_path, out_path = sys.argv[1], sys.argv[2]
course_code = sys.argv[3] if len(sys.argv) > 3 else None

raw = json.load(open(tools_path, encoding="utf-8-sig"))
tools = raw["result"]["tools"]
kept = []
for tool in tools:
    if tool["name"] not in FOR_THE_LOCAL_MODEL:
        continue
    parameters = tool.get("inputSchema", {"type": "object"})
    described = briefly(tool.get("description", ""))
    if course_code is not None:
        make_examples_real(parameters, course_code)
        described = described.replace(EXAMPLE_COURSE, course_code)
    kept.append({
        "type": "function",
        "function": {
            "name": tool["name"],
            "description": described,
            "parameters": parameters,
        },
    })
json.dump(kept, open(out_path, "w", encoding="utf-8"), indent=1)

full = [t["name"] for t in tools]
print("server tools: %d, narrowed: %d, example course: %s"
      % (len(full), len(kept), course_code or "left as " + EXAMPLE_COURSE))
print("kept:", ", ".join(t["function"]["name"] for t in kept))
missing = FOR_THE_LOCAL_MODEL - set(full)
if missing:
    print("IN THE SET BUT NOT ON THE SERVER:", ", ".join(sorted(missing)))
chars = len(json.dumps(kept))
print("narrowed surface: %d chars (~%d tokens at 3.6 chars/token)" % (chars, chars / 3.6))
