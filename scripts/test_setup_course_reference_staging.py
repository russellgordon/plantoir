#!/usr/bin/env python3
"""
A course made straight onto the Reference Courses shelf is set up inside the
app's hidden staging folder, and the live course of the same code is never
touched (GitHub issue #572).

The cases are deserialised from `contracts/course-management.json` ->
courseCode.setupIntoStaging, never retyped. Each one drives the REAL setup
(`setup_course.setup_course(reference_staging_folder=...)`) in-process, the
way scripts/test_graded_folders_new_course.py does: `input` and
`setup_course.getch` are replaced so every prompt is answered with Return,
COURSES_DIR is pointed at a temporary folder, and QUARTZ_DIR at a folder that
does not exist. No terminal, pty or Docker is needed; verify.sh runs it on the
mac host and Windows' PythonToolchainTests discovers it.

Every case starts from the same working folder: a LIVE courses/ICS3U holding
section1 only and none of the shared folders the staged settings name, so a
path that wrote into the live course instead of the staging folder would make
a folder there (plan review M5). Afterwards the live course is compared byte
for byte with how it started, and for a refusal the whole courses folder is.

Run with:

    python3 scripts/test_setup_course_reference_staging.py
"""
import builtins
import contextlib
import hashlib
import io
import json
import os
import re
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

# A run that asks more than this has stopped accepting Return somewhere.
MOST_PROMPTS = 300

# Fewer pages than this means the ready-made pages did not land.
FEWEST_PAGES = 20


def tree_manifest(root: Path) -> dict:
    """Every file and folder under root, with a digest of each file."""
    manifest = {}
    for path in sorted(root.rglob("*")):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            manifest[relative] = "link:" + os.readlink(path)
        elif path.is_dir():
            manifest[relative] = "folder"
        else:
            manifest[relative] = hashlib.sha1(path.read_bytes()).hexdigest()
    return manifest


def reference_settings(code: str) -> dict:
    """What the apps write into the staging folder before the run."""
    return {
        "course_code": code,
        "course_name": "Reference copy",
        "num_sections": 2,
        "section_numbers": [1, 2],
        "prepopulate_example_content": True,
        "include_curriculum_pages": True,
        "use_skeleton": False,
        "kept_for_reference": True,
        "reference_school_year": 2026,
        "deploy_target": "local_folder",
        "deploy_folder_path": "",
    }


