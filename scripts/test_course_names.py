#!/usr/bin/env python3
"""
A course's name is cleaned of control characters where it is read (GitHub #780).

`course_config.json` -> `course_name` can carry a NUL, a line break or a
right-to-left override, written as a JSON escape by a script, a hand edit or
another tool. The rule is `contracts/shared-rules.json` ->
`courseNameCharacters`: C0, DEL, C1, U+2028 and U+2029 become one space, the
bidirectional embeddings, overrides and isolates are removed, and nothing is
trimmed or collapsed. The macOS app runs the same cases in
`CourseNameCharactersTests`, and Windows in its own suite.

Pinned here:

  * every contract case through `course_names.cleaned`, and the rule applied
    twice changes nothing more;
  * the contract's two lists of ranges are exactly what the module answers,
    for every code point in the Basic Multilingual Plane;
  * the three shared readers: `build_site.computed_landing_title` (the front
    page heading, the page title and a printed page's footer),
    `social_card.generate_card`'s title (skipped without Pillow), and
    `setup_course.setup_course`, driven in-process over a saved course whose
    name holds a NUL, a tab and an override.

Pure stdlib apart from the card; no Docker, no network. Windows'
PythonToolchainTests discovers and runs it. Run with:

    python3 scripts/test_course_names.py
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

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))
os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))
os.environ.setdefault("PLANTOIR_SUPPORT_DIR", str(REPOSITORY_ROOT / "support"))

import contracts  # noqa: E402
import course_names  # noqa: E402
import toolchain_paths  # noqa: E402

try:
    import PIL  # noqa: F401
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

# A name holding a NUL, a line feed and a right-to-left override, and what
# every reader must make of it before any trimming of its own.
DIRTY_NAME = "Phys\u0000ics\n\u202eGrade 11"
CLEAN_NAME = "Phys ics Grade 11"


def the_rule() -> dict:
    repo_contracts = REPOSITORY_ROOT / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()
    return contracts.section("shared-rules", "courseNameCharacters")


def code_points(text: str) -> list:
    """The text as code points, so a failure shows exactly what differs."""
    values = []
    for character in text:
        values.append(ord(character))
    return values


def ranges_named(rule: dict, key: str) -> list:
    pairs = []
    for low, high in rule[key]:
        pairs.append((int(low, 16), int(high, 16)))
    return pairs


def is_inside(code_point: int, ranges: list) -> bool:
    for low, high in ranges:
        if low <= code_point <= high:
            return True
    return False


class TheRule(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.rule = the_rule()

    def test_every_case_cleans_as_the_contract_says(self):
        cases = self.rule["cases"]
        self.assertGreaterEqual(len(cases), 41, "the contract lost cases")
        self.assertIs(self.rule["idempotent"], True)
        for case in cases:
            with self.subTest(case=case["name"]):
                cleaned = course_names.cleaned(case["raw"])
                self.assertEqual(code_points(cleaned), code_points(case["expect"]))
                self.assertEqual(code_points(course_names.cleaned(cleaned)), code_points(cleaned))

    def test_the_ranges_are_the_contracts_ranges(self):
        spaced_out = ranges_named(self.rule, "spacedOut")
        removed = ranges_named(self.rule, "removed")
        mismatches = []
        for code_point in range(0x10000):
            if course_names.is_spaced_out(code_point) != is_inside(code_point, spaced_out):
                mismatches.append(f"spacedOut U+{code_point:04X}")
            if course_names.is_removed(code_point) != is_inside(code_point, removed):
                mismatches.append(f"removed U+{code_point:04X}")
        self.assertEqual(mismatches, [])
        for code_point in (0x1F469, 0xE0067, 0xE0100, 0x10FFFF):
            self.assertFalse(course_names.is_spaced_out(code_point))
            self.assertFalse(course_names.is_removed(code_point))

    def test_what_is_kept_on_purpose_is_kept(self):
        for entry in self.rule["keptOnPurpose"]:
            text = "A" + chr(int(entry["codePoint"], 16)) + "B"
            self.assertEqual(course_names.cleaned(text), text, entry["codePoint"])


class TheReaders(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        the_rule()

    def test_the_landing_title_is_cleaned_then_trimmed(self):
        import build_site
        config = {"course_code": "SPH3U", "course_name": DIRTY_NAME + "\u0000",
                  "show_grade_in_title": False}
        title = build_site.computed_landing_title(config, 1, True)
        self.assertEqual(code_points(title), code_points(CLEAN_NAME + ", Section 1"))

    def test_a_name_that_is_only_controls_falls_back_to_the_code(self):
        import build_site
        for raw in ("\u0000", "\n\u202e", "   "):
            config = {"course_code": "SPH3U", "course_name": raw, "show_grade_in_title": False}
            self.assertEqual(build_site.computed_landing_title(config, 1, True), "SPH3U, Section 1", repr(raw))

    @unittest.skipUnless(HAS_PILLOW, "the sharing card needs Pillow")
    def test_the_sharing_cards_title_is_cleaned(self):
        import social_card
        seen = []

        class Stop(Exception):
            pass

        def record(text, *arguments, **keywords):
            seen.append(text)
            raise Stop()

        original = social_card._title_layout
        social_card._title_layout = record
        try:
            with tempfile.TemporaryDirectory() as folder:
                with contextlib.redirect_stdout(io.StringIO()):
                    try:
                        social_card.generate_card(
                            {"course_code": "SPH3U", "course_name": DIRTY_NAME}, 1,
                            Path(folder) / "card.png")
                    except Stop:
                        pass
        finally:
            social_card._title_layout = original
        self.assertEqual(len(seen), 1, "the card never laid out its title")
        self.assertEqual(code_points(seen[0]), code_points(CLEAN_NAME))

    def test_setup_writes_the_saved_name_cleaned(self):
        import setup_course
        temporary = Path(tempfile.mkdtemp(prefix="plantoir-course-name-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        courses = temporary / "courses"
        # ICS3U is the wizard's default code, so Return at every prompt
        # reaches this course whichever prompt comes first.
        course = courses / "ICS3U"
        course.mkdir(parents=True)
        saved = {
            "course_code": "ICS3U",
            "course_name": "Physics\t11\u202e\u0000\u001b[2J",
            "num_sections": 1,
            "section_numbers": [1],
            "shared_folders": [],
            "per_section_folders": [],
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
        config_path = course / "course_config.json"
        config_path.write_text(json.dumps(saved), encoding="utf-8")

        original_courses = toolchain_paths.COURSES_DIR
        original_quartz = toolchain_paths.QUARTZ_DIR
        original_input = builtins.input
        original_getch = setup_course.getch
        prompts_seen = [0]

        prompts_shown = []

        def answer(prompt: str = "") -> str:
            prompts_shown.append(prompt)
            prompts_seen[0] += 1
            if prompts_seen[0] > 200:
                raise RuntimeError("the wizard kept asking; it is looping")
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

        written = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(code_points(written["course_name"]), code_points("Physics 11  [2J"))

        # The saved name is shown as the prompt's default CLEANED: an ESC or
        # a line break from the file never reaches the terminal (#780 review
        # M1). No prompt the run showed carries the name's NUL, override or
        # ESC; the prompts' own line breaks are theirs and stay.
        name_prompts = []
        for prompt in prompts_shown:
            if "course name" in prompt:
                name_prompts.append(prompt)
            for unwanted in ("\u0000", "\u202e", "\u001b[2J", "\t"):
                self.assertNotIn(unwanted, prompt)
        self.assertEqual(len(name_prompts), 1)
        self.assertIn("[Default: Physics 11  [2J]", name_prompts[0])
        front_page = course / "section1" / "index.md"
        if front_page.exists():
            text = front_page.read_text(encoding="utf-8")
            self.assertNotIn("\t", text)
            self.assertNotIn("\u202e", text)
            self.assertNotIn("\u0000", text)


if __name__ == "__main__":
    unittest.main()
