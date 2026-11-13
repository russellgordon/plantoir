#!/usr/bin/env python3
"""
Two builds of one course writing the course's shared files at the same
moment (GitHub #835, fixes F2 and F3).

One copy of Plantoir already builds two sections of a course at once, and
#835 lets two programs do it too, so the two files every build of a course
may write must survive two writers:

  * F2, `course_config.json`. The build's preflight writes it back when it
    finds a new shared folder or file. Until #835 every write went through one
    fixed temporary name, `course_config.json.tmp`, so one writer renamed the
    other's half-written file into place: in a stand-in of two writers 224
    and 301 reads met a file that was not JSON, and one trial ENDED that way
    (2026-11-13). Each write now has a temporary of its own.

  * F3, the date pass. Two sections dating one shared page each write their
    own `createdSection<N>`. The last look at the page and the rename were
    two steps, so both could see the page unchanged and the second rename
    threw the first's date away while both said "written": 100 of 300 trials
    in a stand-in. They are now one step under a lock for the course, kept in
    the course's built-website folder, so the second sees the first's write
    and declines (its next build dates the page again).

The real functions from build_site.py, two processes at a time. Pure stdlib,
no Docker, no network. The lock needs fcntl, so F3's trials skip where there
is none (Windows, which builds natively and owes its own, #835's windows
issue). Listed in verify.sh's step 0. Run with:

    python3 scripts/test_shared_writes_two_at_once.py
"""

import json
import multiprocessing
import os
import shutil
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_site  # noqa: E402

try:
    import fcntl  # noqa: F401
    HAS_FCNTL = True
except ImportError:
    HAS_FCNTL = False

CONFIG_TRIALS = 5
CONFIG_WRITES = 200
DATING_TRIALS = 300
PAGE = "---\ntitle: Shared\n---\nbody\n"


def a_course(root: Path) -> Path:
    course = root / "EXC2O"
    course.mkdir()
    (course / "course_config.json").write_text(json.dumps({"course_code": "EXC2O"}), encoding="utf-8")
    os.chmod(course / "course_config.json", 0o644)
    (course / ".merged_output").mkdir()
    return course


# --- F2 ----------------------------------------------------------------------

def write_the_config(path: str, tag: str, writes: int, start):
    import contextlib
    import io
    start.wait()
    for number in range(writes):
        data = {"course_code": "EXC2O", "writer": tag, "write": number, "pad": ["x" * 40] * 400}
        with contextlib.redirect_stdout(io.StringIO()):
            build_site._atomic_write_json_with_backup(Path(path), data)


class TheConfigSurvivesTwoWriters(unittest.TestCase):

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-two-writers-"))
        self.course = a_course(self.root)
        self.config = self.course / "course_config.json"

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_every_read_is_json_and_nothing_is_left_behind(self):
        context = multiprocessing.get_context("spawn")
        reads: int = 0
        not_json: int = 0
        backups_not_json: int = 0
        for trial in range(CONFIG_TRIALS):
            start = context.Event()
            writers = [context.Process(target=write_the_config, args=(str(self.config), tag, CONFIG_WRITES, start))
                       for tag in ("s1", "s2")]
            for writer in writers:
                writer.start()
            start.set()
            while any(writer.is_alive() for writer in writers):
                for path in (self.config, self.course / "course_config.backup.json"):
                    try:
                        text = path.read_text(encoding="utf-8")
                    except FileNotFoundError:
                        continue
                    reads += 1
                    try:
                        json.loads(text)
                    except ValueError:
                        if path == self.config:
                            not_json += 1
                        else:
                            backups_not_json += 1
            for writer in writers:
                writer.join()
                self.assertEqual(writer.exitcode, 0)
            json.loads(self.config.read_text(encoding="utf-8"))
        self.assertGreater(reads, 0)
        self.assertEqual((not_json, backups_not_json), (0, 0),
                         f"of {reads} reads {not_json} met a config and {backups_not_json} a backup that was not JSON")
        left: list = []
        for entry in self.course.iterdir():
            if entry.name.endswith(".tmp"):
                left.append(entry.name)
        self.assertEqual(left, [], "no temporary file is left beside the config")
        if os.name == "nt":
            # Windows has no 0644: a writable file reads 0o666 there (#835
            # review M2). What the code promises there is a whole file a
            # reader can open, which the reads above have checked.
            self.assertTrue(os.access(self.config, os.R_OK | os.W_OK))
        else:
            self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o644, "the config keeps its permissions")

    def test_a_temporary_left_by_a_killed_writer_is_removed_by_the_next(self):
        import time
        stale = self.course / ".course_config.abc123.tmp"
        stale_backup = self.course / ".course_config.backup.def456.tmp"
        fresh = self.course / ".course_config.ghi789.tmp"
        someone_elses = self.course / ".notes.old.tmp"
        teachers = self.course / "course_config notes.tmp"
        for path in (stale, stale_backup, fresh, someone_elses, teachers):
            path.write_text("left", encoding="utf-8")
        an_hour_ago = time.time() - 3600
        for path in (stale, stale_backup, someone_elses, teachers):
            os.utime(path, (an_hour_ago, an_hour_ago))
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()):
            build_site._atomic_write_json_with_backup(self.config, {"course_code": "EXC2O"})
        self.assertFalse(stale.exists())
        self.assertFalse(stale_backup.exists())
        self.assertTrue(fresh.exists(), "a write in progress elsewhere is never touched")
        self.assertTrue(someone_elses.exists(), "a name this writer does not make is never touched")
        self.assertTrue(teachers.exists())

    def test_the_temporary_is_hidden_and_named_for_nobody_else(self):
        made = build_site._a_private_temporary_beside(self.config, ".course_config.")
        again = build_site._a_private_temporary_beside(self.config, ".course_config.")
        try:
            self.assertNotEqual(made, again)
            for name in (made.name, again.name):
                self.assertTrue(name.startswith(".") and name.endswith(".tmp"), name)
                self.assertNotEqual(name, "course_config.json.tmp")
        finally:
            made.unlink()
            again.unlink()


