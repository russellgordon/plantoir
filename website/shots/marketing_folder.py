#!/usr/bin/env python3
"""The marketing working folder, ``~/Plantoir Marketing``: set up once, kept, reused.

Every v1.4.0 scene on plantoir.app is taken in ONE working folder that is
Russell's to keep: ICS3U (sections 1 and 2) and ICS4U (section 1), made from
their ready-made content by the app's own new-course panel, then REVISED here —
never the shipped payload — so BOTH courses also answer to AP Computer Science
Principles, each with two curriculum folders:

1. a **College Board Curriculum** folder in each course, one page per learning
   objective in the College Board's own words (``college_board.py``; the words
   never enter this repository), kept out of the sidebar like ``Curriculum``;
2. each activity the course's correlation names (``csp-correlation.json`` for
   ICS3U, ``csp-correlation-ics4u.json`` for ICS4U — ``CSP_COURSES``) gains an
   embed per objective inside its existing ``## Curriculum connection`` block,
   after the Ontario embeds, so the second map counts it exactly as the first
   does (coverage counts TRANSCLUSIONS, never plain links);
3. ICS4U's second curriculum is DECLARED here (``curriculum_folders``), writing
   what ticking the box in Course Settings writes; ICS3U's is declared through
   the app by the curriculum-settings scene, because that is the picture;
4. a **How I Teach** page in ICS3U, in our own words (``marketing/How I Teach.md``);
4a. the code figures' pages (#562): ICS3U's pages that the ready-made course
   has made runnable since the folder was made (#561) are brought up to date
   from the payload (``refresh_runnable_pages``), and two pages of our own are
   planted — a runnable Swift program in ICS4U and a page of self-check
   quizzes in ICS3U (``CODE_PAGES``) — so ``capture.py --code`` photographs
   real runnable blocks and a real quiz;
5. ICS3U and ICS4U each publish to a FOLDER inside the kept folder (ICS3U to
   ``School Web Space``, ICS4U to ``School Web Space/ICS4U``), so the
   scheduled-publish scene needs no account, no network, and nothing either
   course publishes puts the College Board's words on a public site (ruling Q2).

The courses themselves, the reference copy of ICS3U and the declaration of
ICS3U's second curriculum are made THROUGH THE APP (``capture.py`` runs the UI
tests that do it), because those are the features being photographed.

The rules this file keeps, each pinned by ``test_marketing_folder.py``:

- **Idempotent.** Every step says "made" or "already there"; a second run
  changes nothing.
- **Never overwrites a file that differs from what it would write.** The folder
  is kept, and Russell may edit it; a changed file is "left as you changed it".
- **Refuses a folder holding any course it did not make** (anything but ICS3U,
  ICS4U and reference copies of them), which is what makes pointing it at a
  real working folder harmless.
- A page whose curriculum block cannot be found is NAMED and skipped, never
  guessed at.

Standard library only.
"""

from __future__ import annotations

import json
import re
import shutil
from datetime import date, timedelta
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
import sys  # noqa: E402
sys.path.insert(0, str(HERE))
import demo_folders  # noqa: E402

DEFAULT_FOLDER = Path.home() / "Plantoir Marketing"
CORRELATION_FILE = HERE / "csp-correlation.json"
ICS4U_CORRELATION_FILE = HERE / "csp-correlation-ics4u.json"
HOW_I_TEACH_SOURCE = HERE / "marketing" / "How I Teach.md"
HOW_I_TEACH_NAME = "How I Teach.md"

# The pages the code figures on plantoir.app's Code page are taken of (#562)
# that no ready-made course carries: (course, the page's place in it, its
# source in marketing/). No payload has Swift (ruling Q5 of #561/#562: the
# Swift demo page lives only in the marketing ICS4U), and no payload has a
# quiz yet (#563 shipped the feature, not content). Planted like How I Teach:
# written when absent, never over a page somebody changed.
CODE_PAGES: list[tuple[str, str, Path]] = [
    ("ICS4U", "Programs/Reading Input in Swift.md", HERE / "marketing" / "Reading Input in Swift.md"),
    ("ICS3U", "Exercises/Check Your Loops.md", HERE / "marketing" / "Check Your Loops.md"),
]
# The ready-made course whose runnable pages (#561) are brought into the
# kept folder, and where the repository keeps it.
RUNNABLE_COURSE = "ICS3U"
REPO = HERE.parent.parent
SUPPORT = REPO / "support"

