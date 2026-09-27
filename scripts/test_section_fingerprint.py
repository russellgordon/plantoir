#!/usr/bin/env python3
"""
The "— Edited" fingerprint's rules (#330), as `section_fingerprint.py`
computes them for Windows' scheduled wrapper.

`contracts/app-rules.json` -> `publishedFreshness.filesCountedUnderRule2`
through the Python filter AND the walk, that the two rules hash identically
for a course without the How I Teach page, and - the one that must not be
"tidied" - that the default is still rule 1 until Windows moves the C#, the
wrapper and the stamp together (`fingerprintRules.pythonDefault`).

Stdlib only and no Docker, so Windows' `PythonToolchainTests` discovers and
runs it too.
"""
import contextlib
import io
import tempfile
import unittest
from pathlib import Path

import contracts
import section_fingerprint
import toolchain_paths


def _rules() -> dict:
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()
    return contracts.load("app-rules")["publishedFreshness"]


class SectionFingerprintRuleTests(unittest.TestCase):

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.course = Path(self.temporary.name) / "ICS3U"
        self.write("course_config.json", "{}")
        self.write("Unit 1/Lesson.md", "# A shared lesson")
        self.write("section1/Classes/Unit 1, Day 1.md", "# Day one")

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, relative: str, text: str) -> None:
        path = self.course / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def fingerprint(self, rule: int) -> str:
        return section_fingerprint.fingerprint(str(self.course), 1, [], rule)

    def test_the_rule_2_cases_through_the_filter_and_the_walk(self):
        section = _rules()["filesCountedUnderRule2"]
        number = section["sectionNumber"]
        for case in section["cases"]:
            with self.subTest(case["path"]):
                self.assertEqual(
                    section_fingerprint.counts_toward_fingerprint(case["path"], number, 2),
                    case["counts"], case.get("why", ""))
                self.write(case["path"], "first")
                before = self.fingerprint(2)
                self.write(case["path"], "second, and longer")
                after = self.fingerprint(2)
                self.assertEqual(before != after, case["counts"], case.get("why", ""))
                (self.course / case["path"]).unlink()

    def test_the_rule_1_cases_still_hold_under_rule_2(self):
        for case in _rules()["filesCounted"]["cases"]:
            with self.subTest(case["path"]):
                self.assertEqual(
                    section_fingerprint.counts_toward_fingerprint(case["path"], 1, 2),
                    case["counts"])

    def test_a_course_without_the_page_hashes_the_same_under_both_rules(self):
        self.assertEqual(self.fingerprint(1), self.fingerprint(2))
        self.write("How I Teach.md", "# How I teach")
        self.assertNotEqual(self.fingerprint(1), self.fingerprint(2))

    def test_default_is_rule_1_until_windows_moves(self):
        """Its only caller is Windows' scheduled wrapper, whose value the C#
        app compares under ITS rule, 1, until the Windows half of #330 lands.
        A default of 2 here is a false "— Edited" for every scheduled Windows
        teacher whose course has the page."""
        self.write("How I Teach.md", "# How I teach")
        self.assertEqual(section_fingerprint.DEFAULT_RULE, 1)
        self.assertEqual(_rules()["fingerprintRules"]["absentMeans"], 1)
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            section_fingerprint.main(["section_fingerprint.py", str(self.course), "1"])
        self.assertEqual(printed.getvalue().strip(), self.fingerprint(1))

    def test_the_rule_flag_is_read_only_before_the_positional_arguments(self):
        self.write("How I Teach.md", "# How I teach")
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            section_fingerprint.main(["section_fingerprint.py", "--rule", "2", str(self.course), "1"])
        self.assertEqual(printed.getvalue().strip(), self.fingerprint(2))
        # After the positionals, "--rule" is an exclude path like any other.
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            section_fingerprint.main(["section_fingerprint.py", str(self.course), "1", "--rule", "2"])
        self.assertEqual(printed.getvalue().strip(), self.fingerprint(1))

    def test_a_rule_it_does_not_know_is_refused(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(section_fingerprint.main(
                ["section_fingerprint.py", "--rule", "3", str(self.course), "1"]), 2)


if __name__ == "__main__":
    unittest.main()
