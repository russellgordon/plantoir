#!/usr/bin/env python3
"""
A printed handout's corners and page labels (#454), against the CONTRACT.

The cases come from `contracts/shared-rules.json` -> `printablePages.corners`
and `.pageLabels`; the words the site prints from `printablePages.words`. Both
are written into every section's build as `quartz/plantoir_print.json`, which
the page's own print code reads - so what is tested here is exactly what
prints.

Stdlib only (`print_settings` reads the contract and the course's settings,
nothing else), so it runs on the Windows machine too.

Run with:

    python3 scripts/test_print_settings.py
"""
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import build_site
import contracts
import print_settings
import toolchain_paths


def use_the_repository_contract():
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


class CornerTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()
        cls.cases = contracts.section("shared-rules", "printablePages", "corners", "cases")

    def test_the_contract_still_carries_its_cases(self):
        self.assertGreaterEqual(len(self.cases), 10, "the contract lost corner cases")

    def test_every_corner_case_composes_as_the_contract_says(self):
        for case in self.cases:
            with self.subTest(case=case["name"]):
                displayed = build_site.displayed_course_code(case["settings"], case["folder"])
                corners = print_settings.compose(case["settings"], displayed)
                for corner in ("topLeft", "topRight", "bottomLeft"):
                    self.assertEqual(corners[corner], case["expect"][corner], corner)
                self.assertEqual(corners["bottomRight"], "pageLabel",
                                 "the bottom right corner is always the page label")

    def test_corners_are_one_line_each(self):
        for case in self.cases:
            displayed = build_site.displayed_course_code(case["settings"], case["folder"])
            corners = print_settings.compose(case["settings"], displayed)
            for corner, text in corners.items():
                self.assertNotIn("\n", text, f"{case['name']}: {corner}")


class PageLabelTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def test_every_page_label_case(self):
        for case in contracts.section("shared-rules", "printablePages", "pageLabels", "cases"):
            with self.subTest(case=case):
                self.assertEqual(print_settings.page_label(case["part"], case["n"], case["total"]),
                                 case["label"])


class WrittenSettingsTests(unittest.TestCase):
    """What the build writes for the page's own print code to read."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def setUp(self):
        self.output = Path(tempfile.mkdtemp(prefix="plantoir-print-settings-"))
        (self.output / "quartz").mkdir()

    def tearDown(self):
        shutil.rmtree(self.output, ignore_errors=True)

    def test_the_file_carries_the_contract_words_unchanged(self):
        path = print_settings.write(self.output, {"course_code": "ICS3U"}, "ICS3U")
        self.assertEqual(path, self.output / "quartz" / "plantoir_print.json")
        written = json.loads(path.read_text(encoding="utf-8"))
        words = contracts.section("shared-rules", "printablePages", "words")
        for key, value in words.items():
            if key in ("where", "why"):
                continue
            self.assertEqual(written["words"][key], value, key)
        self.assertNotIn("where", written["words"], "the notes for maintainers do not ship")

    def test_the_file_carries_the_corners_and_the_rules(self):
        settings = {"course_code": "ICS3U", "print_school_name": "Lakefield College School"}
        written = json.loads(print_settings.write(self.output, settings, "ICS3U").read_text(encoding="utf-8"))
        self.assertEqual(written["corners"], print_settings.compose(settings, "ICS3U"))
        rules = contracts.section("shared-rules", "printablePages", "answerCallouts")
        self.assertEqual(written["answerKinds"], rules["answerKinds"])
        self.assertEqual(written["answerTitleWords"], rules["answerTitleWords"])
        # The page's Curriculum connection is never printed (#498): the page
        # finds it by these words.
        self.assertEqual(written["curriculumHeadings"],
                         contracts.section("shared-rules", "printablePages",
                                           "curriculumConnection", "headingWords"))
        # Nothing prints until a way of printing is chosen (#499, decision
        # 29): there is no default for the page to fall back on.
        self.assertNotIn("defaultMode", written)
        self.assertNotIn("default", contracts.section("shared-rules", "printablePages", "modes"))

    def test_absent_settings_give_the_defaults(self):
        corners = print_settings.compose({}, "ICS3U")
        self.assertEqual(corners["topLeft"], "")
        self.assertEqual(corners["bottomLeft"], "ICS3U")
        self.assertTrue(corners["topRight"].startswith("Name "))

    def test_writing_twice_leaves_the_same_bytes(self):
        first = print_settings.write(self.output, {"course_code": "ICS3U"}, "ICS3U").read_bytes()
        second = print_settings.write(self.output, {"course_code": "ICS3U"}, "ICS3U").read_bytes()
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
