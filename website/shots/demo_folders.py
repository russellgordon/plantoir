#!/usr/bin/env python3
"""The two demo working folders plantoir.app's pictures are taken in, as rules.

``marketing/folders.json`` is the one place that says what the folders hold:
the course codes and sections, each demo section's colour scheme, the demo
sites' names, the marketing courses' destinations, and the demo STATE as rules
that follow the school year rather than as dates (GitHub #445). This module
reads it and applies the parts that are not made by the app's own panels:

- each demo section's colour scheme, written into ``course_config.json``
  where the new-course panel wrote its default;
- the teacher's last name (the one question a first deploy asks) and the
  stand-in Netlify markers naming the live sites;
- every demo section's front page showing the latest class dated on or before
  January 15 of the school year, with every class after it unpublished — made
  THROUGH THE APP's own door (``Plantoir --mcp-stdio`` on the Mac,
  ``plantoir-mcp.exe`` on Windows) with ``unpublish_pages``, so the app
  repoints the front page itself and no third copy of that rule lives here.

Every step says "made", "already there" or "left as you changed it", in
``marketing_folder``'s own words, and a second run changes nothing.

It also answers the questions the capture scripts and the UI tests ask of a
folder — which school year a reference copy is filed under, when a
second-semester section starts — and checks a folder against the rules
(``demo_state_problems``), which is what ``test_demo_folders.py`` and the
opt-in comparison against the kept folders use.

Standard library only, and the same on macOS and Windows.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC_FILE = HERE / "marketing" / "folders.json"

DATE_KEY = re.compile(r"^created: (?P<day>\d{4}-\d{2}-\d{2})", re.MULTILINE)
PUBLISH_KEY = re.compile(r"^publish: (?P<value>\S+)", re.MULTILINE)
EMBED = re.compile(r"!\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]")
DEFAULT_CLASS_FOLDER = "All Classes"


# ---------- The spec ----------

def load_spec(path: Path = SPEC_FILE) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def demo_courses(spec: dict | None = None) -> list[dict]:
    """The demo folder's courses: code, sections, colourScheme, site, siteTitle."""
    if spec is None:
        spec = load_spec()
    return list(spec["demo"]["courses"])


def marketing_courses(spec: dict | None = None) -> list[dict]:
    """The marketing folder's courses: code, sections, publishTo, and the
    College Board correlation each one answers to."""
    if spec is None:
        spec = load_spec()
    return list(spec["marketing"]["courses"])


def sections_as_typed(sections: list[int]) -> str:
    """The sections the way a teacher types them into the new-course panel."""
    words: list[str] = []
    for number in sections:
        words.append(str(number))
    return ", ".join(words)


def month_and_day(text: str) -> tuple[int, int]:
    month, day = text.split("-")
    return int(month), int(day)


# ---------- School years ----------

def school_year_of(day: date) -> int:
    """The year whose September a day belongs to — the installer's own rule
    (setup_course.semester_class_timestamp): August onward is the new year."""
    if day.month >= 8:
        return day.year
    return day.year - 1


def year_title(school_year: int) -> str:
    """How the app writes a school year: 2025 → "2025–26"."""
    return f"{school_year}–{(school_year + 1) % 100:02d}"


def day_in_school_year(school_year: int, month_day: str) -> date:
    """A month and day inside a school year: September to July."""
    month, day = month_and_day(month_day)
    if month >= 8:
        return date(school_year, month, day)
    return date(school_year + 1, month, day)


def second_semester_starts(earliest: date, spec: dict | None = None) -> date:
    """The day whose WEEK a second-semester section's first class falls in:
    folders.json → marketing.secondSemester.startsInTheWeekOf, in the school
    year that `earliest` (the section's earliest date) belongs to. Never a
    fixed year, so the step means the same thing next year."""
    if spec is None:
        spec = load_spec()
    return day_in_school_year(school_year_of(earliest), spec["marketing"]["secondSemester"]["startsInTheWeekOf"])