# The courses the folder holds, with the sections the app is asked to make,
# and the AP CSP half of each: read from marketing/folders.json, the one place
# both demo folders are described (#445), so this file, capture.py, the
# Windows capture and the UI tests cannot disagree about them.
# ICS4U is there so Copy a Page has somewhere to copy TO (ruling Q4).
#
# `correlation`: the course's correlation (data, never code). `declare`:
# whether this set-up writes the second curriculum into `curriculum_folders`.
# ICS3U's is ticked through Course Settings by the curriculum-settings scene,
# because that tick is the picture; no scene photographs ICS4U's, so the file
# step writes it. `publish_to`: the folder, inside the kept folder, the course
# publishes to. EVERY course here publishes to a folder and never to a public
# site, because its pages print the College Board's words, which were cleared
# for Russell's own folder and not for the web (ruling Q2). ICS4U gets a
# folder of its own: a folder destination writes `<folder>/section<N>` with
# `rsync --delete` (deploy.sh), so two courses sharing one folder would
# overwrite each other's section 1.
def _courses_from_spec() -> tuple[list[dict], list[dict]]:
    courses: list[dict] = []
    csp: list[dict] = []
    for course in demo_folders.marketing_courses():
        courses.append({"code": course["code"], "sections": demo_folders.sections_as_typed(course["sections"])})
        csp.append({"code": course["code"], "correlation": HERE / course["collegeBoardCorrelation"],
                    "declare": course["declaresCollegeBoardHere"], "publish_to": course["publishTo"]})
    return courses, csp


COURSES, CSP_COURSES = _courses_from_spec()
CURRICULUM_COURSE = demo_folders.load_spec()["marketing"]["curriculumCourse"]
COLLEGE_BOARD_FOLDER = demo_folders.load_spec()["marketing"]["collegeBoardPages"]["folder"]
# Where the scheduled-publish scene publishes: ICS3U's folder, inside the kept
# folder. `deploy_target` spells a folder destination "local_folder"
# (contracts/file-formats.json -> courseConfigKeys).
PUBLISH_FOLDER_NAME = "School Web Space"
FOLDER_DESTINATION = "local_folder"

CURRICULUM_HEADING = re.compile(r"^##\s+Curriculum connection\s*$")
ANY_HEADING = re.compile(r"^#{1,6}\s")
EMBED = re.compile(r"^!\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]\s*$")


# Written when this set-up creates the folder; its absence on a folder that
# already holds courses means somebody else made it.
MARKER_NAME = ".plantoir-marketing-folder"


class ForeignFolder(Exception):
    """The folder holds a course this script did not make."""


@dataclass
class Report:
    """What each step did, in words, for the summary a run prints."""
    lines: list[str] = field(default_factory=list)
    named_and_skipped: list[str] = field(default_factory=list)
    made: int = 0
    already_there: int = 0
    left_as_changed: int = 0

    def note(self, outcome: str, what: str) -> None:
        self.lines.append(f"{outcome}: {what}")
        if outcome == "made":
            self.made += 1
        elif outcome == "already there":
            self.already_there += 1
        elif outcome == "left as you changed it":
            self.left_as_changed += 1

    def skip(self, what: str) -> None:
        self.named_and_skipped.append(what)
        self.lines.append(f"named and skipped: {what}")


# ---------- The guard ----------

