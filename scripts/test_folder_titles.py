#!/usr/bin/env python3
"""
A folder's index page names it in a title YAML can read back (#506's review).

Written plain, `title: Unit: One`, `title: 'Tis the Season` and
`title: & Friends` are pages the build cannot read: measured with the
dev-test image, each folder stayed out of the sidebar and the build's
unreadable-settings notice named a page Plantoir had just written. So the
course creator's writers, and each app's own writer for a folder added later
(the mac's `FolderScaffold`), quote a title whenever it needs it, by ONE rule:
`setup_course.title_needs_quoting` / `frontmatter_title`, pinned as
`contracts/course-management.json` -> `foldersAddedLater.titleQuoting`.

Three checks:

- every `titleQuoting` case through `setup_course.frontmatter_title`;
- the REAL wizard (`setup_course.setup_course`, in-process, as
  test_graded_folders_new_course.py drives it) making a course whose folders
  are three of those names and the contract's colon-and-space case: each
  index page's title line is the contract's, and the colon case's whole
  index page is the contract's bytes (setup's moment put in its place);
- every case, and a sweep of awkward names, read back through the build's own
  frontmatter reader — run inside the website builder's image, where that
  reader is installed. verify.sh runs this file both on the host (step 0) and
  in the image with PLANTOIR_REQUIRE_FRONTMATTER=1, which makes a missing
  reader a failure rather than a skip; Windows' PythonToolchainTests
  discovers it and runs the first two.

Run with:

    python3 scripts/test_folder_titles.py
"""
import builtins
import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import setup_course  # noqa: E402
import toolchain_paths  # noqa: E402

REPOSITORY = Path(__file__).resolve().parent.parent
CONTRACT_CANDIDATES = [
    REPOSITORY / "contracts" / "course-management.json",
    Path("/opt/contracts/course-management.json"),
]

MOST_PROMPTS = 300


def folders_added_later() -> dict:
    for candidate in CONTRACT_CANDIDATES:
        if candidate.is_file():
            return json.loads(candidate.read_text(encoding="utf-8"))["foldersAddedLater"]
    raise AssertionError("course-management.json was not found")


def frontmatter_reader():
    """The build's own reader, or None where it is not installed."""
    try:
        import frontmatter  # noqa: F401
    except ImportError:
        if os.environ.get("PLANTOIR_REQUIRE_FRONTMATTER") == "1":
            raise
        return None
    return frontmatter


class TheTitleRuleIsTheContracts(unittest.TestCase):

    def test_every_title_quoting_case(self):
        cases = folders_added_later()["titleQuoting"]["cases"]
        self.assertGreaterEqual(len(cases), 15, "titleQuoting has shrunk")
        for case in cases:
            self.assertEqual(setup_course.frontmatter_title(case["name"]), case["title"], case["name"])


