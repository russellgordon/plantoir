"""
Builds the scratch courses of contracts/app-rules.json ->
buildFreshness.reuseTheLastBuild.cases, for the tests that run them.

Shared by scripts/test_build_freshness_reuse.py; the mac's
BuildFreshnessTests and ScheduledPublishOutcomeTests build the same courses
in Swift from the same `casesShape`. Every step is made on the REAL clock
with a short pause between steps, because a folder's time and a file's
change time cannot be set: only the order in which things happen gives them.

Pure stdlib. Not a test itself (no test_ prefix), so no suite runs it alone.
"""

import json
import os
import shutil
import time
from pathlib import Path

# Long enough that each step has its own time. APFS keeps times to the
# nanosecond and the mac's clock moves that finely, so 20 ms is ample there.
# NTFS keeps times to 100 ns, but Windows stamps a file from a system time
# that moves in ticks of up to 15.6 ms, so two steps 20 ms apart can sit one
# tick apart with little to spare; 50 ms there is three ticks (the #768
# review's L4).
PAUSE_SECONDS = 0.05 if os.name == "nt" else 0.02

COURSE_CODE = "C"


def the_contract(repository_root: Path) -> dict:
    with open(repository_root / "contracts" / "app-rules.json", encoding="utf-8") as handle:
        return json.load(handle)["buildFreshness"]["reuseTheLastBuild"]


def _pause() -> None:
    time.sleep(PAUSE_SECONDS)


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def _apply(course: Path, change: dict) -> None:
    what = change["do"]
    path = course / change["path"]
    if what == "edit":
        # In place, as an editor that saves over the file does here.
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("\nedited\n")
    elif what == "delete":
        if path.is_dir():
            shutil.rmtree(path)
        else:
            os.remove(path)
    elif what == "rename":
        target = course / change["to"]
        target.parent.mkdir(parents=True, exist_ok=True)
        os.rename(path, target)
    elif what == "replaceKeepingItsOldTime":
        old = os.stat(path)
        beside = path.with_name(path.name + ".incoming")
        _write(beside, "a new copy\n")
        os.utime(beside, ns=(old.st_atime_ns, old.st_mtime_ns))
        os.replace(beside, path)
    elif what == "overwriteKeepingItsOldTime":
        old = os.stat(path)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("written over where it stands\n")
        os.utime(path, ns=(old.st_atime_ns, old.st_mtime_ns))
    elif what == "createKeepingAnOldTime":
        _write(path, "restored from a backup\n")
        a_year_ago = time.time_ns() - 365 * 24 * 3600 * 1_000_000_000
        os.utime(path, ns=(a_year_ago, a_year_ago))
    else:
        raise ValueError(f"no such change in the contract: {what}")


def _changes(case: dict, when: str):
    found = []
    for change in case.get("changes", []):
        if change["when"] == when:
            found.append(change)
    return found


def build(root: Path, case: dict, the_course: list, stamp_for_this: str, another_stamp: str,
          preview_page: str = ""):
    """Makes the case under root. Returns (course folder, section folder).
    `preview_page` is the front page a case with `previewClient` gets: the
    contract's previewBuild.signature.asQuartzWritesIt (`preview_page_of`)."""
    working_folder = root / "work"
    if case.get("workingFolderUnderAHiddenFolder"):
        working_folder = root / ".kept-out-of-sight" / "work"
    course = working_folder / "courses" / COURSE_CODE
    if case.get("courseFolderIsALink"):
        # The course kept somewhere else, and linked into courses/.
        kept = root / "kept-elsewhere" / COURSE_CODE
        kept.mkdir(parents=True)
        course.parent.mkdir(parents=True)
        os.symlink(kept, course, target_is_directory=True)
    else:
        course.mkdir(parents=True)
    # The built sites live outside the course, behind a hidden link, as the
    # launchers keep them (contracts/shared-rules.json -> buildOutputLocation).
    builds = root / "builds" / COURSE_CODE
    builds.mkdir(parents=True)
    try:
        os.symlink(builds, course / ".merged_output", target_is_directory=True)
    except (OSError, NotImplementedError):
        # Windows without the right to make links: the built sites sit in the
        # hidden folder itself, which every reader skips just the same.
        shutil.rmtree(builds)
        builds = course / ".merged_output"
        builds.mkdir()
    section = builds / "section1"

    files = case.get("course", the_course)
    for relative in files:
        _write(course / relative, f"{relative}\n")
    _pause()
    for change in _changes(case, "beforeTheBuildStarted"):
        _apply(course, change)
    _pause()

    if case.get("site", "built") == "notBuilt":
        return course, section

    public = section / "public"
    public.mkdir(parents=True)
    front_page = public / "index.html"
    marker = section / ".build-started"
    order = case.get("startedMarker", "beforeTheSite")
    page = "<html><body>Welcome</body></html>\n"
    if case.get("previewClient"):
        if not preview_page:
            raise ValueError("a previewClient case needs the preview's page")
        page = preview_page

    if order == "beforeTheSite":
        at_the_start = _changes(case, "atTheBuildStart")
        for change in at_the_start:
            _apply(course, change)
        _write(marker, "This build started when this file was made.\n")
        for change in at_the_start:
            edited = os.stat(course / change["path"]).st_mtime_ns
            os.utime(marker, ns=(edited, edited))
        _pause()
        for change in _changes(case, "whileItBuilt"):
            _apply(course, change)
        _pause()
        _write(front_page, page)
    elif order == "afterTheSite":
        _write(front_page, page)
        _pause()
        for change in _changes(case, "whileItBuilt"):
            _apply(course, change)
        _pause()
        _write(marker, "This build started when this file was made.\n")
    else:
        for change in _changes(case, "whileItBuilt"):
            _apply(course, change)
        _pause()
        _write(front_page, page)

    stamp = case.get("stamp", "this")
    if stamp == "this":
        _write(section / ".built-with-toolchain", stamp_for_this + "\n")
    elif stamp == "another":
        _write(section / ".built-with-toolchain", another_stamp + "\n")

    if case.get("datedLaterThanNow"):
        an_hour = 3600 * 1_000_000_000
        for dated in (marker, front_page):
            if dated.exists():
                was = os.stat(dated).st_mtime_ns
                os.utime(dated, ns=(was + an_hour, was + an_hour))
    _pause()
    for change in _changes(case, "afterTheBuild"):
        _apply(course, change)
    return course, section


def preview_page_of(repository_root: Path) -> str:
    """A front page as a preview writes it: the contract's own sample."""
    with open(repository_root / "contracts" / "app-rules.json", encoding="utf-8") as handle:
        signature = json.load(handle)["buildFreshness"]["previewBuild"]["signature"]
    return "<html><body>" + signature["asQuartzWritesIt"] + "</body></html>\n"


def expected(case: dict, reads_the_stamp: bool):
    """(expect, because) for a reader, `inTheApps` applied when it does not
    read the stamp."""
    if not reads_the_stamp and "inTheApps" in case:
        override = case["inTheApps"]
        return override["expect"], override.get("because")
    return case["expect"], case.get("because")
