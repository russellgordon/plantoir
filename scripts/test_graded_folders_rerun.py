#!/usr/bin/env python3
"""
A re-run of course setup leaves a saved marks pool alone (GitHub issue #192).

The cases are deserialised from `contracts/shared-rules.json` ->
gradedFolders.rerunningSetup, never retyped. Each one drives the REAL wizard
(`setup_course.setup_course`) against a saved course, pressing Return at every
prompt, and reads back what it wrote — so what is pinned is the wiring, not a
helper that the wizard might stop calling.

Everything happens in-process: `input` and `setup_course.getch` are replaced,
so no terminal, no pty and no Docker are needed. That is what lets verify.sh
run this on the mac host in its first step, and Windows' PythonToolchainTests
run it too (it discovers every scripts/test_*.py). `build_site` is NOT
imported, since its `frontmatter` exists only inside the image.

The wizard writes only inside the temporary folder: COURSES_DIR is pointed at
it, and so is QUARTZ_DIR — at a folder that does not exist, because two steps
of the wizard patch Quartz's own files whenever that folder is there.

Run with:

    python3 scripts/test_graded_folders_rerun.py
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

COURSE_CODE = "ICS3U"

# Nothing is poured into the course: without these a skeleton or payload
# would create folders of its own (a skeleton's Tasks, say) and hide exactly
# the shapes the cases are about.
QUIET_ANSWERS = {
    "course_code": COURSE_CODE,
    "course_name": "Introduction to Computer Science",
    "num_sections": 1,
    "section_numbers": [1],
    "shared_files": [],
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

# A wizard that asks more than this has stopped accepting Return somewhere
# and is looping; fail rather than hang.
MOST_PROMPTS = 200


class SetupRerunKeepsTheMarksPool(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        cls.cases = contracts.section(
            "shared-rules", "gradedFolders", "rerunningSetup", "cases")

    def rerun_setup(self, case: dict) -> dict:
        """Build the case's course, run the wizard over it, return the file."""
        temporary = Path(tempfile.mkdtemp(prefix="plantoir-rerun-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        courses = temporary / "courses"
        course = courses / COURSE_CODE
        course.mkdir(parents=True)
        for directory in case["directories"]:
            (course / directory).mkdir(parents=True, exist_ok=True)

        saved = dict(QUIET_ANSWERS)
        saved["shared_folders"] = list(case["sharedFolders"])
        saved["per_section_folders"] = list(case["perSectionFolders"])
        for key, value in case["saved"].items():
            saved[key] = value
        config_path = course / "course_config.json"
        config_path.write_text(json.dumps(saved), encoding="utf-8")

        original_courses = toolchain_paths.COURSES_DIR
        original_quartz = toolchain_paths.QUARTZ_DIR
        original_input = builtins.input
        original_getch = setup_course.getch
        prompts_seen = [0]

        def answer(prompt: str = "") -> str:
            prompts_seen[0] += 1
            if prompts_seen[0] > MOST_PROMPTS:
                raise RuntimeError("the wizard kept asking; it is looping")
            if prompts_seen[0] == 1:
                return COURSE_CODE
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

        self.assertFalse((temporary / "no-quartz-here").exists(),
                         "the wizard created Quartz's folder")
        return json.loads(config_path.read_text(encoding="utf-8"))

    def test_every_rerun_case(self):
        self.assertGreaterEqual(len(self.cases), 10,
                                "the contract lost re-run cases")
        for case in self.cases:
            with self.subTest(case=case["name"]):
                written = self.rerun_setup(case)
                if "graded_folders" in case["expect"]:
                    self.assertIn("graded_folders", written)
                    self.assertEqual(written["graded_folders"],
                                     case["expect"]["graded_folders"])
                else:
                    self.assertNotIn("graded_folders", written)

    def test_the_run_kept_the_lists_it_was_given(self):
        # The cases are only meaningful if the run ENDS with the lists they
        # name: a wizard that quietly added a folder from disk would make a
        # case pass for the wrong reason.
        for case in self.cases:
            with self.subTest(case=case["name"]):
                written = self.rerun_setup(case)
                self.assertEqual(written["shared_folders"], case["sharedFolders"])
                self.assertEqual(written["per_section_folders"],
                                 case["perSectionFolders"])


if __name__ == "__main__":
    unittest.main()