def read_config(course_dir: Path) -> dict | None:
    path = course_dir / "course_config.json"
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def refuse_foreign_courses(folder: Path) -> None:
    """Stop unless every course in the folder is one this script makes.

    Allowed: a course folder named for ICS3U or ICS4U, and a REFERENCE copy of
    either (`kept_for_reference` true — whatever its folder is called, since
    Keep a Copy for Reference proposes its own name). Anything else means this
    is somebody's real working folder, and nothing is written to it.
    """
    courses = folder / "courses"
    if not courses.is_dir():
        return
    if not (folder / MARKER_NAME).exists():
        holds_a_course = False
        for entry in courses.iterdir():
            if (entry / "course_config.json").is_file():
                holds_a_course = True
        if holds_a_course:
            raise ForeignFolder(
                f"{folder} already holds courses and was not made by this set-up (no {MARKER_NAME} in it), "
                "so it may be somebody's real working folder — a Computer Science teacher's would hold ICS3U "
                "and ICS4U too. Nothing was changed. Point --marketing-folder at a folder of its own."
            )
    allowed: set[str] = set()
    for course in COURSES:
        allowed.add(course["code"])
    foreign: list[str] = []
    for entry in sorted(courses.iterdir()):
        if not entry.is_dir() or entry.name.startswith(".") or entry.name.startswith("_"):
            continue
        config = read_config(entry)
        code = ""
        if config is not None:
            code = str(config.get("course_code", ""))
        if entry.name in allowed:
            continue
        if config is not None and config.get("kept_for_reference") is True and code in allowed:
            continue
        foreign.append(entry.name)
    if foreign:
        raise ForeignFolder(
            f"{folder} holds courses this set-up did not make ({', '.join(foreign)}), so it looks like "
            "somebody's real working folder. Nothing was changed. Point --marketing-folder at a folder "
            "of its own."
        )


# ---------- Writing without overwriting ----------

def mark_as_ours(folder: Path) -> None:
    """Called when the set-up creates the folder, before any course is in it."""
    folder.mkdir(parents=True, exist_ok=True)
    marker = folder / MARKER_NAME
    if not marker.exists():
        marker.write_text("Made by website/shots/capture.py --provision, for plantoir.app's pictures.\n",
                          encoding="utf-8")


def write_if_absent(path: Path, text: str, report: Report, label: str) -> None:
    if path.exists():
        if path.read_text(encoding="utf-8") == text:
            report.note("already there", label)
        else:
            report.note("left as you changed it", label)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    report.note("made", label)


def update_config(course_dir: Path, change, report: Report, label: str) -> None:
    """Apply `change(config) -> bool` to course_config.json, writing only when
    it changed something, in the file's own two-space shape."""
    path = course_dir / "course_config.json"
    config = read_config(course_dir)
    if config is None:
        report.skip(f"{label} — {path} is missing or cannot be read")
        return
    if change(config):
        path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        report.note("made", label)
    else:
        report.note("already there", label)


# ---------- The steps ----------

def install_college_board_pages(course_dir: Path, pages: dict[str, str], report: Report) -> None:
    """One page per learning objective, written only where missing."""
    folder = course_dir / COLLEGE_BOARD_FOLDER
    for code in sorted(pages):
        write_if_absent(folder / f"{code}.md", pages[code], report,
                        f"{course_dir.name}/{COLLEGE_BOARD_FOLDER}/{code}.md")


def declare_curriculum_folder(course_dir: Path, name: str, report: Report) -> None:
    """Add `name` to the course's `curriculum_folders`, after the folders it
    already declares — what ticking the box in Course Settings writes
    (`CurriculumFoldersOffer.ticking`: the ticked folders first, so the
    primary stays primary). A course with no list yet starts from its legacy
    `curriculum_folder`, then "Curriculum". The build adds the folder to
    `shared_folders` and `expandable` itself when it first meets it."""
    def change(config: dict) -> bool:
        declared = config.get("curriculum_folders")
        if isinstance(declared, list) and declared:
            written: list = list(declared)
        else:
            legacy = config.get("curriculum_folder")
            written = [legacy] if isinstance(legacy, str) and legacy else ["Curriculum"]
        if name in written:
            return False
        written.append(name)
        config["curriculum_folders"] = written
        return True
    update_config(course_dir, change, report, f"{course_dir.name} declares {name} as a second curriculum")


def keep_out_of_sidebar(course_dir: Path, name: str, report: Report) -> None:
    """Add a folder to the course's `hidden` list, as `Curriculum` is."""
    def change(config: dict) -> bool:
        hidden = config.get("hidden")
        if not isinstance(hidden, list):
            hidden = []
        if name in hidden:
            return False
        hidden.append(name)
        config["hidden"] = hidden
        return True
    update_config(course_dir, change, report, f"{name} kept out of the sidebar")


def netlify_site_recorded(course_dir: Path) -> bool:
    """True when deploy.py has recorded a Netlify site for this course."""
    if (course_dir / ".netlify_sites").exists():
        return True
    for marker in course_dir.glob("section*/.netlify_site.json"):
        if marker.is_file():
            return True
    return False


