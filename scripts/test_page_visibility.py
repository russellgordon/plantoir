#!/usr/bin/env python3
"""
Whether the built site shows a page — the Python side, against the CONTRACT.

The cases are not retyped here. They are deserialised from
`contracts/file-formats.json` -> `pageVisibility.readingCases`, the same list
the macOS suite runs against `PageVisibilityReader` and the Windows suite runs
against `PageFrontmatter.IsDraft`. One rule, one list, three implementations.

**Stdlib only, and that is the point.** The round trip through
python-frontmatter can only be run inside the image
(`check_visibility_against_the_site.py`, driven by `verify.sh`). This half
needs nothing but Python, so `PythonToolchainTests` runs it on the Windows
machine as well — which has no python-frontmatter, and where a test that
SKIPPED itself would report green having run nothing.

What it covers: the two family predicates in `page_visibility`, the
curriculum-coverage map's reader in `build_site`, and the course-level
splitter in `setup_course` that writes a shared page's visibility out once per
section. The splitter is where the polarity used to invert: a `draft: yes`
page was split as PUBLISHED into every section while the build went on hiding
the original.
"""
import unittest
from pathlib import Path

import build_site
import contracts
import page_visibility
import setup_course
import toolchain_paths


def reading_cases():
    """The cases both app suites run, from contracts/file-formats.json."""
    # Inside the image the contract is baked at /opt/contracts; run from a
    # clone it is beside this folder. Same approach as test_class_pages.py.
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()
    return contracts.section("file-formats", "pageVisibility", "readingCases")


class FamilySpellingTests(unittest.TestCase):
    """The nine-and-nine table, stated once so nobody drops a spelling."""

    def test_every_yaml_true_spelling_holds_a_draft_page_back(self):
        for spelling in ("true", "True", "TRUE", "yes", "Yes", "YES", "on", "On", "ON"):
            self.assertEqual(
                page_visibility.draft_family_answer(" " + spelling),
                page_visibility.HIDDEN,
                f"draft: {spelling} is YAML 1.1's true, so the build hides the page",
            )

    def test_every_yaml_false_spelling_holds_a_publish_page_back(self):
        for spelling in ("false", "False", "FALSE", "no", "No", "NO", "off", "Off", "OFF"):
            self.assertEqual(
                page_visibility.publish_family_answer(" " + spelling),
                page_visibility.HIDDEN,
                f"publish: {spelling} is YAML 1.1's false, so the build hides the page",
            )

    def test_a_case_that_cannot_be_read_says_so_rather_than_guessing(self):
        for value in (" !!str false", " >-", " &flag false", " *flag", ' "fal'):
            self.assertEqual(
                page_visibility.publish_family_answer(value),
                page_visibility.CANNOT_TELL,
                f"publish:{value} is not something this reader should answer about",
            )

    def test_a_value_that_runs_onto_the_next_line_cannot_be_copied(self):
        self.assertTrue(page_visibility.is_complete_on_its_own_line(" oN # why"))
        self.assertTrue(page_visibility.is_complete_on_its_own_line(' "false"'))
        self.assertFalse(page_visibility.is_complete_on_its_own_line(" >-"))
        self.assertFalse(page_visibility.is_complete_on_its_own_line(" |"))
        self.assertFalse(page_visibility.is_complete_on_its_own_line("   "))


class CoverageMapReaderTests(unittest.TestCase):
    """
    `build_site._is_draft` — the curriculum-coverage map's own reader.

    Every contract case that uses the PLAIN keys is run through it. The
    per-section cases are not: `_is_draft` only ever sees the merged tree,
    where `process_frontmatter` has already resolved those keys onto a plain
    `publish:` and deleted them.
    """

    def test_the_contract_carries_enough_cases_to_be_worth_running(self):
        cases = reading_cases()
        self.assertGreater(len(cases), 30, "readingCases has shrunk — has an edit dropped the list?")
        self.assertTrue(any(case["expectVisible"] for case in cases))
        self.assertTrue(any(not case["expectVisible"] for case in cases))

    def test_every_plain_key_case_reads_the_way_the_contract_says(self):
        ran = 0
        for case in reading_cases():
            if "Section" in case["page"]:
                continue
            page = "---\n" + case["page"] + "\n---\n\nThe lesson.\n"
            visible = not build_site._is_draft(page)
            self.assertEqual(
                visible,
                case["expectVisible"],
                f"{case['page']!r}: {case.get('why', '')}",
            )
            ran += 1
        self.assertGreater(ran, 20, "No plain-key cases ran — the skip rule has swallowed the list")


class CourseLevelSplitterTests(unittest.TestCase):
    """
    `setup_course.per_section_frontmatter` — a shared page's one flag becomes
    one flag per section.
    """

    def split(self, frontmatter_line, sections=(1, 2)):
        text = "---\n" + frontmatter_line + "\n---\nBody.\n"
        return setup_course.per_section_frontmatter(text, list(sections))

    def test_a_publish_value_is_copied_exactly_as_written(self):
        # Copying the characters is what makes the copy safe: whatever the
        # build makes of the original it makes of the copy, so no reader
        # standing between them can invert it.
        for value in ("true", "false", "oN", "maybe", '"False"', "no # for now"):
            out = self.split("publish: " + value)
            self.assertIn("publishForSection1: " + value, out, value)
            self.assertIn("publishForSection2: " + value, out, value)

    def test_a_legacy_draft_value_is_turned_round_by_the_builds_own_rule(self):
        for value, expected in (
            ("true", "false"),
            ("false", "true"),
            ("yes", "false"),
            ("on", "false"),
            ("TrUe", "false"),
            ('"true"', "false"),
            ('"yes"', "true"),
            ("maybe", "true"),
            ("1", "true"),
            ("true # not ready", "false"),
        ):
            out = self.split("draft: " + value)
            self.assertIn(
                "publishForSection1: " + expected,
                out,
                f"draft: {value} should split as publishForSection1: {expected}",
            )
            self.assertNotIn("draft:", out, "the legacy key does not survive the split")

    def test_a_value_it_cannot_read_is_written_as_held_back(self):
        # A page wrongly held back is one a teacher notices and fixes; a page
        # wrongly published is one nobody notices at all.
        for line in ("draft: !!str true", "draft: >-", "publish: >-", "publish:"):
            out = self.split(line)
            self.assertIn("publishForSection1: false", out, line)

    def test_a_page_with_no_flag_is_given_none(self):
        out = self.split("title: Course Outline")
        self.assertNotIn("publishForSection", out)


if __name__ == "__main__":
    unittest.main()
