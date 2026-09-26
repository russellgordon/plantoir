#!/usr/bin/env python3
"""
A NEW course's file carries its marks pool, whichever tool made it (GitHub
issue #292).

The cases are deserialised from `contracts/shared-rules.json` ->
gradedFolders.newCourse, never retyped. This is the command line's half:

- `cases` drive the REAL wizard (`setup_course.setup_course`) with NO saved
  course_config.json — a new course made on the command line — typing the
  case's course code, saying no to the ready-made pages when the case
  declines them, and pressing Return everywhere else. The mac and Windows
  apps play the same cases through their own wizards, so the three tools are
  held to one answer. A case that carries `appliesOn` names the apps it is
  for (the club: there is no club toggle at a new course here), so it is
  skipped, and says so.
- `manifestCases` go through `graded_folders_for` the way setup calls it for
  a payload: the shared folders without Media, then the per-section folders.

Everything happens in-process, as in test_graded_folders_rerun.py: `input`
and `setup_course.getch` are replaced, so no terminal, pty or Docker is
needed. verify.sh runs this on the mac host in its first step, and Windows'
PythonToolchainTests discovers and runs it (every scripts/test_*.py).

The wizard writes only inside the temporary folder: COURSES_DIR is pointed at
it, and QUARTZ_DIR at a folder that does not exist, because two steps of the
wizard patch Quartz's own files whenever that folder is there.

The course code is answered by the prompt's TEXT, never by position: the
first measurement for #292 answered the first prompt and silently built the
default course instead. So every run also asserts that the case's own course
folder was made and that pages were installed into it.

Run with:

    python3 scripts/test_graded_folders_new_course.py
"""
import builtins
import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import setup_course  # noqa: E402
import toolchain_paths  # noqa: E402

REPOSITORY = Path(__file__).resolve().parent.parent
PAYLOADS = REPOSITORY / "support" / "example_content"

# A wizard that asks more than this has stopped accepting Return somewhere
# and is looping; fail rather than hang.
MOST_PROMPTS = 300

# Fewer pages than this means the run went down a path that installs nothing.
FEWEST_PAGES = 5


def payload_codes() -> list:
    codes = []
    for entry in sorted(PAYLOADS.iterdir()):
        if (entry / "manifest.json").is_file():
            codes.append(entry.name)
    return codes


def declared_pool(code: str) -> list:
    """The contract's "manifest" symbol: what the payload itself declares."""
    manifest = json.loads((PAYLOADS / code / "manifest.json").read_text(encoding="utf-8"))
    if "graded_folders" not in manifest:
        raise AssertionError(f"{code}'s manifest declares no marks pool")
    return manifest["graded_folders"]


class NewCourseGetsItsMarksPool(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = REPOSITORY / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        cls.rule = contracts.section("shared-rules", "gradedFolders", "newCourse")

    def create_course(self, code: str, takes_example: bool, keeps_skeleton: bool) -> dict:
        """Make a new course on the command line; return the file it wrote."""
        temporary = Path(tempfile.mkdtemp(prefix="plantoir-new-course-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        courses = temporary / "courses"
        courses.mkdir()

        original_courses = toolchain_paths.COURSES_DIR
        original_quartz = toolchain_paths.QUARTZ_DIR
        original_input = builtins.input
        original_getch = setup_course.getch
        prompts_seen = [0]
        code_typed = [False]

        def answer(prompt: str = "") -> str:
            prompts_seen[0] += 1
            if prompts_seen[0] > MOST_PROMPTS:
                raise RuntimeError("the wizard kept asking; it is looping")
            text = str(prompt).lower()
            if "enter the course code" in text:
                code_typed[0] = True
                return code
            if "pre-populate this course with example content?" in text:
                return "y" if takes_example else "n"
            if "start this course from that skeleton?" in text:
                return "y" if keeps_skeleton else "n"
            return ""

        def press_return() -> str:
            return "ENTER"

        toolchain_paths.COURSES_DIR = courses
        toolchain_paths.QUARTZ_DIR = temporary / "no-quartz-here"
        builtins.input = answer
        setup_course.getch = press_return
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                setup_course.setup_course(no_backup=True)
        finally:
            toolchain_paths.COURSES_DIR = original_courses
            toolchain_paths.QUARTZ_DIR = original_quartz
            builtins.input = original_input
            setup_course.getch = original_getch

        self.assertTrue(code_typed[0], "the wizard never asked for the course code")
        self.assertFalse((temporary / "no-quartz-here").exists(),
                         "the wizard created Quartz's folder")
        course = courses / code
        config_path = course / "course_config.json"
        self.assertTrue(config_path.is_file(),
                        f"no {code} course was made — the run went down another path")
        pages = list(course.rglob("*.md"))
        self.assertGreaterEqual(len(pages), FEWEST_PAGES,
                                f"{code}: only {len(pages)} pages were installed")
        written = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(written.get("course_code"), code)
        self.assertEqual(bool(written.get("prepopulate_example_content")), takes_example,
                         f"{code}: the run did not take the ready-made pages as asked")
        return written

    def test_every_new_course_case(self):
        cases = self.rule["cases"]
        self.assertGreaterEqual(len(cases), 6, "the contract lost new-course cases")
        played = 0
        for case in cases:
            # `appliesOn` names the APPS a case is for; the command line is
            # neither, so a case that carries one is not this runner's.
            if "appliesOn" in case:
                print(f"skipped on the command line: {case['name']} — "
                      f"{case.get('appliesOnWhy', 'not for this platform')}")
                continue
            if case.get("everyPayload"):
                codes = payload_codes()
                self.assertGreaterEqual(len(codes), 39, "the sweep found too few payloads")
            else:
                codes = [case["courseCode"]]
            takes_example = case["exampleContent"] == "taken"
            keeps_skeleton = bool(case.get("startsFromSkeleton", True))
            for code in codes:
                with self.subTest(case=case["name"], code=code):
                    written = self.create_course(code, takes_example, keeps_skeleton)
                    if case["expect"] == "manifest":
                        expected = declared_pool(code)
                    else:
                        expected = case["expect"]
                    self.assertIn("graded_folders", written,
                                  "a new course with no key reads as never asked")
                    self.assertEqual(written["graded_folders"], expected)
                    played += 1
        self.assertGreaterEqual(played, 43, "every command-line case, and one per payload")

    def test_every_manifest_case(self):
        cases = self.rule["manifestCases"]
        self.assertGreaterEqual(len(cases), 8, "the contract lost manifest cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                manifest = case["manifest"]
                shared = [name for name in manifest.get("shared_folders", []) if name != "Media"]
                per_section = list(manifest.get("per_section_folders", []))
                self.assertEqual(
                    setup_course.graded_folders_for(manifest, shared, per_section),
                    case["expect"])


if __name__ == "__main__":
    unittest.main()