def publish_to_folder(course_dir: Path, destination: Path, report: Report) -> None:
    """Make the course publish to a folder — but only a course that has not
    been pointed anywhere else: a destination somebody chose is left alone."""
    def change(config: dict) -> bool:
        target = str(config.get("deploy_target", ""))
        path = str(config.get("deploy_folder_path", ""))
        if target == FOLDER_DESTINATION and path == str(destination):
            return False
        # Only a course nobody has pointed anywhere. The new-course panel
        # writes "netlify" for every course it makes (measured on the first
        # real set-up, 2026-09-27), so the word alone is not a choice: Netlify
        # counts as chosen once a site is recorded for the course
        # (deploy.py's `.netlify_sites/` marker, or a section's older
        # `.netlify_site.json`). Anything else written out is left alone.
        unchosen: bool = target == "" or (target == "netlify" and not netlify_site_recorded(course_dir))
        if not unchosen or (path and path != str(destination)):
            report.skip(f"{course_dir.name} publishes to {target or 'Netlify'} {path}; left as it is")
            return False
        config["deploy_target"] = FOLDER_DESTINATION
        config["deploy_folder_path"] = str(destination)
        return True
    destination.mkdir(parents=True, exist_ok=True)
    update_config(course_dir, change, report, f"{course_dir.name} publishes to {destination}")


def link_activity(page_path: Path, codes: list[str], report: Report, course: str = "") -> None:
    """Add an embed for each code inside the page's curriculum block.

    After the LAST embed already in the block, one per line with the blank
    line between them the block already uses. A code already embedded there
    is left alone; a page with no block is named and skipped.
    """
    label = f"{course}: {page_path.name}" if course else page_path.name
    if not page_path.is_file():
        report.skip(f"{label} — the page is not in the course")
        return
    text = page_path.read_text(encoding="utf-8")
    lines = text.split("\n")
    heading_index = -1
    for index, line in enumerate(lines):
        if CURRICULUM_HEADING.match(line):
            heading_index = index
            break
    if heading_index == -1:
        report.skip(f"{label} — no '## Curriculum connection' block")
        return

    end = len(lines)
    for index in range(heading_index + 1, len(lines)):
        if ANY_HEADING.match(lines[index]):
            end = index
            break
    present: set[str] = set()
    last_embed = -1
    for index in range(heading_index + 1, end):
        match = EMBED.match(lines[index].strip())
        if match:
            present.add(match.group(1).strip())
            last_embed = index
    if last_embed == -1:
        report.skip(f"{label} — its curriculum block has no embeds to follow")
        return

    missing: list[str] = []
    for code in codes:
        if code not in present:
            missing.append(code)
    if not missing:
        report.note("already there", f"{label} links {', '.join(codes)}")
        return
    addition: list[str] = []
    for code in missing:
        addition.append("")
        addition.append(f"![[{code}]]")
    updated = lines[:last_embed + 1] + addition + lines[last_embed + 1:]
    page_path.write_text("\n".join(updated), encoding="utf-8")
    report.note("made", f"{label} links {', '.join(missing)}")


def load_correlation(path: Path = CORRELATION_FILE) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))["rows"]


def link_activities(course_dir: Path, rows: list[dict], report: Report) -> None:
    for row in rows:
        link_activity(course_dir / f"{row['page']}.md", row["codes"], report, course_dir.name)


def add_how_i_teach(course_dir: Path, report: Report, source: Path = HOW_I_TEACH_SOURCE) -> None:
    write_if_absent(course_dir / HOW_I_TEACH_NAME, source.read_text(encoding="utf-8"), report,
                    f"{course_dir.name}/{HOW_I_TEACH_NAME}")


def add_code_pages(folder: Path, report: Report, earlier_versions=None) -> None:
    """Plant CODE_PAGES (#562): each written where missing, and brought up
    to date while it is still an earlier committed version of its source
    (#587: Check Your Loops gained a fifth question, and a folder made before
    that kept the four-question page). A page somebody changed is left as
    they changed it and named (`demo_folders.plant_page`)."""
    if earlier_versions is None:
        earlier_versions = git_versions
    for code, place, source in CODE_PAGES:
        course_dir = folder / "courses" / code
        if read_config(course_dir) is None:
            report.skip(f"{code} — the course has not been made yet (the app makes it first)")
            continue
        demo_folders.plant_page(course_dir / place, source, report, f"{code}/{place}", earlier_versions)


