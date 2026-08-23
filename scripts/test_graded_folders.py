#!/usr/bin/env python3
"""
Which folders count for marks, run against the SHARED contract.

The cases are deserialised from `contracts/shared-rules.json` -> gradedFolders,
never retyped. What they protect is a teacher's marks: an expectation counts as
ASSESSED when a page addressing it lives in one of these folders, and that is
what Ontario asks a course to be able to show.

`build_site` imports `frontmatter`, which lives only inside the container, so
this cannot run on the host. verify.sh runs it in the image.
"""
import unittest
from pathlib import Path

import build_site
import contracts
import toolchain_paths


class GradedFolderContractTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        cls.contract = contracts.section("shared-rules", "gradedFolders")

    def test_every_case(self):
        cases = self.contract["cases"]
        self.assertGreaterEqual(len(cases), 9, "the contract lost graded-folder cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                self.assertEqual(
                    build_site._is_graded_path(
                        case["path"], case["graded"], case["configured"]),
                    case["expect"],
                    case.get("why", ""))


class AbsentIsNotEmpty(unittest.TestCase):
    """
    The distinction the whole migration rests on. Getting it wrong breaks
    courses in both directions: treating absent as empty takes every assessed
    mark off every existing course, and treating empty as absent ignores a
    teacher who deliberately cleared the list.
    """

    def test_absent_means_the_historical_rule(self):
        names, configured = build_site.graded_folder_names({})
        self.assertEqual(names, [])
        self.assertFalse(configured)
        self.assertTrue(build_site._is_graded_path("Tasks/x.md", names, configured))
        self.assertTrue(
            build_site._is_graded_path("Thinking Tasks/x.md", names, configured),
            "a course that counted 'Thinking Tasks' yesterday must count it today")

    def test_empty_means_the_teacher_said_none(self):
        names, configured = build_site.graded_folder_names({"graded_folders": []})
        self.assertEqual(names, [])
        self.assertTrue(configured)
        self.assertFalse(build_site._is_graded_path("Tasks/x.md", names, configured))

    def test_a_configured_pool_is_taken_literally(self):
        names, configured = build_site.graded_folder_names(
            {"graded_folders": ["Tasks", "Tests"]})
        self.assertEqual(names, ["Tasks", "Tests"])
        self.assertTrue(configured)
        self.assertTrue(build_site._is_graded_path("Tests/quiz.md", names, configured))
        self.assertFalse(build_site._is_graded_path("Thinking Tasks/x.md", names, configured))

    def test_an_explicit_null_reads_as_cleared_not_unset(self):
        """
        The key is PRESENT, so the teacher has been asked. Absent is reserved
        for a course that never was. Both platforms agreed on this by accident
        and nothing said which answer was intended.
        """
        names, configured = build_site.graded_folder_names({"graded_folders": None})
        self.assertEqual(names, [])
        self.assertTrue(configured)
        self.assertFalse(build_site._is_graded_path("Tasks/x.md", names, configured))

    def test_blank_entries_are_ignored_rather_than_matching_everything(self):
        names, configured = build_site.graded_folder_names(
            {"graded_folders": ["", "Tasks", None]})
        self.assertEqual(names, ["Tasks"])
        self.assertFalse(build_site._is_graded_path("Concepts/x.md", names, configured))


if __name__ == "__main__":
    unittest.main(verbosity=2)