class SetupIntoStaging(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = REPOSITORY / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        cls.rule = contracts.section("course-management", "courseCode", "setupIntoStaging")

    def make_working_folder(self) -> Path:
        temporary = Path(tempfile.mkdtemp(prefix="plantoir-reference-staging-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        courses = temporary / "courses"
        live = courses / "ICS3U"
        (live / "section1").mkdir(parents=True)
        (live / "course_config.json").write_text(json.dumps({
            "course_code": "ICS3U",
            "course_name": "The live course",
            "num_sections": 1,
            "section_numbers": [1],
            "deploy_target": "cloudflare_pages",
        }, indent=2) + "\n", encoding="utf-8")
        (live / "section1" / "index.md").write_text(
            "---\ntitle: Live front page\npublish: true\n---\nTaught this year.\n", encoding="utf-8")
        (live / "A page of mine.md").write_text("Written by the teacher.\n", encoding="utf-8")
        return temporary

    def stage(self, courses: Path, case: dict) -> None:
        folder_name = case["folder"]
        settings_kind = case["settings"]
        if "/" in folder_name:
            # The folder the climbing name would resolve to is made, so a run
            # that followed it would have something to write into.
            target = (courses / folder_name).resolve()
            target.mkdir(parents=True, exist_ok=True)
            (target / "course_config.json").write_text(
                json.dumps(reference_settings(case["code"])), encoding="utf-8")
            return
        if case.get("link"):
            real = courses.parent / "somewhere-else"
            real.mkdir()
            (real / "course_config.json").write_text(
                json.dumps(reference_settings(case["code"])), encoding="utf-8")
            try:
                (courses / folder_name).symlink_to(real, target_is_directory=True)
            except OSError as error:
                # Windows lets an ordinary account make a symbolic link only
                # with Developer Mode on (WinError 1314, measured on Windows 11
                # Pro 26200): this machine's setting, not the launcher's
                # behaviour. The case still runs on the mac and in the container.
                if getattr(error, "winerror", None) == 1314:
                    self.skipTest("this Windows account may not make symbolic links (WinError 1314, "
                                  "Developer Mode off); the case runs on the mac and in the container")
                raise
            return
        staging = courses / folder_name
        if staging.exists():
            # The bare name is the live course itself, which stays as it is.
            return
        staging.mkdir()
        if settings_kind == "none":
            return
        settings = reference_settings(case["code"])
        if settings_kind == "notReference":
            del settings["kept_for_reference"]
        (staging / "course_config.json").write_text(
            json.dumps(settings, indent=2) + "\n", encoding="utf-8")

    def run_setup(self, temporary: Path, folder_name: str, install_fails: bool = False):
        """Runs setup with the flag; returns (exit code or None, output, asked)."""
        courses = temporary / "courses"
        original_courses = toolchain_paths.COURSES_DIR
        original_quartz = toolchain_paths.QUARTZ_DIR
        original_input = builtins.input
        original_getch = setup_course.getch
        original_install = setup_course.install_example_content
        prompts = []

        def answer(prompt: str = "") -> str:
            prompts.append(str(prompt))
            if len(prompts) > MOST_PROMPTS:
                raise RuntimeError("setup kept asking; it is looping")
            return ""

        def press_return() -> str:
            return "ENTER"

        def install_that_fails(*arguments, **keywords):
            raise OSError("the disk said no")

        toolchain_paths.COURSES_DIR = courses
        toolchain_paths.QUARTZ_DIR = temporary / "no-quartz-here"
        builtins.input = answer
        setup_course.getch = press_return
        if install_fails:
            setup_course.install_example_content = install_that_fails
        output = io.StringIO()
        exit_code = None
        try:
            with contextlib.redirect_stdout(output):
                setup_course.setup_course(reference_staging_folder=folder_name)
        except SystemExit as stopped:
            exit_code = stopped.code
        finally:
            toolchain_paths.COURSES_DIR = original_courses
            toolchain_paths.QUARTZ_DIR = original_quartz
            builtins.input = original_input
            setup_course.getch = original_getch
            setup_course.install_example_content = original_install
        return exit_code, output.getvalue(), prompts

    def test_the_contract_has_its_cases(self):
        expectations = set()
        for case in self.rule["cases"]:
            expectations.add(case["expect"])
        self.assertGreaterEqual(len(self.rule["cases"]), 8)
        self.assertEqual(expectations, {"setUp", "refused", "noPages"})

    def test_the_sentences_are_the_contracts(self):
        said = self.rule["said"]
        self.assertEqual(setup_course.REFERENCE_STAGING_REFUSED, said["refused"])
        self.assertEqual(setup_course.REFERENCE_PAGES_NOT_INSTALLED, said["noPages"])

    def test_the_prefix_is_the_apps(self):
        """One staging prefix across the script and both apps, and it is the
        shape the code prompt refuses."""
        prefix = setup_course.REFERENCE_STAGING_PREFIX
        mac = (REPOSITORY / "mac-app" / "QuartzTeachers" / "Models" / "ReferenceStaging.swift").read_text(encoding="utf-8")
        self.assertIsNotNone(
            re.search(r'static let prefix: String = "' + re.escape(prefix) + '"', mac),
            "ReferenceStaging.prefix on the mac is not the script's prefix")
        windows = REPOSITORY / "windows-app" / "Plantoir.Core" / "Models" / "ReferenceStaging.cs"
        if windows.is_file():
            self.assertIn('Prefix = "' + prefix + '"', windows.read_text(encoding="utf-8"))
        typed_cases = contracts.section("course-management", "courseCode", "commandLine")["cases"]
        dotted = []
        for case in typed_cases:
            if case["typed"].startswith(prefix):
                dotted.append(case)
        self.assertEqual(len(dotted), 1, "the code prompt no longer pins the staging shape")
        self.assertEqual(dotted[0]["expect"], "refused")

    def test_every_case(self):
        said = self.rule["said"]
        for case in self.rule["cases"]:
            with self.subTest(case["name"]):
                temporary = self.make_working_folder()
                courses = temporary / "courses"
                live = courses / "ICS3U"
                live_before = tree_manifest(live)
                self.stage(courses, case)
                courses_before = tree_manifest(courses)
                outside_before = tree_manifest(temporary)

                exit_code, output, prompts = self.run_setup(
                    temporary, case["folder"], install_fails=case.get("installFails", False))

                for prompt in prompts:
                    self.assertNotIn("enter the course code", prompt.lower(),
                                     "the code prompt was asked")
                    self.assertNotIn("install the example course", prompt.lower(),
                                     "the Example Course offer was asked")
                self.assertEqual(tree_manifest(live), live_before,
                                 "the live course was changed")
                self.assertFalse((courses / "_backups").exists(), "a backup was made")
                self.assertFalse((temporary / "no-quartz-here").exists())

                if case["expect"] == "refused":
                    self.assertEqual(exit_code, 1, output)
                    self.assertIn(said["refused"], output)
                    self.assertEqual(tree_manifest(temporary), outside_before,
                                     "a refused run wrote something")
                    continue

                if case["expect"] == "noPages":
                    self.assertEqual(exit_code, 1, output)
                    self.assertIn(said["noPages"].replace("{code}", case["code"]), output)
                    self.assertNotIn("set up successfully", output)
                    # Only the staging folder may have changed; the app
                    # removes it.
                    for name in tree_manifest(courses):
                        if name.startswith(case["folder"]):
                            continue
                        self.assertIn(name, courses_before, f"{name} appeared outside the staging folder")
                    continue

                self.assertEqual(case["expect"], "setUp")
                self.assertIsNone(exit_code, output)
                self.assertIn("set up successfully", output)
                self.assertNotIn("You can preview", output)
                self.assertNotIn("You can deploy", output)
                staging = courses / case["folder"]
                self.assertTrue((staging / "section1").is_dir())
                self.assertTrue((staging / "section2").is_dir())
                pages = list(staging.rglob("*.md"))
                self.assertGreaterEqual(len(pages), FEWEST_PAGES, "the ready-made pages did not land")
                written = json.loads((staging / "course_config.json").read_text(encoding="utf-8"))
                self.assertEqual(written.get("course_code"), case["code"])
                self.assertIs(written.get("kept_for_reference"), True)
                self.assertEqual(written.get("reference_school_year"), 2026)
                self.assertEqual(written.get("deploy_target"), "local_folder")
                # Nothing new anywhere in courses/ but the staging folder.
                for name in tree_manifest(courses):
                    if name.startswith(case["folder"]):
                        continue
                    self.assertIn(name, courses_before, f"{name} appeared outside the staging folder")

    def test_the_typed_path_still_makes_its_course(self):
        """The ordinary run, after the three path sites changed, still writes
        its folders into courses/<CODE>."""
        temporary = Path(tempfile.mkdtemp(prefix="plantoir-typed-path-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        courses = temporary / "courses"
        courses.mkdir()
        original_courses = toolchain_paths.COURSES_DIR
        original_quartz = toolchain_paths.QUARTZ_DIR
        original_input = builtins.input
        original_getch = setup_course.getch

        def answer(prompt: str = "") -> str:
            if "enter the course code" in str(prompt).lower():
                return "ICS4U"
            return ""

        toolchain_paths.COURSES_DIR = courses
        toolchain_paths.QUARTZ_DIR = temporary / "no-quartz-here"
        builtins.input = answer
        setup_course.getch = lambda: "ENTER"
        try:
            with contextlib.redirect_stdout(io.StringIO()) as output:
                setup_course.setup_course(no_backup=True)
        finally:
            toolchain_paths.COURSES_DIR = original_courses
            toolchain_paths.QUARTZ_DIR = original_quartz
            builtins.input = original_input
            setup_course.getch = original_getch
        self.assertTrue((courses / "ICS4U" / "section1" / "index.md").is_file())
        self.assertIn("You can preview ICS4U", output.getvalue())


if __name__ == "__main__":
    unittest.main()
