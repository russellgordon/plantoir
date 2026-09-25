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
        for value in (" !!str false", " >-", " &flag false", " *flag", ' "fal',
                      " %", " @x", " `x", " - false", " false: true"):
            self.assertEqual(
                page_visibility.publish_family_answer(value),
                page_visibility.CANNOT_TELL,
                f"publish:{value} is not something this reader should answer about",
            )

    def test_a_value_on_the_line_below_is_not_followed(self):
        # Measured: the build reads it and HIDES the page, so a reader that
        # called the key null would call a held-back page visible.
        self.assertEqual(
            page_visibility.publish_family_answer("", "  false"),
            page_visibility.CANNOT_TELL,
        )
        self.assertEqual(
            page_visibility.draft_family_answer("", "\ttrue"),
            page_visibility.CANNOT_TELL,
        )
        # But a key with nothing below it is a genuine null, which publishes.
        self.assertEqual(
            page_visibility.publish_family_answer("", "title: x"),
            page_visibility.VISIBLE,
        )
        self.assertEqual(page_visibility.publish_family_answer(""), page_visibility.VISIBLE)

    def test_a_value_below_a_complete_looking_one_is_still_a_value_below(self):
        # Measured 2026-09-19: every one of these pages is PUBLISHED by the
        # site. YAML folds the key's line and the line below into one plain
        # scalar — "false false", "no false", "maybe false" — and a string
        # that is not "false" publishes.
        #
        # Reading the key's line alone therefore called four of them hidden,
        # and called it confidently, which is what let a writer's "already
        # right, change nothing" gate turn "hide this page" into a no-op.
        for value in ("false", "no", "off", "FALSE", "true", "maybe"):
            self.assertEqual(
                page_visibility.publish_family_answer(" " + value, "  false"),
                page_visibility.CANNOT_TELL,
                f"publish: {value} with a value under it is not something to answer about",
            )
        # The legacy spelling refuses the same way.
        self.assertEqual(
            page_visibility.draft_family_answer(" true", "  x"),
            page_visibility.CANNOT_TELL,
        )
        # And a `# note` under a complete value is not a value: the caller has
        # already stepped over it, so `next_line` is whatever came after.
        self.assertEqual(
            page_visibility.publish_family_answer(" false", "title: x"),
            page_visibility.HIDDEN,
        )

    def test_only_spaces_and_tabs_are_whitespace(self):
        # A non-breaking space is what Option-Space types on a Mac. YAML does
        # not treat it as whitespace, so `false<NBSP>` is a STRING and the page
        # is PUBLISHED — measured. Trimming it would call that page hidden.
        self.assertEqual(
            page_visibility.publish_family_answer(" false\u00a0"), page_visibility.VISIBLE
        )
        self.assertEqual(
            page_visibility.publish_family_answer(" false\t"), page_visibility.HIDDEN
        )

    def test_a_backslash_is_an_escape_only_inside_double_quotes(self):
        # Single quotes have no escapes at all, so this is the string "fal\\se"
        # and the page is PUBLISHED — measured. Refusing it made the course
        # installer write `false` for a page the build shows, and disagreed
        # with the Swift reader, which had it right.
        self.assertEqual(
            page_visibility.publish_family_answer(" 'fal\\se'"), page_visibility.VISIBLE
        )
        self.assertEqual(
            page_visibility.draft_family_answer(" 'tr\\ue'"), page_visibility.VISIBLE
        )
        # Inside double quotes it really is an escape, and the characters here
        # are not the value.
        self.assertEqual(
            page_visibility.publish_family_answer(' "fal\\se"'), page_visibility.CANNOT_TELL
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
        for line in ("draft: !!str true", "draft: >-", "publish: >-"):
            out = self.split(line)
            self.assertIn("publishForSection1: false", out, line)

    def test_a_value_on_the_line_below_is_held_back_and_taken_with_it(self):
        # Measured: the build reads the indented line and HIDES the page. The
        # continuation has to go with the key — left behind, it becomes an
        # indented scalar under whatever key follows, which STOPS the build.
        for line in ("publish:\n  false", "draft:\n  true", "publish: >-\n  false"):
            out = self.split(line)
            self.assertIn("publishForSection1: false", out, line)
            self.assertIn("publishForSection2: false", out, line)
            self.assertNotIn("  false", out, line)
            self.assertNotIn("  true", out, line)

    def test_a_blank_line_does_not_end_a_value_written_below_the_key(self):
        # Measured: the build reads past the blank line and HIDES both of
        # these. A scan that stopped at the blank called the key null and
        # published a held-back page into every section at course setup.
        for line in ("draft:\n\n  true", "publish:\n\n  false"):
            out = self.split(line)
            self.assertIn("publishForSection1: false", out, line)
            self.assertIn("publishForSection2: false", out, line)
            self.assertNotIn("  true", out, line)
            self.assertNotIn("  false", out, line)

    def test_an_indented_comment_is_not_a_value_and_is_never_deleted(self):
        # Measured: `publish: true` followed by an indented `# note` is still
        # true, and `publish:` followed by one is still null. The note is the
        # teacher's, so it stays exactly where they wrote it.
        out = self.split("publish: true\n  # mine")
        self.assertIn("publishForSection1: true", out)
        self.assertIn("  # mine", out)

        out = self.split("publish:\n  # mine")
        self.assertIn("publishForSection1:\n", out)
        self.assertIn("  # mine", out)

        # But a real value UNDER the comment is still a value.
        out = self.split("publish:\n  # mine\n  false")
        self.assertIn("publishForSection1: false", out)

    def test_a_comment_at_column_0_is_stepped_over_like_any_other(self):
        # The splitter used to step over a comment only when it was INDENTED,
        # so a note at column 0 between a key and its value ended the scan.
        # Measured 2026-09-19: `publish:` / `# note` / `  false` is HIDDEN
        # before the split and the old splitter left section 1 reading
        # `publish: null` — VISIBLE. The teacher held the page back and one
        # section published it; with a single section it happened to survive,
        # which is why nothing noticed.
        out = self.split("publish:\n# note\n  false")
        self.assertIn("publishForSection1: false", out)
        self.assertIn("publishForSection2: false", out)
        self.assertNotIn("  false", out)

        # The same where the key's own line looks complete. The build cannot
        # parse that page either way — the orphaned value is a mapping error —
        # so this is an unreadable page being split into pages that still are
        # (hidden and named by the build since #246; before it, a build that
        # stopped), rather than a published page becoming an unreadable one.
        out = self.split("publish: false\n# note\n  false")
        self.assertIn("publishForSection1: false", out)
        self.assertNotIn("  false", out)

        # The consequence worth stating: a column-0 note BETWEEN a key and its
        # value goes WITH the value, which is what the rule already said. A
        # note with NOTHING under it is still left exactly where it was.
        self.assertNotIn("# note", out)
        kept = self.split("publish: true\n# note")
        self.assertIn("publishForSection1: true", kept)
        self.assertIn("# note", kept)
        kept = self.split("publish:\n# note\ntitle: x")
        self.assertIn("publishForSection1:\n", kept)
        self.assertIn("# note", kept)

    def test_a_key_with_nothing_after_it_stays_a_null(self):
        # A null PUBLISHES the page. Writing "false" here would hide, at course
        # setup, a page the teacher's own file publishes.
        out = self.split("publish:")
        self.assertIn("publishForSection1:\n", out)
        self.assertNotIn("publishForSection1: false", out)

    def test_the_last_of_two_identical_keys_wins(self):
        # PyYAML keeps the last, so the build reads the last. Taking the first
        # published a page into every new section that the build hides.
        out = self.split("publish: true\npublish: false")
        self.assertIn("publishForSection1: false", out)
        self.assertNotIn("publishForSection1: true", out)
        out = self.split("draft: false\ndraft: true")
        self.assertIn("publishForSection1: false", out)

    def test_the_other_legal_spellings_of_the_key_are_split_too(self):
        for line in ('"publish": false', "publish : false", "'publish': false"):
            out = self.split(line)
            self.assertIn("publishForSection1: false", out, line)
            self.assertNotIn(line, out, f"{line} should have been replaced, not left beside the split")

    def test_a_colon_with_no_space_after_it_is_not_a_key(self):
        # `publish:false` is one plain scalar, not a mapping. Measured: a page
        # whose whole frontmatter is that line reaches Quartz with no keys.
        out = self.split("publish:false")
        self.assertNotIn("publishForSection", out)

    def test_a_page_with_no_flag_is_given_none(self):
        out = self.split("title: Course Outline")
        self.assertNotIn("publishForSection", out)


if __name__ == "__main__":
    unittest.main()