def reference_copies(folder: Path, code: str) -> list[Path]:
    """Every reference copy of `code` in a working folder, whatever its
    folder is called (Keep a Copy for Reference proposes its own name)."""
    found: list[Path] = []
    courses = folder / "courses"
    if not courses.is_dir():
        return found
    for entry in sorted(courses.iterdir()):
        config = read_config(entry)
        if config is None:
            continue
        if config.get("kept_for_reference") is True and config.get("course_code") == code:
            found.append(entry)
    return found


def reference_school_year(folder: Path, today: date, spec: dict | None = None) -> int:
    """The school year the scenes look for under Reference Courses.

    READ from the folder's own reference copy (`reference_school_year`) once
    there is one: a kept copy stays filed where it was filed, whatever the
    clock says next year. Only a folder without a copy yet — about to be
    given one — takes the year folders.json names, counted from today."""
    if spec is None:
        spec = load_spec()
    rule = spec["marketing"]["referenceCopy"]
    for copy in reference_copies(folder, rule["of"]):
        config = read_config(copy) or {}
        year = config.get("reference_school_year")
        if isinstance(year, int):
            return year
    current = school_year_of(today)
    if rule["schoolYear"] == "previous":
        return current - 1
    return current


# ---------- Reading a course ----------

def read_config(course_dir: Path) -> dict | None:
    path = course_dir / "course_config.json"
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


@dataclass
class ClassPage:
    day: date
    title: str
    path: Path
    published: bool


def class_pages(course_dir: Path, section: int) -> list[ClassPage]:
    """A section's dated class pages, oldest first."""
    config = read_config(course_dir) or {}
    folder_name = config.get("class_folder") or DEFAULT_CLASS_FOLDER
    folder = course_dir / f"section{section}" / folder_name
    found: list[ClassPage] = []
    if not folder.is_dir():
        return found
    for page in sorted(folder.glob("*.md")):
        if page.name == "index.md":
            continue
        text = page.read_text(encoding="utf-8")
        dated = DATE_KEY.search(text)
        if dated is None:
            continue
        published = PUBLISH_KEY.search(text)
        found.append(ClassPage(
            day=date.fromisoformat(dated.group("day")),
            title=page.stem,
            path=page,
            published=published is not None and published.group("value") == "true",
        ))
    found.sort(key=lambda page: (page.day, page.title))
    return found


@dataclass
class FrontPagePlan:
    """What one section's front page should show, by folders.json's rule."""
    course: str
    section: int
    shown: ClassPage | None
    after: list[ClassPage]


def front_page_plan(course_dir: Path, section: int, spec: dict | None = None) -> FrontPagePlan:
    """The latest class dated on or before the rule's month and day — never a
    class ON that day, which is a weekend in some years — and every class
    after it."""
    if spec is None:
        spec = load_spec()
    pages = class_pages(course_dir, section)
    plan = FrontPagePlan(course=course_dir.name, section=section, shown=None, after=[])
    if not pages:
        return plan
    limit = day_in_school_year(school_year_of(pages[0].day), spec["demo"]["frontPage"]["latestClassOnOrBefore"])
    for page in pages:
        if page.day <= limit:
            plan.shown = page
        else:
            plan.after.append(page)
    return plan


def door_requests(plan: FrontPagePlan) -> list[tuple[str, dict]]:
    """The tool calls that make a section match its plan, through the app.

    `publish_class_on` only when the class to show is not published yet;
    then `unpublish_pages` from the next class's date onward, after which the
    app repoints the front page at the newest class students can see."""
    requests: list[tuple[str, dict]] = []
    if plan.shown is None:
        return requests
    if not plan.shown.published:
        requests.append(("publish_class_on", {"course": plan.course, "section": plan.section,
                                              "date": plan.shown.day.isoformat()}))
    if plan.after:
        requests.append(("unpublish_pages", {"course": plan.course, "section": plan.section,
                                             "onOrAfter": plan.after[0].day.isoformat()}))
    return requests


