#!/usr/bin/env python3
"""
What a course calls a unit, and what follows from it.

Two halves, and the second is the one that matters most. The apps decide what
to NAME a new class page; the build decides what COUNTS as one — and when it
decides wrongly it does not fail. `_pages_the_course_teaches` returning nothing
makes the curriculum map fall back to counting every published page, so a
course whose pages are called "Module 2, Day 3" would get a map that looks
healthy and is wrong. That is why the contract's naming cases are run here
against the Python as well as in the app's own suite.
"""
import sys
import unittest
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import contracts
import toolchain_paths

import class_pages


class ContractNamingTests(unittest.TestCase):
    """The cases both suites run, from contracts/class-planning.json."""

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()

    def test_every_naming_case(self):
        import re

        cases = contracts.section("class-planning", "pageNaming", "cases")
        self.assertGreater(len(cases), 5, "The contract's naming cases went missing")
        for case in cases:
            title = case["title"]
            # A case with no `term` uses the default word, which is what a
            # course says when `unit_word` is absent from its configuration.
            term = case.get("term") or class_pages.DEFAULT_UNIT_WORD
            match = re.match(class_pages.class_page_pattern(term), title, re.IGNORECASE)
            expected_unit = case.get("expectUnit")
            why = f"{term}: {title} — {case.get('why', '')}"
            if expected_unit is None:
                self.assertIsNone(match, why)
                continue
            self.assertIsNotNone(match, why)
            self.assertEqual(int(match.group(1)), expected_unit, why)
            self.assertEqual(int(match.group(2)), case["expectDay"], why)


class BuildRecognisesTheCoursesOwnWordTests(unittest.TestCase):
    """The pattern is one thing; `build_site` actually using it is another."""

    def setUp(self):
        import build_site

        self.build_site = build_site
        self.addCleanup(build_site.set_unit_word, class_pages.DEFAULT_UNIT_WORD)

    def test_a_module_course_recognises_its_own_pages(self):
        self.build_site.set_unit_word("Module")
        self.assertTrue(self.build_site._is_class_page(Path("Module 2, Day 3.md")))
        self.assertFalse(
            self.build_site._is_class_page(Path("Unit 2, Day 3.md")),
            "Reading the OTHER word's pages as classes too would put two numbering "
            "schemes in one section",
        )

    def test_an_absent_word_still_means_unit(self):
        self.build_site.set_unit_word(class_pages.word_from_config({}))
        self.assertTrue(self.build_site._is_class_page(Path("Unit 2, Day 3.md")))

    def test_the_first_class_of_the_year_follows_the_word_too(self):
        import re

        self.build_site.set_unit_word("Module")
        self.assertTrue(re.match(self.build_site.first_class_pattern(), "Module 01, Day 1"))
        self.assertFalse(re.match(self.build_site.first_class_pattern(), "Unit 1, Day 1"))

    def test_a_front_page_is_never_a_class_page_whatever_the_word(self):
        self.build_site.set_unit_word("Module")
        self.assertFalse(self.build_site._is_class_page(Path("index.md")))
        self.assertFalse(self.build_site._is_class_page(Path("Key Links.md")))


class WordFromConfigTests(unittest.TestCase):

    def test_absent_and_empty_both_mean_unit(self):
        self.assertEqual(class_pages.word_from_config({}), "Unit")
        self.assertEqual(class_pages.word_from_config({"unit_word": ""}), "Unit")
        self.assertEqual(class_pages.word_from_config({"unit_word": "  "}), "Unit")
        self.assertEqual(class_pages.word_from_config({"unit_word": None}), "Unit")

    def test_a_word_is_trimmed(self):
        self.assertEqual(class_pages.word_from_config({"unit_word": " Module "}), "Module")

    def test_a_regex_character_in_the_word_is_taken_literally(self):
        """
        The word comes from a teacher's configuration. One containing "(" would
        otherwise quietly become a different pattern — or fail to compile in
        the middle of a build, which is the worse of the two.
        """
        import re

        pattern = class_pages.class_page_pattern("Unit (A)")
        self.assertIsNotNone(re.match(pattern, "Unit (A) 2, Day 3"))
        self.assertIsNone(re.match(pattern, "Unit A 2, Day 3"))


class PayloadRewriteTests(unittest.TestCase):
    """
    What happens to ready-made content as it is poured into a new course.

    Only ever run over content Plantoir itself ships — never over a teacher's
    own writing, where "Unit 3 of the textbook" would be a false positive
    nobody could undo.
    """

    def test_the_page_form_is_rewritten_everywhere_it_appears(self):
        text = "---\ntitle: Unit 2, Day 3\n---\nSee [[Unit 2, Day 4]] and [[Unit 2, Day 3|today]]."
        self.assertEqual(
            class_pages.rewritten(text, "Module"),
            "---\ntitle: Module 2, Day 3\n---\nSee [[Module 2, Day 4]] and [[Module 2, Day 3|today]].",
        )

    def test_a_bare_unit_reference_in_prose_follows_too(self):
        """
        Around 574 payload files say things like "by the end of Unit 3". Left
        alone, a Module course would talk about Units in its own pages.
        """
        self.assertEqual(
            class_pages.rewritten("By the end of Unit 3 you will...", "Thread"),
            "By the end of Thread 3 you will...",
        )

    def test_the_ordinary_english_word_is_left_alone(self):
        """
        A number is what separates a unit reference from the word "unit". This
        is the check that keeps the rewrite from editing prose.
        """
        for sentence in [
            "This unit of work is assessed.",
            "The unit circle has radius 1.",
            "Units are metres per second.",
        ]:
            self.assertEqual(class_pages.rewritten(sentence, "Module"), sentence)

    def test_the_default_word_changes_nothing_at_all(self):
        text = "title: Unit 2, Day 3"
        self.assertEqual(class_pages.rewritten(text, "Unit"), text)
        self.assertEqual(class_pages.renamed("Unit 2, Day 3.md", "Unit"), "Unit 2, Day 3.md")

    def test_a_file_name_is_renamed_only_at_the_front(self):
        self.assertEqual(
            class_pages.renamed("Unit 2, Day 3.md", "Module"), "Module 2, Day 3.md"
        )
        self.assertEqual(
            class_pages.renamed("Notes on Unit 2.md", "Module"), "Notes on Unit 2.md",
            "Only a name that BEGINS with the word is a class page's",
        )

    def test_a_backslash_in_the_word_is_not_read_as_an_escape(self):
        self.assertEqual(class_pages.rewritten("Unit 2, Day 3", r"A\1B"), r"A\1B 2, Day 3")


if __name__ == "__main__":
    unittest.main(verbosity=2)
