#!/usr/bin/env python3
"""
A link written inside code is an example of a link, not a link (#313).

`contracts/shared-rules.json` -> `readingALink.whatIsCode` says where code is,
and `readingALink.cases` pins it. `markdown_code.py` is the one Python
implementation; every reader in the build and the installer asks it. This
file runs the contract through the build's dating walk, and checks the
coverage map, the module's own edges, and that a rewriter never touches code.

Stdlib only and no Docker, so Windows' `PythonToolchainTests` discovers and
runs it too.
"""
import re
import tempfile
import unittest
from pathlib import Path

import build_site
import contracts
import markdown_code
import setup_course
import toolchain_paths

REPO = Path(__file__).resolve().parent.parent
LINK = re.compile(r"(!?\[\[)([^\]|#]+?)(?=\\?[\]|#])")


def link_cases():
    repo_contracts = REPO / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()
    cases = contracts.load("shared-rules")["readingALink"]["cases"]
    assert len(cases) >= 40, "readingALink lost cases"
    return cases


def names_read(text: str) -> list:
    """The contract's `expect` shape: each name once, as written."""
    names = []
    for match in markdown_code.matches_outside_code(LINK, text):
        name = match.group(2).strip()
        if name.lower().endswith(".md"):
            name = name[:-3]
        if name not in names:
            names.append(name)
    return names


class ContractTests(unittest.TestCase):

    def test_every_case_through_the_mask(self):
        for case in link_cases():
            with self.subTest(case=case["name"]):
                self.assertEqual(names_read(case["text"]), case["expect"])

    def test_every_case_through_the_dating_walk(self):
        # build_site._extract_wikilink_targets holds each name by its last
        # component and by its whole path, lowercased.
        for case in link_cases():
            with self.subTest(case=case["name"]):
                expected = set()
                for name in case["expect"]:
                    expected.add(name.split("/")[-1].strip().lower())
                    expected.add(name.lower())
                self.assertEqual(build_site._extract_wikilink_targets(case["text"]), expected)

    def test_a_rename_never_touches_code(self):
        # Renaming EVERY name the pattern finds, code included, changes only
        # what is outside code: each code range comes back byte for byte.
        for case in link_cases():
            with self.subTest(case=case["name"]):
                text = case["text"]
                renames = {}
                for match in LINK.finditer(text):
                    renames[match.group(2).strip().split("/")[-1]] = "RENAMED"
                for name in case["expect"]:
                    renames[name.split("/")[-1]] = "RENAMED"
                renamed = setup_course.retargeted_expectation_references(text, renames)
                for start, end in markdown_code.code_ranges(text):
                    self.assertIn(text[start:end], renamed)
                self.assertEqual(renamed.count("RENAMED"),
                                 len(markdown_code.matches_outside_code(LINK, text)))


class EdgeTests(unittest.TestCase):

    def test_an_empty_page_and_a_page_that_is_one_fence(self):
        self.assertEqual(markdown_code.code_ranges(""), [])
        self.assertEqual(markdown_code.code_ranges("```"), [(0, 3)])
        self.assertEqual(markdown_code.code_ranges("```\n[[A]]\n```\n"), [(0, 14)])

    def test_offsets_are_code_points(self):
        text = "é🙂 `[[Code]]` [[Real]]"
        self.assertEqual(names_read(text), ["Real"])
        start, end = markdown_code.code_ranges(text)[0]
        self.assertEqual(text[start:end], "`[[Code]]`")

    def test_a_tilde_fence_may_carry_backticks_in_its_info_string(self):
        self.assertEqual(names_read("~~~ `x`\n[[Code]]\n~~~\n[[Real]]\n"), ["Real"])

    def test_nested_quotes(self):
        self.assertEqual(names_read("> > ```\n> > [[Code]]\n> > ```\n> > [[Real]]\n"), ["Real"])

    def test_a_heading_line_ends_a_span_s_paragraph(self):
        self.assertEqual(names_read("a ` b\n# [[Real]] ` c\n"), ["Real"])