def front_page_embed_and_date(course_dir: Path, section: int) -> tuple[str | None, date | None]:
    """The class a section's front page transcludes, and the page's date."""
    index = course_dir / f"section{section}" / "index.md"
    if not index.is_file():
        return None, None
    text = index.read_text(encoding="utf-8")
    dated = DATE_KEY.search(text)
    day = date.fromisoformat(dated.group("day")) if dated else None
    titles: set[str] = set()
    for page in class_pages(course_dir, section):
        titles.add(page.title)
    for match in EMBED.finditer(text):
        name = match.group(1).strip().split("/")[-1]
        if name.endswith(".md"):
            name = name[:-3]
        if name in titles:
            return name, day
    return None, day


def front_page_problems(course_dir: Path, section: int, spec: dict | None = None) -> list[str]:
    """Everything about one section that does not match the front-page rule."""
    plan = front_page_plan(course_dir, section, spec)
    label = f"{course_dir.name} section {section}"
    if plan.shown is None:
        return [f"{label} has no class dated on or before the front page's day"]
    problems: list[str] = []
    if not plan.shown.published:
        problems.append(f"{label}: {plan.shown.title} ({plan.shown.day}) should be published")
    for page in plan.after:
        if page.published:
            problems.append(f"{label}: {page.title} ({page.day}) comes after {plan.shown.title} and should be unpublished")
    shown, day = front_page_embed_and_date(course_dir, section)
    if shown != plan.shown.title:
        problems.append(f"{label}: the front page shows {shown}, not {plan.shown.title}")
    if day != plan.shown.day:
        problems.append(f"{label}: the front page is dated {day}, not {plan.shown.day}")
    return problems


def colour_problems(folder: Path, spec: dict | None = None) -> list[str]:
    problems: list[str] = []
    for course in demo_courses(spec):
        config = read_config(folder / "courses" / course["code"]) or {}
        schemes = config.get("color_schemes") or {}
        for section in course["sections"]:
            found = schemes.get(f"section{section}")
            if found != course["colourScheme"]:
                problems.append(f"{course['code']} section {section} is coloured {found}, not {course['colourScheme']}")
    return problems


def demo_state_problems(folder: Path, spec: dict | None = None) -> list[str]:
    """Read-only: everything in a demo folder that does not match folders.json."""
    if spec is None:
        spec = load_spec()
    problems: list[str] = []
    for course in demo_courses(spec):
        course_dir = folder / "courses" / course["code"]
        if read_config(course_dir) is None:
            problems.append(f"{course['code']} is not in {folder}")
            continue
        for section in course["sections"]:
            problems.extend(front_page_problems(course_dir, section, spec))
    problems.extend(colour_problems(folder, spec))
    return problems


# ---------- Applying the state ----------

def note(report, outcome: str, what: str) -> None:
    """marketing_folder.Report when one is given; printing otherwise."""
    if report is not None:
        report.note(outcome, what)
    else:
        print(f"   {outcome}: {what}")


def apply_colours(folder: Path, report=None, spec: dict | None = None) -> None:
    """Each demo section's colour scheme, where the panel wrote its default.
    A scheme somebody chose that is neither the panel's default nor
    folders.json's is left as it is."""
    for course in demo_courses(spec):
        path = folder / "courses" / course["code"] / "course_config.json"
        config = read_config(path.parent)
        if config is None:
            continue
        schemes = config.get("color_schemes")
        if not isinstance(schemes, dict):
            schemes = {}
        changed = False
        for section in course["sections"]:
            key = f"section{section}"
            found = schemes.get(key)
            label = f"{course['code']} section {section} coloured {course['colourScheme']}"
            if found == course["colourScheme"]:
                note(report, "already there", label)
            elif found in (None, "", "quartz-standard"):
                schemes[key] = course["colourScheme"]
                changed = True
                note(report, "made", label)
            else:
                note(report, "left as you changed it", label)
        if changed:
            config["color_schemes"] = schemes
            path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def write_site_markers(folder: Path, report=None, spec: dict | None = None) -> None:
    """Stand-in markers naming the live sites, for a folder that has none.
    The kept folder's real ones (Netlify's own ids) are never touched."""
    for course in demo_courses(spec):
        marker = folder / "courses" / course["code"] / ".netlify_sites" / "section1.json"
        label = f"{course['code']} names its site {course['site']}"
        if marker.exists():
            note(report, "already there", label)
            continue
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text(json.dumps({
            "id": f"demo-{course['code'].lower()}-s1",
            "name": course["site"],
            "url": f"https://{course['site']}.netlify.app",
        }, indent=2), encoding="utf-8")
        note(report, "made", label)


