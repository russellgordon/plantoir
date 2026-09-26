#!/usr/bin/env python3
"""The marketing working folder, ``~/Plantoir Marketing``: set up once, kept, reused.

Every v1.4.0 scene on plantoir.app is taken in ONE working folder that is
Russell's to keep: ICS3U (sections 1 and 2) and ICS4U (section 1), made from
their ready-made content by the app's own new-course panel, then REVISED here —
never the shipped payload — so the ICS3U course also answers to AP Computer
Science Principles:

1. a **College Board Curriculum** folder, one page per learning objective in the
   College Board's own words (``college_board.py``; the words never enter this
   repository), kept out of the sidebar like ``Curriculum``;
2. each activity the correlation names (``csp-correlation.json``) gains an
   embed per objective inside its existing ``## Curriculum connection`` block,
   after the Ontario embeds, so the second map counts it exactly as the first
   does (coverage counts TRANSCLUSIONS, never plain links);
3. a **How I Teach** page, in our own words (``marketing/How I Teach.md``);
4. ICS3U publishes to a FOLDER inside the kept folder, so the scheduled-publish
   scene needs no account, no network, and makes nothing public.

The courses themselves, the reference copy of ICS3U and the declaration of the
second curriculum are made THROUGH THE APP (``capture.py`` runs the UI tests
that do it), because those are the features being photographed.

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
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_FOLDER = Path.home() / "Plantoir Marketing"
CORRELATION_FILE = HERE / "csp-correlation.json"
HOW_I_TEACH_SOURCE = HERE / "marketing" / "How I Teach.md"
HOW_I_TEACH_NAME = "How I Teach.md"

# The courses the folder holds, with the sections the app is asked to make.
# ICS4U is there so Copy a Page has somewhere to copy TO (ruling Q4).
COURSES: list[dict] = [
    {"code": "ICS3U", "sections": "1, 2"},
    {"code": "ICS4U", "sections": "1"},
]
CURRICULUM_COURSE = "ICS3U"
COLLEGE_BOARD_FOLDER = "College Board Curriculum"
# Where the scheduled-publish scene publishes: a folder inside the kept folder.
# `deploy_target` spells a folder destination "local_folder"
# (contracts/file-formats.json -> courseConfigKeys).
PUBLISH_FOLDER_NAME = "School Web Space"
FOLDER_DESTINATION = "local_folder"

CURRICULUM_HEADING = re.compile(r"^##\s+Curriculum connection\s*$")
ANY_HEADING = re.compile(r"^#{1,6}\s")
EMBED = re.compile(r"^!\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]\s*$")


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
        write_if_absent(folder / f"{code}.md", pages[code], report, f"{COLLEGE_BOARD_FOLDER}/{code}.md")


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


def publish_to_folder(course_dir: Path, destination: Path, report: Report) -> None:
    """Make the course publish to a folder — but only a course that has not
    been pointed anywhere else: a destination somebody chose is left alone."""
    def change(config: dict) -> bool:
        target = str(config.get("deploy_target", ""))
        path = str(config.get("deploy_folder_path", ""))
        if target == FOLDER_DESTINATION and path == str(destination):
            return False
        if target not in ("", "netlify") or (path and path != str(destination)):
            report.skip(f"{course_dir.name} publishes to {target or 'Netlify'} {path}; left as it is")
            return False
        config["deploy_target"] = FOLDER_DESTINATION
        config["deploy_folder_path"] = str(destination)
        return True
    destination.mkdir(parents=True, exist_ok=True)
    update_config(course_dir, change, report, f"{course_dir.name} publishes to {destination}")


def link_activity(page_path: Path, codes: list[str], report: Report) -> None:
    """Add an embed for each code inside the page's curriculum block.

    After the LAST embed already in the block, one per line with the blank
    line between them the block already uses. A code already embedded there
    is left alone; a page with no block is named and skipped.
    """
    label = page_path.name
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
        link_activity(course_dir / f"{row['page']}.md", row["codes"], report)


def add_how_i_teach(course_dir: Path, report: Report, source: Path = HOW_I_TEACH_SOURCE) -> None:
    write_if_absent(course_dir / HOW_I_TEACH_NAME, source.read_text(encoding="utf-8"), report,
                    f"{course_dir.name}/{HOW_I_TEACH_NAME}")


def apply_file_steps(folder: Path, college_board_pages: dict[str, str] | None,
                     rows: list[dict] | None = None) -> Report:
    """Everything that is files rather than the app, in order.

    Needs the ICS3U course to exist already (the app makes it). The College
    Board pages are passed in, because making them needs the document
    (`college_board.build_pages`); None skips that step and says so.
    """
    refuse_foreign_courses(folder)
    report = Report()
    course_dir = folder / "courses" / CURRICULUM_COURSE
    if read_config(course_dir) is None:
        report.skip(f"{CURRICULUM_COURSE} — the course has not been made yet (the app makes it first)")
        return report
    if college_board_pages is None:
        report.skip(f"{COLLEGE_BOARD_FOLDER} — no pages were supplied")
    else:
        install_college_board_pages(course_dir, college_board_pages, report)
    keep_out_of_sidebar(course_dir, COLLEGE_BOARD_FOLDER, report)
    link_activities(course_dir, rows if rows is not None else load_correlation(), report)
    add_how_i_teach(course_dir, report)
    publish_to_folder(course_dir, folder / PUBLISH_FOLDER_NAME, report)
    return report


def summary(report: Report) -> str:
    text = (f"{report.made} made, {report.already_there} already there, "
            f"{report.left_as_changed} left as you changed them")
    if report.named_and_skipped:
        text += f", {len(report.named_and_skipped)} named and skipped:\n   - " + "\n   - ".join(report.named_and_skipped)
    return text


def stage_from_payload(folder: Path, support: Path) -> None:
    """For a DRY RUN only: lay the ICS3U payload out the way a course folder
    looks after the app installs it, in a throwaway folder, so the file steps
    can be proven against real pages without the app. Never used on a kept
    folder.
    """
    payload = support / "example_content" / CURRICULUM_COURSE
    course_dir = folder / "courses" / CURRICULUM_COURSE
    shutil.copytree(payload / "shared", course_dir, dirs_exist_ok=True)
    manifest = json.loads((payload / "manifest.json").read_text(encoding="utf-8"))
    config = {"course_code": CURRICULUM_COURSE, "hidden": list(manifest.get("hidden", []))}
    (course_dir / "course_config.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
