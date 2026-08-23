#!/usr/bin/env python3
"""
What is wrong with a course's folders, in words a teacher can act on.

Certain folder and file names carry behaviour — the curriculum folder, the
folder holding class pages, `Media`, a section's `index.md` — and nothing
stopped a teacher deleting or renaming one in Obsidian or the Finder. The
features then failed SILENTLY. The Curriculum Coverage map is the worst of
them: it still rendered, still looked healthy, and was wrong.

**Why this lives here and not in the apps.** Every check is defined over the
MERGED content tree, which does not exist until a build makes it — so there is
nothing for a check to look at before the run. And a check that only guarded
the GUI button would be bypassed by the assistant, by `Plantoir --mcp-stdio`,
by the launchers, and by the scheduled deploy, which runs from launchd or Task
Scheduler with the app CLOSED and is the case that matters most.

**Every check asks whether the FEATURE produced anything**, never whether a
folder exists. Recreating an empty `Ontario Curriculum` folder does not restore
a teacher's expectation pages — `_find_curriculum_folder` wants a page named
for an expectation code — so an existence check with a Fix button would have
silenced the warning AND left the map missing. A check that can be satisfied
without fixing the problem is worse than no check at all.

The words themselves are NOT written here. They come from
`contracts/shared-rules.json` -> `siteHealth.checks`, so the two apps and this
module cannot word the same problem differently, and so a sentence a teacher
reads has one home like every other sentence in this product.
"""

import json

import contracts

CONTRACT_FILE = "shared-rules"


class Finding:
    """One thing that is wrong, ready to be said out loud."""

    def __init__(self, name: str, sentence: str, detail: str, fixable: bool,
                 course: str, section):
        self.name = name
        self.sentence = sentence
        self.detail = detail
        self.fixable = fixable
        self.course = course
        self.section = section

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "sentence": self.sentence,
            "detail": self.detail,
            "fixable": self.fixable,
            "course": self.course,
            "section": self.section,
        }


def _checks_by_name() -> dict:
    table = {}
    for entry in contracts.section(CONTRACT_FILE, "siteHealth", "checks"):
        table[entry["name"]] = entry
    return table


def marker_prefix() -> str:
    return contracts.section(CONTRACT_FILE, "siteHealth", "marker", "prefix")


def finding(name: str, course: str, section, checks: dict = None) -> Finding:
    """
    One finding, worded from the contract.

    `{course}` and `{section}` are filled in; nothing else is substituted, so a
    sentence can contain ordinary braces without becoming a format string by
    accident.
    """
    table = checks if checks is not None else _checks_by_name()
    entry = table[name]
    fill = {"course": str(course), "section": str(section)}

    def worded(text: str) -> str:
        for key, value in fill.items():
            text = text.replace("{" + key + "}", value)
        return text

    return Finding(
        name=name,
        sentence=worded(entry["sentence"]),
        detail=worded(entry["detail"]),
        fixable=bool(entry["fixable"]),
        course=course,
        section=section,
    )


def findings(facts: dict, course: str, section) -> list:
    """
    Every finding for one section's build.

    `facts` is deliberately plain data, worked out by the caller — this module
    imports nothing from `build_site` and touches no filesystem of its own,
    which is what lets it be tested without building a site. The keys:

    * `coverage_wanted`     — is the map switched on for this section?
    * `curriculum_found`    — did `_find_curriculum_folder` return a folder
                              that actually holds expectation pages?
    * `class_pages_found`   — did the section have any class pages at all?
    * `media_target_exists` — does the COURSE-level `Media` folder exist? Not
                              `content/Media`, which every build recreates.
    * `section_index_exists`
    * `hand_written_coverage_page`
    """
    table = _checks_by_name()
    found = []

    if facts.get("coverage_wanted") and not facts.get("curriculum_found"):
        found.append(finding("curriculumCoverageFoundNothing", course, section, table))

    # Only worth saying when the map is on: with the map off, nothing depends
    # on knowing which pages the course teaches, and a warning about it would
    # be noise a teacher cannot act on.
    if facts.get("coverage_wanted") and not facts.get("class_pages_found"):
        found.append(finding("courseTeachesNothing", course, section, table))

    if not facts.get("media_target_exists"):
        found.append(finding("mediaFolderMissing", course, section, table))

    if not facts.get("section_index_exists"):
        found.append(finding("sectionIndexMissing", course, section, table))

    if facts.get("hand_written_coverage_page"):
        found.append(finding("handWrittenCoveragePage", course, section, table))

    return found


def announce(found: list, printer=print) -> None:
    """
    Say each finding twice: once for a person reading the console, and once as
    a machine-readable line the apps parse out of the transcript they are
    already reading.

    The teacher-facing SENTENCE travels in the machine line rather than being
    re-authored on each platform, so the two apps cannot word the same problem
    differently.
    """
    if not found:
        return
    prefix = marker_prefix()
    printer("")
    for item in found:
        printer(f"⚠️  {item.sentence}")
        printer(f"   {item.detail}")
        printer(f"{prefix} {json.dumps(item.as_dict(), ensure_ascii=False)}")