def remember_teacher_name(folder: Path, report=None, spec: dict | None = None) -> None:
    """The one question a first deploy asks about the teacher, answered."""
    if spec is None:
        spec = load_spec()
    profile = folder / "courses" / ".internal" / "profile.json"
    if profile.exists():
        note(report, "already there", "the teacher's last name")
        return
    profile.parent.mkdir(parents=True, exist_ok=True)
    profile.write_text(json.dumps({"teacher_last_name": spec["teacherLastName"]}, indent=2), encoding="utf-8")
    try:
        profile.chmod(0o600)
    except OSError:
        pass
    note(report, "made", "the teacher's last name")


class DoorRefused(Exception):
    """The app answered a tool call with an error."""


def ask_the_app(server: list[str], requests: list[tuple[str, dict]], timeout_seconds: int = 300) -> list[str]:
    """Send tool calls to the app's own MCP server, one process for all of
    them, and return each answer's text. Newline-delimited JSON-RPC over
    stdio, the way an outside assistant talks to it."""
    process = subprocess.Popen(server, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True, encoding="utf-8")
    assert process.stdin is not None and process.stdout is not None

    def send(message: dict) -> None:
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()

    def answer(identifier: int) -> dict:
        deadline = time.time() + timeout_seconds
        while time.time() < deadline:
            line = process.stdout.readline()
            if not line:
                break
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if message.get("id") == identifier:
                return message
        raise DoorRefused(f"the app's MCP server did not answer request {identifier}")

    answers: list[str] = []
    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                         "clientInfo": {"name": "plantoir-demo-folders", "version": "1"}}})
        answer(1)
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        identifier = 2
        for tool, arguments in requests:
            send({"jsonrpc": "2.0", "id": identifier, "method": "tools/call",
                  "params": {"name": tool, "arguments": arguments}})
            reply = answer(identifier)
            result = reply.get("result") or {}
            text_parts: list[str] = []
            for part in result.get("content") or []:
                text_parts.append(str(part.get("text", "")))
            text = "\n".join(text_parts)
            if "error" in reply or result.get("isError"):
                raise DoorRefused(f"{tool} {json.dumps(arguments)} was refused: {reply.get('error') or text}")
            answers.append(text)
            identifier += 1
    finally:
        # Close stdin and wait: a stray server holds files open.
        process.stdin.close()
        try:
            process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdout.close()
    return answers


def mac_server(app_binary: Path, folder: Path, state_dir: Path | None = None) -> list[str]:
    """The Mac's door: the app itself, serving MCP over stdio. A state
    folder keeps its trail and preferences out of the real ones."""
    command: list[str] = [str(app_binary)]
    if state_dir is not None:
        command += ["--state-dir", str(state_dir)]
    command += ["--mcp-stdio", str(folder)]
    return command


def windows_server(mcp_exe: Path, folder: Path) -> list[str]:
    """Windows' door: plantoir-mcp.exe beside Plantoir.exe."""
    return [str(mcp_exe), "--mcp-stdio", str(folder)]


def apply_front_pages(folder: Path, server: list[str] | None, report=None, spec: dict | None = None) -> list[str]:
    """Every demo section's front page, through the app. Returns what could
    not be done; a section already right is "already there" and costs no
    call at all."""
    if spec is None:
        spec = load_spec()
    left: list[str] = []
    for course in demo_courses(spec):
        course_dir = folder / "courses" / course["code"]
        if read_config(course_dir) is None:
            left.append(f"{course['code']} — the course has not been made yet (the app makes it first)")
            continue
        for section in course["sections"]:
            label = f"{course['code']} section {section}'s front page"
            if not front_page_problems(course_dir, section, spec):
                note(report, "already there", label)
                continue
            plan = front_page_plan(course_dir, section, spec)
            requests = door_requests(plan)
            if server is None:
                left.append(f"{label} — needs the app ({len(requests)} request(s))")
                continue
            ask_the_app(server, requests)
            still = front_page_problems(course_dir, section, spec)
            if still:
                left.extend(still)
            else:
                note(report, "made", f"{label} shows {plan.shown.title if plan.shown else '?'}")
    return left