class TheWizardWritesTheContractsTitles(unittest.TestCase):

    COLON_CASE_FOLDER = "Unit 1: Kinematics"

    def make_course(self, shared_folders: list, per_section_folders: list, sections: list) -> Path:
        temporary = Path(tempfile.mkdtemp(prefix="plantoir-folder-titles-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        courses = temporary / "courses"
        course = courses / "ZZZ3O"
        course.mkdir(parents=True)
        saved = {
            "course_code": "ZZZ3O", "course_name": "Test Course",
            "num_sections": len(sections), "section_numbers": sections,
            "shared_folders": shared_folders, "shared_files": [],
            "per_section_folders": per_section_folders, "per_section_files": [],
            "hidden": [], "expandable": [],
            "use_skeleton": False, "prepopulate_example_content": False,
            "use_lcs_terminology": False, "include_curriculum_coverage": False,
            "include_curriculum_pages": False, "include_coverage_notes": False,
        }
        (course / "course_config.json").write_text(json.dumps(saved), encoding="utf-8")

        original_courses = toolchain_paths.COURSES_DIR
        original_quartz = toolchain_paths.QUARTZ_DIR
        original_input = builtins.input
        original_getch = setup_course.getch
        prompts_seen = [0]

        def answer(prompt: str = "") -> str:
            prompts_seen[0] += 1
            if prompts_seen[0] > MOST_PROMPTS:
                raise RuntimeError("the wizard kept asking; it is looping")
            text = str(prompt).lower()
            if "enter the course code" in text:
                return "ZZZ3O"
            if "pre-populate" in text or "skeleton?" in text or "curriculum pages?" in text:
                return "n"
            return ""

        toolchain_paths.COURSES_DIR = courses
        toolchain_paths.QUARTZ_DIR = temporary / "no-quartz"
        builtins.input = answer
        setup_course.getch = lambda: "ENTER"
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                setup_course.setup_course(no_backup=True)
        finally:
            toolchain_paths.COURSES_DIR = original_courses
            toolchain_paths.QUARTZ_DIR = original_quartz
            builtins.input = original_input
            setup_course.getch = original_getch
        return course

    def title_line(self, page: Path) -> str:
        for line in page.read_text(encoding="utf-8").split("\n"):
            if line.startswith("title:"):
                return line
        raise AssertionError(f"{page} has no title line")

    def test_the_wizards_folder_pages_carry_the_contracts_titles(self):
        section = folders_added_later()
        titles = {}
        for case in section["titleQuoting"]["cases"]:
            titles[case["name"]] = case["title"]
        shared = ["Unit: One", "'Tis the Season", "Labs", self.COLON_CASE_FOLDER]
        per_section = ["& Friends"]
        course = self.make_course(shared, per_section, [1, 2])

        for folder in ["Unit: One", "'Tis the Season", "Labs"]:
            self.assertEqual(self.title_line(course / folder / "index.md"), "title: " + titles[folder], folder)
        for number in (1, 2):
            page = course / f"section{number}" / "& Friends" / "index.md"
            self.assertEqual(self.title_line(page), "title: " + titles["& Friends"])

        # The colon case's whole page, as the contract has it, with setup's
        # own moment put where the contract's stands.
        colon_case = None
        for case in section["cases"]:
            if case["folder"] == self.COLON_CASE_FOLDER:
                colon_case = case
        self.assertIsNotNone(colon_case, "the contract's colon-and-space case is gone")
        written = (course / self.COLON_CASE_FOLDER / "index.md").read_text(encoding="utf-8")
        moment = None
        for line in written.split("\n"):
            if line.startswith("createdSection1: "):
                moment = line[len("createdSection1: "):]
        self.assertIsNotNone(moment, written)
        expected = colon_case["files"][0]["text"].replace(section["created"], moment)
        self.assertEqual(written, expected)


class EveryTitleReadsBackAsItsName(unittest.TestCase):

    SWEEP = [
        "Unit: One", "'Tis the Season", "& Friends", "* Stars", "! Bang", "| Pipe", "> Quote",
        "% Percent", "@ At", "[Brackets]", "{Braces}", "# Hash", "- Dash", "? Question",
        ", Comma", ": Colon", "`Tick", "\"Quoted\"", "Yes", "no", "ON", "Off", "y", "N", "null",
        "Null", "~", "true", "False", "2024", "3.14", "1:20", "2026-09-24", "0x1F", ".inf",
        "end:", "trailing ", "Notes #1", "C#", "Q&A Corner", "Rock & Roll's", "Say \"Hi\"",
        "Back\\slash", "Élan", "日本語", "Tab\there", "a: b: c", "Labs",
    ]

    def test_every_case_and_the_sweep_read_back(self):
        reader = frontmatter_reader()
        if reader is None:
            self.skipTest("the build's frontmatter reader is not installed here; verify.sh runs this in the image")
        names = list(self.SWEEP)
        for case in folders_added_later()["titleQuoting"]["cases"]:
            names.append(case["name"])
        for name in names:
            written = setup_course.frontmatter_title(name)
            try:
                read = reader.loads(f"---\ntitle: {written}\n---\nbody\n").get("title")
            except Exception as error:  # noqa: BLE001 - any reader failure is the bug
                self.fail(f"{name!r} written as {written!r} could not be read: {error}")
            self.assertEqual(read, name, f"{name!r} written as {written!r}")

    def test_the_three_measured_names_fail_unquoted(self):
        reader = frontmatter_reader()
        if reader is None:
            self.skipTest("the build's frontmatter reader is not installed here; verify.sh runs this in the image")
        for name in ["Unit: One", "'Tis the Season", "& Friends"]:
            try:
                read = reader.loads(f"---\ntitle: {name}\n---\nbody\n").get("title")
            except Exception:  # noqa: BLE001
                continue
            self.assertNotEqual(read, name, f"{name!r} reads back plain, so the rule is quoting it for nothing")


if __name__ == "__main__":
    unittest.main()
