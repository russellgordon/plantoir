#!/usr/bin/env python3
"""
The command-line set-up asks no question named for one school, and a course
made with that question keeps everything it had (GitHub #891).

Until 2.0.0 `setup_course.py` asked whether to use one school's own folder
and file names. Russell removed the question on 2026-11-13. What must hold,
measured here by driving the REAL wizard (`setup_course.setup_course`) with
Return at every prompt, in-process as test_graded_folders_rerun.py does:

- no prompt mentions terminology, on a new course or on a re-run;
- a new course's file carries no `use_lcs_terminology`;
- a re-run over a course that has the key, that school's file names and the
  colour scheme's old id keeps all three exactly: the lists, the key (read by
  nothing, carried by the saved-keys loop) and the stored scheme id.

The old scheme id is read from support/colour_schemes.json, never typed here.
Pure Python, so Windows' PythonToolchainTests runs it too.
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

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import contracts  # noqa: E402
import setup_course  # noqa: E402
import toolchain_paths  # noqa: E402

COURSE_CODE = "ICS3U"
MOST_PROMPTS = 200
OLD_KEY = "use_lcs_terminology"

# A course made with the old question answered yes: its own folder and file
# names, as such a course's settings hold them.
EARLIER_SHARED_FOLDERS = [
    "Concepts", "Discussions", "Examples", "Exercises",
    "Ontario Curriculum", "College Board Curriculum", "Portfolios",
    "Recaps", "Setup", "Style", "Tasks", "Tutorials",
]
EARLIER_SHARED_FILES = ["SIC Drop-In Sessions.md", "Grove Time.md", "Learning Goals.md"]


def old_grove_id():
    schemes = json.loads((HERE.parent / "support" / "colour_schemes.json").read_text(encoding="utf-8"))
    for scheme in schemes:
        if scheme.get("listed", True) is False and scheme.get("sameAs") == "grove-colours":
            return scheme["id"]
    raise AssertionError("the scheme list holds no unlisted twin of grove-colours")


class SetupAsksNoSchoolQuestion(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = HERE.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()

    def run_setup(self, saved):
        """Run the wizard, Return at every prompt; return (file, prompts)."""
        temporary = Path(tempfile.mkdtemp(prefix="plantoir-terms-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        courses = temporary / "courses"
        course = courses / COURSE_CODE
        course.mkdir(parents=True)
        config_path = course / "course_config.json"
        if saved is not None:
            config_path.write_text(json.dumps(saved), encoding="utf-8")

        original_courses = toolchain_paths.COURSES_DIR
        original_quartz = toolchain_paths.QUARTZ_DIR
        original_input = builtins.input
        original_getch = setup_course.getch
        prompts = []

        def answer(prompt=""):
            prompts.append(str(prompt))
            if len(prompts) > MOST_PROMPTS:
                raise RuntimeError("the wizard kept asking; it is looping")
            if len(prompts) == 1:
                return COURSE_CODE
            return ""

        def press_return():
            return "ENTER"

        toolchain_paths.COURSES_DIR = courses
        toolchain_paths.QUARTZ_DIR = temporary / "no-quartz-here"
        builtins.input = answer
        setup_course.getch = press_return
        shown = io.StringIO()
        try:
            with contextlib.redirect_stdout(shown):
                setup_course.setup_course(no_backup=True)
        finally:
            toolchain_paths.COURSES_DIR = original_courses
            toolchain_paths.QUARTZ_DIR = original_quartz
            builtins.input = original_input
            setup_course.getch = original_getch
        return json.loads(config_path.read_text(encoding="utf-8")), prompts, shown.getvalue()

    def assert_no_terminology_question(self, prompts, shown):
        for prompt in prompts:
            self.assertNotIn("terminology", prompt.lower(), prompt)
        self.assertNotIn("terminology", shown.lower())

    def test_a_new_course_is_not_asked_and_does_not_record_the_key(self):
        written, prompts, shown = self.run_setup(None)
        self.assert_no_terminology_question(prompts, shown)
        self.assertNotIn(OLD_KEY, written)

    def test_a_rerun_keeps_an_earlier_course_exactly(self):
        old_id = old_grove_id()
        saved = {
            "course_code": COURSE_CODE,
            "course_name": "Introduction to Computer Science",
            "num_sections": 1,
            "section_numbers": [1],
            "shared_folders": list(EARLIER_SHARED_FOLDERS),
            "shared_files": list(EARLIER_SHARED_FILES),
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
            "use_skeleton": False,
            "prepopulate_example_content": False,
            OLD_KEY: True,
            "include_curriculum_coverage": False,
            "include_curriculum_pages": False,
            "include_coverage_notes": False,
            "color_schemes": {"section1": old_id},
        }
        written, prompts, shown = self.run_setup(saved)
        self.assert_no_terminology_question(prompts, shown)
        self.assertEqual(written["shared_folders"], EARLIER_SHARED_FOLDERS)
        self.assertEqual(written["shared_files"], EARLIER_SHARED_FILES)
        self.assertIs(written[OLD_KEY], True)
        self.assertEqual(written["color_schemes"], {"section1": old_id})


if __name__ == "__main__":
    unittest.main()
