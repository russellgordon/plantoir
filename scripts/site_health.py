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

    `{course}` and `{section}` are filled in by plain replacement rather than
    `str.format`, so a sentence containing ordinary braces cannot become a
    format string by accident. The replacements are applied in a fixed order
    and are not re-scanned, so a value that itself contained a placeholder
    would not be expanded twice.
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

    # Each of the two coverage checks needs the OTHER half of the map to be
    # present before it means anything. A brand-new course has an empty
    # curriculum folder and an empty class folder on day one — the wizard
    # creates both and switches the map on — so an unconditional pair of
    # warnings would fire on every build of a course nobody has broken. That
    # is the nagging this feature must not do: a warning a teacher cannot act
    # on is one they learn to dismiss, and they will dismiss it when it counts.
    #
    # So: complain that the expectations are missing only once there are
    # lessons, and complain that the lessons are missing only once there are
    # expectations. A course with neither has not been written yet and is told
    # nothing.
    coverage_wanted = facts.get("coverage_wanted")
    curriculum_found = facts.get("curriculum_found")
    class_pages_found = facts.get("class_pages_found")

    if coverage_wanted and not curriculum_found and class_pages_found:
        found.append(finding("curriculumCoverageFoundNothing", course, section, table))

    if coverage_wanted and not class_pages_found and curriculum_found:
        found.append(finding("courseTeachesNothing", course, section, table))

    if not facts.get("media_target_exists"):
        found.append(finding("mediaFolderMissing", course, section, table))

    if not facts.get("section_index_exists"):
        found.append(finding("sectionIndexMissing", course, section, table))

    if facts.get("hand_written_coverage_page"):
        found.append(finding("handWrittenCoveragePage", course, section, table))

    return found


def announce_or_stay_quiet(facts: dict, course: str, section, printer=print) -> None:
    """
    The whole feature, wrapped so it can never break a build.

    This is the first code in a build that MUST read a contract at run time,
    and `contracts.load` deliberately raises rather than falling back to a
    hidden default. Raising is right for a test; it is wrong here. A stale
    `PLANTOIR_CONTRACTS_DIR` on a native Windows run, or an older image pinned
    with `--image`, would otherwise kill a build that used to succeed —
    AFTER the content merge, with a traceback. A health check that destroys
    the build it was checking is worse than the silent failure it replaces.

    So the checks are advisory in the strongest sense: if they cannot run, the
    build carries on and says so in one plain line.
    """
    try:
        announce(findings(facts, course, section), printer=printer)
    except Exception as error:
        printer(f"\u2139\ufe0f  Skipped the folder checks for {course} "
                f"Section {section}: {error}")


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
