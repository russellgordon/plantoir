#!/usr/bin/env python3
"""
What course setup writes about a course's curriculum folders (#128).

`curriculum_folders` (a list) is written for a course that has none recorded,
from the one folder its payload or skeleton manifest declares; a saved list is
kept exactly; and a course whose only record is the legacy `curriculum_folder`
is left alone. That last one is a BUG FIX, not a new rule: setup used to write
`curriculum_folder` from the manifest unconditionally, and the saved-keys merge
only restores keys the fresh configuration lacks — so re-running setup on a
course whose folder a rename had recorded as "Expectations" put the manifest's
"Curriculum" (or null) back over it, and the rename's whole point was undone.

The re-runs drive the REAL wizard (`setup_course.setup_course`), pressing
Return at every prompt, in the way scripts/test_graded_folders_rerun.py does,
and read back what it wrote. In-process, no Docker: verify.sh runs it on the
mac host and Windows' PythonToolchainTests discovers it.
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

import setup_course  # noqa: E402
import toolchain_paths  # noqa: E402

COURSE_CODE = "ICS3U"

QUIET_ANSWERS = {
    "course_code": COURSE_CODE,
    "course_name": "Introduction to Computer Science",
    "num_sections": 1,
    "section_numbers": [1],
    "shared_folders": ["Concepts", "Expectations"],
    "shared_files": [],
    "per_section_folders": ["All Classes"],
    "per_section_files": [],
    "hidden": [],
    "expandable": [],
    "use_skeleton": False,
    "prepopulate_example_content": False,
    "use_lcs_terminology": False,
    "include_curriculum_coverage": False,
    "include_curriculum_pages": False,
    "include_coverage_notes": False,
}

MOST_PROMPTS = 200


def rerun_setup(test: unittest.TestCase, saved_extra: dict) -> dict:
    temporary = Path(tempfile.mkdtemp(prefix="plantoir-curriculum-"))
    test.addCleanup(shutil.rmtree, temporary, True)
    courses = temporary / "courses"
    course = courses / COURSE_CODE
    course.mkdir(parents=True)
    saved = dict(QUIET_ANSWERS)
    saved.update(saved_extra)
    for name in saved["shared_folders"]:
        (course / name).mkdir(exist_ok=True)
    config_path = course / "course_config.json"
    config_path.write_text(json.dumps(saved), encoding="utf-8")

    original = (toolchain_paths.COURSES_DIR, toolchain_paths.QUARTZ_DIR,
                builtins.input, setup_course.getch)
    prompts_seen = [0]

    def answer(prompt: str = "") -> str:
        prompts_seen[0] += 1
        if prompts_seen[0] > MOST_PROMPTS:
            raise RuntimeError("the wizard kept asking; it is looping")
        return COURSE_CODE if prompts_seen[0] == 1 else ""

    toolchain_paths.COURSES_DIR = courses
    toolchain_paths.QUARTZ_DIR = temporary / "no-quartz-here"
    builtins.input = answer
    setup_course.getch = lambda: "ENTER"
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            setup_course.setup_course(no_backup=True)
    finally:
        (toolchain_paths.COURSES_DIR, toolchain_paths.QUARTZ_DIR,
         builtins.input, setup_course.getch) = original
    return json.loads(config_path.read_text(encoding="utf-8"))


class ARerunKeepsWhatWasRecorded(unittest.TestCase):

    def test_a_renamed_folder_survives_a_rerun(self):
        written = rerun_setup(self, {"curriculum_folder": "Expectations",
                                     "curriculum_folders": ["Expectations"]})
        self.assertEqual(written.get("curriculum_folder"), "Expectations",
                         "setup put the manifest's folder back over a recorded rename")
        self.assertEqual(written.get("curriculum_folders"), ["Expectations"])

    def test_a_legacy_only_course_is_left_alone(self):
        written = rerun_setup(self, {"curriculum_folder": "Expectations"})
        self.assertEqual(written.get("curriculum_folder"), "Expectations")
        self.assertNotIn("curriculum_folders", written)

    def test_a_saved_list_is_kept_exactly(self):
        written = rerun_setup(self, {"curriculum_folders": ["Ontario Curriculum", "AP CSP"]})
        self.assertEqual(written.get("curriculum_folders"), ["Ontario Curriculum", "AP CSP"])
        self.assertNotIn("curriculum_folder", written)

    def test_a_course_from_scratch_records_nothing(self):
        written = rerun_setup(self, {})
        self.assertNotIn("curriculum_folders", written)
        self.assertNotIn("curriculum_folder", written)


class WhatANewCourseRecords(unittest.TestCase):
    """The rule itself, for the manifest half a quiet re-run cannot reach."""

    def test_the_manifests_folder_as_a_list_of_one(self):
        self.assertEqual(setup_course.curriculum_folders_to_record({}, "Curriculum"), ["Curriculum"])
        self.assertEqual(setup_course.curriculum_folders_to_record(
            {"course_code": "ICS3U"}, "Curriculum"), ["Curriculum"])

    def test_nothing_when_the_manifest_declares_nothing(self):
        self.assertIsNone(setup_course.curriculum_folders_to_record({}, None))
        self.assertIsNone(setup_course.curriculum_folders_to_record({"curriculum_folder": None}, None))

    def test_a_saved_list_or_legacy_name_wins_over_the_manifest(self):
        self.assertEqual(setup_course.curriculum_folders_to_record(
            {"curriculum_folders": ["Expectations"]}, "Curriculum"), ["Expectations"])
        self.assertIsNone(setup_course.curriculum_folders_to_record(
            {"curriculum_folder": "Expectations"}, "Curriculum"))
        self.assertEqual(setup_course.curriculum_folders_to_record(
            {"curriculum_folder": None}, "Curriculum"), ["Curriculum"])


if __name__ == "__main__":
    unittest.main()