def apply_demo_state(folder: Path, server: list[str] | None, report=None, spec: dict | None = None) -> list[str]:
    """Everything folders.json asks of a demo folder after the app has made
    its courses. Returns what is still left (empty when the folder matches)."""
    if spec is None:
        spec = load_spec()
    apply_colours(folder, report, spec)
    remember_teacher_name(folder, report, spec)
    write_site_markers(folder, report, spec)
    return apply_front_pages(folder, server, report, spec)


# ---------- Finding the kept folders, for the opt-in comparison ----------

def kept_folder_candidates(home: Path | None = None) -> list[Path]:
    """Where the kept folders can be, including where the scenes put them:
    the marketing folder is shown as ~/Desktop/Teaching while the scenes run,
    and the demo folder is set aside beside it (capture.py)."""
    if home is None:
        home = Path.home()
    found: list[Path] = []
    for path in [home / "Plantoir Marketing", home / "Desktop" / "Teaching"]:
        found.append(path)
    desktop = home / "Desktop"
    if desktop.is_dir():
        for entry in sorted(desktop.iterdir()):
            if entry.name.startswith(".Teaching"):
                found.append(entry)
    return found


def identify(folder: Path, spec: dict | None = None) -> str | None:
    """"marketing", "demo" or None — by what the folder HOLDS, never by its
    path, since the scenes move the folders while they run."""
    if spec is None:
        spec = load_spec()
    courses = folder / "courses"
    if not courses.is_dir():
        return None
    held: set[str] = set()
    for entry in courses.iterdir():
        config = read_config(entry)
        if config is not None and config.get("kept_for_reference") is not True:
            held.add(str(config.get("course_code", entry.name)))
    if (folder / ".plantoir-marketing-folder").exists():
        wanted: set[str] = set()
        for course in marketing_courses(spec):
            wanted.add(course["code"])
        return "marketing" if wanted <= held else None
    wanted_demo: set[str] = set()
    for course in demo_courses(spec):
        wanted_demo.add(course["code"])
    return "demo" if held == wanted_demo else None


def find_kept_folders(home: Path | None = None) -> dict[str, Path]:
    found: dict[str, Path] = {}
    for candidate in kept_folder_candidates(home):
        kind = identify(candidate)
        if kind is not None and kind not in found:
            found[kind] = candidate
    return found


def copy_sources(source: Path, destination: Path) -> None:
    """A folder's SOURCE pages and configs, without what was built, the
    recipe mirror, the launchers or the backups — for a read-only comparison."""
    import shutil
    skip = {".merged_output", ".toolchain", "_backups", "School Web Space", ".sources", ".obsidian",
            ".publish_state", ".internal", "node_modules", ".git"}

    def ignored(directory: str, names: list[str]) -> list[str]:
        out: list[str] = []
        for name in names:
            if name in skip or name.endswith(".zip"):
                out.append(name)
        return out

    shutil.copytree(source, destination, ignore=ignored, symlinks=True)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Apply folders.json's demo state to a working folder.")
    parser.add_argument("folder")
    parser.add_argument("--app", help="the Plantoir binary (Mac) or plantoir-mcp.exe (Windows) whose door to use")
    parser.add_argument("--state-dir", help="Mac only: a folder for the app's own state")
    arguments = parser.parse_args()
    target = Path(arguments.folder).expanduser()
    door: list[str] | None = None
    if arguments.app:
        if os.name == "nt":
            door = windows_server(Path(arguments.app), target)
        else:
            door = mac_server(Path(arguments.app), target,
                              Path(arguments.state_dir) if arguments.state_dir else None)
    remaining = apply_demo_state(target, door)
    for line in remaining:
        print(f"   still to do: {line}")
    raise SystemExit(1 if remaining else 0)