# --- F3 ----------------------------------------------------------------------

def date_the_page(page: str, key: str, trials: int, barrier, answers):
    for trial in range(trials):
        barrier.wait()      # the page has been reset
        path = Path(page)
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)
        rewritten = "".join(lines[:1] + [f"{key}: 2026-11-13\n"] + lines[1:])
        answers.put((trial, key, build_site._replace_the_page_safely(path, text, rewritten)))
        barrier.wait()      # both have answered


@unittest.skipUnless(HAS_FCNTL, "the course's dating lock needs fcntl (Windows owes its own)")
class TwoSectionsDatingOnePageLoseNothing(unittest.TestCase):

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-two-daters-"))
        self.course = a_course(self.root)
        (self.course / "Unit 1").mkdir()
        self.page = self.course / "Unit 1" / "Shared Page.md"
        self.page.write_text(PAGE, encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_a_date_said_to_be_written_is_on_the_page(self):
        context = multiprocessing.get_context("spawn")
        barrier = context.Barrier(3)
        answers = context.Queue()
        daters = [context.Process(target=date_the_page,
                                  args=(str(self.page), key, DATING_TRIALS, barrier, answers))
                  for key in ("createdSection1", "createdSection2")]
        for dater in daters:
            dater.start()
        lost: int = 0
        both_written: int = 0
        for trial in range(DATING_TRIALS):
            self.page.write_text(PAGE, encoding="utf-8")
            barrier.wait()
            barrier.wait()
            said: dict = {}
            for _ in range(2):
                number, key, written = answers.get(timeout=30)
                self.assertEqual(number, trial)
                said[key] = written
            on_the_page = self.page.read_text(encoding="utf-8")
            if said["createdSection1"] and said["createdSection2"]:
                both_written += 1
            for key, written in said.items():
                if written and f"{key}:" not in on_the_page:
                    lost += 1
        for dater in daters:
            dater.join(timeout=30)
        self.assertEqual(lost, 0, f"in {DATING_TRIALS} trials {lost} dates were said to be written and were not "
                                  f"there ({both_written} trials said both were written)")
        self.assertFalse(any(entry.name.endswith(".plantoir-dating") for entry in self.page.parent.iterdir()))

    def test_the_lock_is_kept_with_the_built_website_never_among_the_teachers_files(self):
        self.assertEqual(build_site._the_course_dating_lock(self.page), self.course / ".merged_output" / ".dating.lock")
        build_site._replace_the_page_safely(self.page, PAGE, PAGE + "more\n")
        names: list = []
        for entry in self.course.rglob("*"):
            names.append(str(entry.relative_to(self.course)))
        self.assertIn(".merged_output/.dating.lock", names)
        self.assertNotIn(".dating.lock", names)

    def test_without_a_built_website_the_lock_is_in_the_temporary_folder(self):
        shutil.rmtree(self.course / ".merged_output")
        where = build_site._the_course_dating_lock(self.page)
        self.assertEqual(where.parent, Path(tempfile.gettempdir()))
        self.assertTrue(where.name.startswith("plantoir-dating-"))
        self.assertEqual(where, build_site._the_course_dating_lock(self.course / "Shared.md"),
                         "one lock for the whole course")

    def test_a_page_outside_any_course_is_dated_unlocked_as_before(self):
        loose = self.root / "loose.md"
        loose.write_text(PAGE, encoding="utf-8")
        self.assertIsNone(build_site._the_course_dating_lock(loose))
        self.assertTrue(build_site._replace_the_page_safely(loose, PAGE, PAGE + "more\n"))


if __name__ == "__main__":
    unittest.main()