# ---------- Bringing in what the ready-made course has gained (#562) ----------
#
# The kept folder's ICS3U was installed from the payload before #561 made 83
# of its Python blocks runnable, and installing never overwrites a page, so
# its pages still show plain code (measured 2026-10-17: Warm-Ups/Spot the
# Bug.md had a plain ```python fence and no codeRunner). A page is brought up
# to date ONLY when it is still exactly what an earlier payload would have
# made of it — the same body once the installer's and this set-up's own
# changes are set aside — so a page Russell has changed is left as he changed
# it and named. What the installer changes on the way in: the frontmatter's
# dates and publish states become per-section keys (kept as the folder has
# them; only the `codeRunner: true` line is added, after them, where a fresh
# install puts it) and the %%curriculum-start%% markers go. What this set-up
# adds: the College Board embeds, which `link_activities` puts back after.

CURRICULUM_MARKERS = ("%%curriculum-start%%", "%%curriculum-end%%")
PER_SECTION_KEY = re.compile(r"^(createdSection|publishForSection)\d+\s*:")
CODE_RUNNER_LINE = "codeRunner: true"


def split_frontmatter(text: str) -> tuple[list[str], str]:
    """The frontmatter's lines and everything after its closing `---`."""
    if not text.startswith("---\n"):
        return [], text
    end = text.find("\n---", 4)
    if end < 0:
        return [], text
    return text[4:end].split("\n"), text[end + 4:]


def without_curriculum_markers(body: str) -> str:
    """The installer's `strip_curriculum_blocks(keep_content=True)`: only the
    marker lines go."""
    kept: list[str] = []
    for line in body.split("\n"):
        if line.strip() in CURRICULUM_MARKERS:
            continue
        kept.append(line)
    return "\n".join(kept)


def without_embeds_of(body: str, codes: list[str]) -> str:
    """The body as it was before `link_activity` added these codes' embeds:
    each `![[CODE]]` line it wrote goes, with the blank line it wrote before
    it."""
    lines = body.split("\n")
    wanted = set(codes)
    result: list[str] = []
    for line in lines:
        match = EMBED.match(line.strip())
        if match and match.group(1).strip() in wanted:
            if result and result[-1] == "":
                result.pop()
            continue
        result.append(line)
    return "\n".join(result)


# Every committed version of a file, newest first (demo_folders keeps it,
# for the planted pages of both folders).
git_versions = demo_folders.git_versions


def has_code_runner(head: list[str]) -> bool:
    for line in head:
        if line.strip() == CODE_RUNNER_LINE:
            return True
    return False


def with_code_runner(head: list[str]) -> list[str]:
    """The kept frontmatter with `codeRunner: true` after its per-section
    keys — where a fresh install of a page whose payload says
    `publish: true` then `codeRunner: true` puts it — or at its end."""
    last_per_section = -1
    for index, line in enumerate(head):
        if PER_SECTION_KEY.match(line):
            last_per_section = index
    if last_per_section == -1:
        return head + [CODE_RUNNER_LINE]
    return head[:last_per_section + 1] + [CODE_RUNNER_LINE] + head[last_per_section + 1:]


def refresh_runnable_pages(course_dir: Path, payload_shared: Path, codes_by_page: dict[str, list[str]],
                           report: Report, earlier_versions=git_versions) -> None:
    """Bring each page the payload makes runnable (`codeRunner: true`) into
    the kept course, when the kept page is still what an earlier payload
    made. `codes_by_page` names the College Board codes this set-up embeds
    in each page (by its place without `.md`), so they can be set aside for
    the comparison; `link_activities` puts them back afterwards."""
    for source in sorted(payload_shared.rglob("*.md")):
        current = source.read_text(encoding="utf-8")
        payload_head, payload_body = split_frontmatter(current)
        if not has_code_runner(payload_head):
            continue
        place = source.relative_to(payload_shared).as_posix()
        label = f"{course_dir.name}/{place} runnable"
        kept_path = course_dir / place
        if not kept_path.is_file():
            report.skip(f"{label} — the page is not in the course")
            continue
        kept_head, kept_body = split_frontmatter(kept_path.read_text(encoding="utf-8"))
        codes = codes_by_page.get(place[:-3], [])
        kept_core = without_curriculum_markers(without_embeds_of(kept_body, codes))
        wanted_core = without_curriculum_markers(payload_body)
        if has_code_runner(kept_head):
            if kept_core == wanted_core:
                report.note("already there", label)
            else:
                report.note("left as you changed it", label)
            continue
        made_earlier = False
        for version in earlier_versions(source):
            _, earlier_body = split_frontmatter(version)
            if without_curriculum_markers(earlier_body) == kept_core:
                made_earlier = True
                break
        if not made_earlier:
            report.note("left as you changed it", label)
            continue
        head = with_code_runner(kept_head)
        kept_path.write_text("---\n" + "\n".join(head) + "\n---" + wanted_core, encoding="utf-8")
        report.note("made", label)


