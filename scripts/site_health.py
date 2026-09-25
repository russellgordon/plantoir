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
import re

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


_PLACEHOLDER = re.compile(r"\{([A-Za-z]+)\}")


def filled(text: str, fill: dict) -> str:
    """
    `text` with each `{name}` in `fill` replaced, in ONE pass.

    Not `str.format`, so a sentence containing ordinary braces cannot become a
    format string by accident. And not one `replace` after another, because
    since #246 a value can be a PAGE NAME a teacher typed: a page called
    "{course} notes" must be named as it is, not expanded into the course
    code. A single pass never re-reads what it has just put in. A placeholder
    `fill` does not name is left exactly as written.
    """
    def one(match: re.Match) -> str:
        key = match.group(1)
        if key in fill:
            return str(fill[key])
        return match.group(0)

    return _PLACEHOLDER.sub(one, text)


def finding(name: str, course: str, section, checks: dict = None,
            extra_fill: dict = None, sentence_key: str = "sentence",
            detail_suffix: str = "") -> Finding:
    """
    One finding, worded from the contract.

    `{course}` and `{section}` always; `extra_fill` for the placeholders one
    check has of its own (`pageSettingsUnreadable`'s page, count and list).
    `sentence_key` picks which of the entry's sentences heads the finding, and
    `detail_suffix` is appended to the detail after it is filled, so nothing in
    it is expanded.
    """
    table = checks if checks is not None else _checks_by_name()
    entry = table[name]
    fill = {"course": str(course), "section": str(section)}
    if extra_fill:
        for key, value in extra_fill.items():
            fill[key] = str(value)

    return Finding(
        name=name,
        sentence=filled(entry[sentence_key], fill),
        detail=filled(entry["detail"], fill) + detail_suffix,
        fixable=bool(entry["fixable"]),
        course=course,
        section=section,
    )


# How many pages a `pageSettingsUnreadable` finding names before it says "and
# N more": the detail is ONE line of the console and of the dialog.
MOST_PAGES_NAMED = 10


def unreadable_settings_finding(facts: dict, course: str, section, table: dict) -> Finding:
    """
    ONE finding for every page of this build whose settings could not be read
    (#246), never one per page. Both apps key a finding's identity on its name,
    course and section (the mac's `SiteHealthFinding.id`, Windows'
    `SiteHealthFinding.Identity`), so two per-page findings would collide.

    Each page's name is filled into `pageWithLine` or `pageWithoutLine` on its
    own, and the list is then put into `{pages}` in a single pass, so a page
    named with braces is named as it is.
    """
    entry = table["pageSettingsUnreadable"]
    pages = facts.get("unreadable_pages") or []
    named = []
    for page in pages[:MOST_PAGES_NAMED]:
        line = page.get("line")
        if line is None:
            named.append(filled(entry["pageWithoutLine"], {"page": page.get("page", "")}))
        else:
            named.append(filled(entry["pageWithLine"], {"page": page.get("page", ""), "line": line}))
    if len(pages) > MOST_PAGES_NAMED:
        named.append(filled(entry["andMore"], {"count": len(pages) - MOST_PAGES_NAMED}))
    extra = {
        "page": pages[0].get("page", "") if pages else "",
        "count": len(pages),
        "pages": ", ".join(named),
    }
    suffix = ""
    if facts.get("front_page_unreadable"):
        suffix = " " + filled(entry["frontPage"], {"course": str(course), "section": str(section)})
    return finding(
        "pageSettingsUnreadable", course, section, table,
        extra_fill=extra,
        sentence_key="sentence" if len(pages) == 1 else "sentenceForSeveral",
        detail_suffix=suffix,
    )


def findings(facts: dict, course: str, section) -> list:
    """
    Every finding for one section's build.

    `facts` is deliberately plain data, worked out by the caller — this module
    imports nothing from `build_site` and touches no filesystem of its own,
    which is what lets it be tested without building a site. The keys:

    * `coverage_wanted`      — is the map switched on for this section?
    * `curriculum_found`     — did `_find_curriculum_folder` return a folder
                               that actually holds expectation pages?
    * `class_pages_found`    — did the section have any class pages at all?
    * `graded_folders_found` — does any folder on disk count for marks?
    * `media_target_exists`  — does the COURSE-level `Media` folder exist? Not
                               `content/Media`, which every build recreates.
    * `section_index_exists`
    * `hand_written_coverage_page`
    * `unreadable_pages`     — [{"page": name in the course folder, "line":
                               n or None}], the pages hidden because their
                               settings could not be read (#246)
    * `front_page_unreadable` — is the section's front page one of them?
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
    graded_folders_found = facts.get("graded_folders_found", True)

    if coverage_wanted and not curriculum_found and class_pages_found:
        found.append(finding("curriculumCoverageFoundNothing", course, section, table))

    if coverage_wanted and not class_pages_found and curriculum_found:
        found.append(finding("courseTeachesNothing", course, section, table))

    if coverage_wanted and curriculum_found and not graded_folders_found:
        found.append(finding("noGradedFolders", course, section, table))

    if not facts.get("media_target_exists"):
        found.append(finding("mediaFolderMissing", course, section, table))

    if not facts.get("section_index_exists"):
        found.append(finding("sectionIndexMissing", course, section, table))

    if facts.get("hand_written_coverage_page"):
        found.append(finding("handWrittenCoveragePage", course, section, table))

    # LAST, so the findings above keep their places — the contract's marker
    # examples and #153's console cases are captured in this order.
    if facts.get("unreadable_pages"):
        found.append(unreadable_settings_finding(facts, course, section, table))

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