class CommentTests(unittest.TestCase):
    """A %% comment is never a link either (#331, readingALink.whatIsAComment)."""

    def test_comment_ranges_pair_left_to_right_and_leave_a_lone_one(self):
        self.assertEqual(markdown_code.comment_ranges("a %%b%% c %%d"), [(2, 7)])
        self.assertEqual(markdown_code.comment_ranges("%%\n%%"), [(0, 5)])

    def test_code_ranges_hold_code_only(self):
        # The curriculum markers are comments: code_ranges must not report
        # them, or every block would be skipped and the map would go empty.
        text = "%%curriculum-start%%\n![[A1.1]]\n%%curriculum-end%%\n"
        self.assertEqual(markdown_code.code_ranges(text), [])
        self.assertEqual(len(markdown_code.not_a_link_ranges(text)), 2)

    def test_offsets_line_up_after_an_astral_character_before_a_comment(self):
        # Built in the wrong unit, every range after the emoji is off by one.
        text = "🙂 %% [[Hidden]] %% `[[Code]]` [[Real]]"
        self.assertEqual(names_read(text), ["Real"])
        start, end = markdown_code.code_ranges(text)[0]
        self.assertEqual(text[start:end], "`[[Code]]`")
        start, end = markdown_code.comment_ranges(text)[0]
        self.assertEqual(text[start:end], "%% [[Hidden]] %%")

    def test_the_installer_leaves_a_link_in_a_comment_alone(self):
        text = "%% was [[Old]] %% now [[Old]]\n"
        unlinked = setup_course.unlink_curriculum_references(text, {"Old"})
        self.assertEqual(unlinked, "%% was [[Old]] %% now Old\n")


class CoverageTests(unittest.TestCase):
    """The coverage map counts nothing written inside code."""

    def covered(self, lesson_body: str) -> dict:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            curriculum = root / "Curriculum"
            curriculum.mkdir()
            codes = ["A1.1", "A1.2", "B1.1"]
            for code in codes:
                (curriculum / f"{code}.md").write_text(f"# {code}\n", encoding="utf-8")
            (root / "All Classes").mkdir()
            (root / "All Classes" / "Unit 1, Day 1.md").write_text(
                "Today: [[Lesson]]\n", encoding="utf-8")
            (root / "Lesson.md").write_text(lesson_body, encoding="utf-8")
            specific = {}
            for code in codes:
                specific[code] = code
            covered_by, _ = build_site._coverage_counts(
                root, curriculum, specific, ["All Classes"], ["Tasks"], True)
            counts = {}
            for code in codes:
                counts[code] = len(covered_by[code])
            return counts

    def test_a_fenced_embed_and_a_fenced_block_count_nothing_and_the_real_block_counts(self):
        body = ("Write a connection like this:\n\n"
                "```markdown\n![[A1.1]]\n%%curriculum-start%%\n[[A1.2]]\n%%curriculum-end%%\n```\n\n"
                "Or inline, `![[A1.1]]`.\n\n"
                "%%curriculum-start%%\n[[B1.1]]\n%%curriculum-end%%\n")
        self.assertEqual(self.covered(body), {"A1.1": 0, "A1.2": 0, "B1.1": 1})

    def test_a_fenced_start_marker_does_not_swallow_the_real_block(self):
        body = ("```\n%%curriculum-start%%\n```\n\n"
                "%%curriculum-start%%\n[[B1.1]]\n%%curriculum-end%%\n")
        self.assertEqual(self.covered(body), {"A1.1": 0, "A1.2": 0, "B1.1": 1})

    def test_an_example_in_a_block_does_not_swallow_the_real_link_after_it(self):
        body = "%%curriculum-start%%\nType `[[` then [[B1.1]]\n%%curriculum-end%%\n"
        self.assertEqual(self.covered(body), {"A1.1": 0, "A1.2": 0, "B1.1": 1})

    def test_a_real_embed_still_counts(self):
        self.assertEqual(self.covered("![[A1.1]]\n"), {"A1.1": 1, "A1.2": 0, "B1.1": 0})

    def test_an_embed_in_a_comment_counts_nothing_and_a_real_block_still_counts(self):
        # #331: `%% ![[A1.1]] %%` is removed before Quartz draws anything, so
        # it covers nothing; the block's markers are comments too, and the
        # block must still count (the map-empties trap).
        body = ("%% ![[A1.1]] %%\n\n"
                "%%curriculum-start%%\n![[B1.1]]\n%%curriculum-end%%\n")
        self.assertEqual(self.covered(body), {"A1.1": 0, "A1.2": 0, "B1.1": 1})


if __name__ == "__main__":
    unittest.main()