def apply_code_steps(folder: Path, report: Report, earlier_versions=git_versions) -> None:
    """What the code figures need in the kept folder (#562): ICS3U's runnable
    pages brought up to date (its College Board embeds put back after), and
    CODE_PAGES planted. Run by `apply_file_steps` and on its own by
    `capture.py --code`, which needs no College Board pages."""
    course_dir = folder / "courses" / RUNNABLE_COURSE
    if read_config(course_dir) is not None:
        rows: list[dict] = []
        for course in CSP_COURSES:
            if course["code"] == RUNNABLE_COURSE:
                rows = load_correlation(course["correlation"])
        codes_by_page: dict[str, list[str]] = {}
        for row in rows:
            codes_by_page[row["page"]] = list(row["codes"])
        refresh_runnable_pages(course_dir, SUPPORT / "example_content" / RUNNABLE_COURSE / "shared",
                               codes_by_page, report, earlier_versions)
        link_activities(course_dir, rows, report)
    else:
        report.skip(f"{RUNNABLE_COURSE} — the course has not been made yet (the app makes it first)")
    add_code_pages(folder, report, earlier_versions)


# The start-of-year scene is "the week before school starts" for section 2,
# so section 2 is a SECOND-SEMESTER section: its classes begin in the week of
# folders.json → marketing.secondSemester.startsInTheWeekOf (1 February), in
# the school year after the one the section's dates begin in. Measured
# 2026-09-27: the payload's classes run from 2026-09-08, so on the day of the
# capture 13 of them were "dated before today" and the sheet led with an
# orange warning about students losing classes already taught — a true
# sentence about the wrong story. Section 1 keeps the payload's dates: the
# maps, the preview and the scheduled publish are all section 1.
#
# Computed, never a fixed date (#445): this was `date(2027, 2, 1)`, and a
# folder made after August 2027 would have had a section 2 already past it,
# so nothing moved and the scene told the wrong story again.
SECOND_SEMESTER_SECTION = demo_folders.load_spec()["marketing"]["secondSemester"]["section"]
DATE_LINE = re.compile(r"^(?P<key>created|createdSection\d+): (?P<day>\d{4}-\d{2}-\d{2})(?P<rest>T.*)?$")


def section_dates(course_dir: Path, section: int) -> list[tuple[Path, str]]:
    """Every page carrying a date for `section`, with the key that carries it:
    `created:` on the section's own pages, `createdSection<N>:` on shared ones."""
    found: list[tuple[Path, str]] = []
    own = course_dir / f"section{section}"
    for page in sorted(course_dir.rglob("*.md")):
        if COLLEGE_BOARD_FOLDER in page.parts:
            continue
        key = "created" if own in page.parents else f"createdSection{section}"
        found.append((page, key))
    return found


def move_section_to_second_semester(course_dir: Path, report: Report,
                                    section: int = SECOND_SEMESTER_SECTION,
                                    starts: date | None = None) -> None:
    """Shift every date `section` carries by whole weeks, so its first class
    falls in the week of `starts` and every class keeps its weekday. Without
    `starts`, the day folders.json names in the school year the section's
    earliest date belongs to (`demo_folders.second_semester_starts`).

    Idempotent: nothing moves once the earliest date is on or after the start
    of that week. Only the date lines change; the rest of each page is left
    byte for byte.
    """
    pages = section_dates(course_dir, section)
    earliest: date | None = None
    for page, key in pages:
        for line in page.read_text(encoding="utf-8").split("\n"):
            match = DATE_LINE.match(line)
            if match and match.group("key") == key:
                day = date.fromisoformat(match.group("day"))
                earliest = day if earliest is None or day < earliest else earliest
    if earliest is None:
        report.skip(f"{course_dir.name} section {section} — no dated pages to move")
        return
    if starts is None:
        starts = demo_folders.second_semester_starts(earliest)
    week_start = starts - timedelta(days=starts.weekday())
    if earliest >= week_start:
        report.note("already there", f"{course_dir.name} section {section} starts {earliest.isoformat()}")
        return
    weeks = ((week_start - (earliest - timedelta(days=earliest.weekday()))).days) // 7
    shift = timedelta(weeks=weeks)
    moved = 0
    for page, key in pages:
        text = page.read_text(encoding="utf-8")
        lines = text.split("\n")
        changed = False
        for index, line in enumerate(lines):
            match = DATE_LINE.match(line)
            if not match or match.group("key") != key:
                continue
            day = date.fromisoformat(match.group("day")) + shift
            lines[index] = f"{key}: {day.isoformat()}{match.group('rest') or ''}"
            changed = True
        if changed:
            page.write_text("\n".join(lines), encoding="utf-8")
            moved += 1
    first = earliest + shift
    report.note("made", f"{course_dir.name} section {section} moved {weeks} weeks to a second semester "
                        f"starting {first.isoformat()} ({moved} pages)")


def apply_file_steps(folder: Path, college_board_pages: dict[str, str] | None) -> Report:
    """Everything that is files rather than the app, in order.

    Needs the courses to exist already (the app makes them); a course that is
    not there yet is named and skipped. For each course in `CSP_COURSES`: its
    College Board pages, the folder kept out of the sidebar, the second
    curriculum declared where this set-up owns that, its correlation's embeds
    and its folder destination. Then ICS3U's own steps: How I Teach and the
    second-semester section.

    The College Board pages are passed in, because making them needs the
    document (`college_board.build_pages`); None skips that step and says so.
    """
    refuse_foreign_courses(folder)
    report = Report()
    if college_board_pages is None:
        report.skip(f"{COLLEGE_BOARD_FOLDER} — no pages were supplied")
    for course in CSP_COURSES:
        code = course["code"]
        course_dir = folder / "courses" / code
        if read_config(course_dir) is None:
            report.skip(f"{code} — the course has not been made yet (the app makes it first)")
            continue
        if college_board_pages is not None:
            install_college_board_pages(course_dir, college_board_pages, report)
        keep_out_of_sidebar(course_dir, COLLEGE_BOARD_FOLDER, report)
        if course["declare"]:
            declare_curriculum_folder(course_dir, COLLEGE_BOARD_FOLDER, report)
        link_activities(course_dir, load_correlation(course["correlation"]), report)
        publish_to_folder(course_dir, folder / course["publish_to"], report)

    apply_code_steps(folder, report)

    course_dir = folder / "courses" / CURRICULUM_COURSE
    if read_config(course_dir) is None:
        return report
    add_how_i_teach(course_dir, report)
    move_section_to_second_semester(course_dir, report)
    return report


def summary(report: Report) -> str:
    text = (f"{report.made} made, {report.already_there} already there, "
            f"{report.left_as_changed} left as you changed them")
    if report.named_and_skipped:
        text += f", {len(report.named_and_skipped)} named and skipped:\n   - " + "\n   - ".join(report.named_and_skipped)
    return text


def stage_from_payload(folder: Path, support: Path) -> None:
    """For a DRY RUN only: lay each CSP course's payload (ICS3U and ICS4U)
    out the way a course folder looks after the app installs it, in a
    throwaway folder, so the file steps can be proven against real pages
    without the app. Never used on a kept folder.
    """
    mark_as_ours(folder)
    for course in CSP_COURSES:
        code = course["code"]
        payload = support / "example_content" / code
        course_dir = folder / "courses" / code
        shutil.copytree(payload / "shared", course_dir, dirs_exist_ok=True)
        manifest = json.loads((payload / "manifest.json").read_text(encoding="utf-8"))
        config = {"course_code": code, "hidden": list(manifest.get("hidden", [])),
                  "curriculum_folders": ["Curriculum"]}
        (course_dir / "course_config.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
